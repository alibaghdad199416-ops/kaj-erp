-- Quality Line ERP 18.6.6 - Stage 12 live workspace, recursive reports and maintenance deletion hardening.
begin;

create or replace function public.erp_cloud_detailed_accounting_report(
  p_company_id uuid,p_report_type text,p_currency text default 'ALL',
  p_branch_id text default null,p_cost_center_id text default null,
  p_from_date timestamptz default null,p_to_date timestamptz default null
) returns setof jsonb language plpgsql security definer set search_path=public as $$
begin
  if not public.is_active_company_member(p_company_id) then
    raise exception 'access denied';
  end if;

  if p_report_type in ('trialBalance','generalLedger','cashFlow') then
    return query
    with recursive account_tree as (
      select
        a.account_id,
        a.parent_account_id,
        a.code,
        a.name,
        a.account_type,
        a.currency,
        a.opening_balance,
        array[a.account_id::text] as id_path,
        array[coalesce(a.code,'')] as code_path,
        array[coalesce(a.name,'')] as name_path,
        0 as hierarchy_depth,
        a.code as root_account_code,
        a.name as root_account_name
      from public.erp_accounts a
      where a.organization_id=p_company_id
        and a.is_active
        and (
          a.parent_account_id is null
          or not exists (
            select 1 from public.erp_accounts parent
            where parent.organization_id=a.organization_id
              and parent.account_id=a.parent_account_id
              and parent.is_active
          )
        )
      union all
      select
        child.account_id,
        child.parent_account_id,
        child.code,
        child.name,
        child.account_type,
        child.currency,
        child.opening_balance,
        tree.id_path || child.account_id::text,
        tree.code_path || coalesce(child.code,''),
        tree.name_path || coalesce(child.name,''),
        tree.hierarchy_depth + 1,
        tree.root_account_code,
        tree.root_account_name
      from public.erp_accounts child
      join account_tree tree
        on child.organization_id=p_company_id
       and child.parent_account_id=tree.account_id
      where child.is_active
        and not child.account_id::text=any(tree.id_path)
    ), lines as (
      select
        tree.account_id,
        tree.code account_code,
        tree.name account_name,
        tree.account_type,
        tree.parent_account_id,
        tree.root_account_code,
        tree.root_account_name,
        tree.code_path,
        tree.name_path,
        tree.hierarchy_depth,
        coalesce(nullif(je.data->>'currency',''),tree.currency) currency,
        coalesce(nullif(je.data->>'entryDate','')::timestamptz,je.created_at) entry_date,
        coalesce(je.data->>'entryNumber',je.id) entry_number,
        coalesce(jl.data->>'description',je.data->>'description','') description,
        coalesce(je.data->>'referenceType',je.data->>'sourceType','') reference_type,
        coalesce(je.data->>'referenceId',je.data->>'sourceId','') reference_id,
        coalesce(je.data->>'partyName',je.data->>'counterpartyName','') party_name,
        public.erp_try_numeric(jl.data->>'debit',0) debit,
        public.erp_try_numeric(jl.data->>'credit',0) credit,
        tree.opening_balance,
        je.created_at,
        jl.created_at line_created_at
      from public.erp_journal_lines jl
      join public.erp_journal_entries je
        on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
      join account_tree tree on tree.account_id=jl.data->>'accountId'
      where jl.company_id=p_company_id
        and not jl.is_deleted
        and not je.is_deleted
        and lower(coalesce(je.data->>'status',je.data->>'postingStatus','posted'))
          in ('posted','approved','confirmed')
        and (upper(p_currency)='ALL' or upper(coalesce(nullif(je.data->>'currency',''),tree.currency))=upper(p_currency))
        and (p_branch_id is null or coalesce(je.data->>'branchId',je.data->>'branch_id')=p_branch_id)
        and (p_cost_center_id is null or coalesce(jl.data->>'costCenterId',jl.data->>'cost_center_id',je.data->>'costCenterId',je.data->>'cost_center_id')=p_cost_center_id)
        and (p_from_date is null or coalesce(nullif(je.data->>'entryDate','')::timestamptz,je.created_at)>=p_from_date)
        and (p_to_date is null or coalesce(nullif(je.data->>'entryDate','')::timestamptz,je.created_at)<=p_to_date)
    ), running as (
      select *, opening_balance + sum(
        case when account_type in ('liability','equity','revenue')
          then credit-debit else debit-credit end
      ) over(
        partition by account_id,currency
        order by entry_date,created_at,line_created_at
        rows between unbounded preceding and current row
      ) running_balance
      from lines
    )
    select jsonb_build_object(
      'entryDate',entry_date,
      'entryNumber',entry_number,
      'accountId',account_id,
      'accountCode',account_code,
      'accountName',account_name,
      'accountType',account_type,
      'parentAccountId',parent_account_id,
      'rootAccountCode',coalesce(root_account_code,''),
      'rootAccountName',coalesce(root_account_name,''),
      'hierarchyCodes',code_path,
      'hierarchyNames',name_path,
      'hierarchyPath',array_to_string(name_path,' / '),
      'hierarchyDepth',hierarchy_depth,
      'description',description,
      'partyName',party_name,
      'referenceType',reference_type,
      'referenceId',reference_id,
      'currency',currency,
      'debit',debit,
      'credit',credit,
      'cashIn',case when p_report_type='cashFlow' then debit else 0 end,
      'cashOut',case when p_report_type='cashFlow' then credit else 0 end,
      'netCashFlow',case when p_report_type='cashFlow' then debit-credit else 0 end,
      'runningBalance',running_balance
    )
    from running
    order by account_type,code_path,entry_date,created_at,line_created_at;
  else
    return query select * from public.erp_cloud_professional_accounting_report(
      p_company_id,p_report_type,p_currency,p_branch_id,p_cost_center_id,p_from_date,p_to_date
    );
  end if;
end $$;

create or replace function public.erp_delete_cloud_maintenance_order(
  p_company_id uuid,p_order_id uuid,p_reason text default null
) returns void language plpgsql security definer set search_path=public as $$
declare
  o public.erp_maintenance_orders%rowtype;
  v_reason text := coalesce(nullif(btrim(p_reason),''),'حذف أمر الصيانة');
begin
  perform public.erp_active_company_context(p_company_id);
  select * into o
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted
  for update;
  if not found then raise exception 'أمر الصيانة غير موجود'; end if;

  begin
    if o.workflow_stage not in ('order_draft','cancelled') then
      perform public.erp_cancel_cloud_maintenance_order(p_company_id,p_order_id,v_reason);
    end if;
  exception when others then
    -- Legacy orders can have incomplete workflow links. Continue with direct
    -- reversal below so an old malformed order does not become undeletable.
    null;
  end;

  begin perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_stock_issue',p_order_id::text); exception when others then null; end;
  begin perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_invoice',p_order_id::text); exception when others then null; end;
  begin perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_payment',p_order_id::text); exception when others then null; end;
  begin perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance',p_order_id::text); exception when others then null; end;

  update public.erp_maintenance_parts
     set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;

  update public.erp_maintenance_payments
     set is_deleted=true,deleted_at=now()
   where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;

  update public.erp_maintenance_orders
     set paid_amount=0,
         workflow_stage='cancelled',
         is_deleted=true,
         deleted_at=now(),
         deleted_by=auth.uid(),
         deleted_reason=v_reason,
         updated_at=now()
   where company_id=p_company_id and id=p_order_id;
end $$;

revoke all on function public.erp_delete_cloud_maintenance_order(uuid,uuid,text) from public,anon;
grant execute on function public.erp_delete_cloud_maintenance_order(uuid,uuid,text) to authenticated;

commit;
