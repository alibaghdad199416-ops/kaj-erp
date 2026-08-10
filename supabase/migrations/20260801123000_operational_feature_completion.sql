-- Quality Line ERP 18.8.0 - operational feature completion hotfix.
-- Completes per-user overrides, accounting reports, and maintenance deletion.
begin;

create or replace function public.erp_get_cloud_user_permission_override(
  p_user_id text
) returns jsonb
language plpgsql stable security definer set search_path=public
as $$
declare
  v_slug text;
  v_admin boolean;
  v_has_override boolean := false;
  v_codes text[] := array[]::text[];
begin
  select company_slug,is_admin into v_slug,v_admin
  from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  if not v_admin and p_user_id <> coalesce(
    (select local_user_id from public.company_memberships
      where user_uid=auth.uid()::text and is_active limit 1),
    auth.uid()::text
  ) then
    raise exception 'permission_denied';
  end if;

  select exists(
    select 1 from public.erp_records
    where company_id=v_slug
      and entity_type='user_permission_overrides'
      and record_id=p_user_id
      and deleted_at is null
      and not is_deleted
  ) into v_has_override;

  if v_has_override then
    select coalesce(array_agg(p.payload->>'code' order by p.payload->>'code'),array[]::text[])
      into v_codes
    from public.erp_records up
    join public.erp_records p
      on p.company_id=v_slug
     and p.entity_type='permissions'
     and p.record_id=up.payload->>'permissionId'
     and p.deleted_at is null
     and not p.is_deleted
    where up.company_id=v_slug
      and up.entity_type='user_permissions'
      and up.payload->>'userId'=p_user_id
      and up.deleted_at is null
      and not up.is_deleted;
  end if;

  return jsonb_build_object(
    'hasOverride',v_has_override,
    'codes',to_jsonb(coalesce(v_codes,array[]::text[]))
  );
end $$;

create or replace function public.erp_get_cloud_user_permissions(p_user_id text)
returns text[]
language plpgsql stable security definer set search_path=public
as $$
declare
  v_slug text;
  v_admin boolean;
  v_role_id text;
  v_result text[];
  v_override jsonb;
begin
  select company_slug,is_admin into v_slug,v_admin
  from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  if not v_admin and p_user_id <> coalesce(
    (select local_user_id from public.company_memberships
      where user_uid=auth.uid()::text and is_active limit 1),
    auth.uid()::text
  ) then
    raise exception 'permission_denied';
  end if;

  v_override := public.erp_get_cloud_user_permission_override(p_user_id);
  if coalesce((v_override->>'hasOverride')::boolean,false) then
    return array(
      select jsonb_array_elements_text(coalesce(v_override->'codes','[]'::jsonb))
    );
  end if;

  select payload->>'roleId' into v_role_id
  from public.erp_records
  where company_id=v_slug
    and entity_type='users'
    and record_id=p_user_id
    and deleted_at is null
    and not is_deleted
  limit 1;

  select array_agg(p.payload->>'code' order by p.payload->>'code') into v_result
  from public.erp_records rp
  join public.erp_records p
    on p.company_id=v_slug
   and p.entity_type='permissions'
   and p.record_id=rp.payload->>'permissionId'
   and p.deleted_at is null
   and not p.is_deleted
  where rp.company_id=v_slug
    and rp.entity_type='role_permissions'
    and rp.payload->>'roleId'=v_role_id
    and rp.deleted_at is null
    and not rp.is_deleted;
  return coalesce(v_result,array[]::text[]);
end $$;

create or replace function public.erp_set_cloud_user_permissions(
  p_user_id text,
  p_permission_codes text[]
) returns void
language plpgsql security definer set search_path=public
as $$
declare
  v_slug text;
  v_admin boolean;
  v_code text;
  v_permission_id text;
begin
  select company_slug,is_admin into v_slug,v_admin
  from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  if not v_admin then raise exception 'permission_denied'; end if;

  insert into public.erp_records(
    company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at
  ) values(
    v_slug,'user_permission_overrides',p_user_id,
    jsonb_build_object('userId',p_user_id,'enabled',true),false,null,now()
  ) on conflict(company_id,entity_type,record_id) do update
    set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();

  update public.erp_records
     set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=v_slug
     and entity_type='user_permissions'
     and payload->>'userId'=p_user_id
     and deleted_at is null;

  foreach v_code in array coalesce(p_permission_codes,array[]::text[]) loop
    select record_id into v_permission_id
    from public.erp_records
    where company_id=v_slug
      and entity_type='permissions'
      and payload->>'code'=v_code
      and deleted_at is null
      and not is_deleted
    limit 1;
    if v_permission_id is null then
      raise exception 'permission_code_not_found:%',v_code;
    end if;
    insert into public.erp_records(
      company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at
    ) values(
      v_slug,'user_permissions',p_user_id||'::'||v_permission_id,
      jsonb_build_object('userId',p_user_id,'permissionId',v_permission_id),
      false,null,now()
    ) on conflict(company_id,entity_type,record_id) do update
      set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();
  end loop;
end $$;

create or replace function public.erp_clear_cloud_user_permissions(
  p_user_id text
) returns void
language plpgsql security definer set search_path=public
as $$
declare
  v_slug text;
  v_admin boolean;
begin
  select company_slug,is_admin into v_slug,v_admin
  from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  if not v_admin then raise exception 'permission_denied'; end if;

  update public.erp_records
     set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=v_slug
     and entity_type in ('user_permission_overrides','user_permissions')
     and (
       record_id=p_user_id
       or payload->>'userId'=p_user_id
     )
     and deleted_at is null;
end $$;

revoke all on function public.erp_get_cloud_user_permission_override(text) from public,anon;
grant execute on function public.erp_get_cloud_user_permission_override(text) to authenticated;
revoke all on function public.erp_get_cloud_user_permissions(text) from public,anon;
grant execute on function public.erp_get_cloud_user_permissions(text) to authenticated;
revoke all on function public.erp_set_cloud_user_permissions(text,text[]) from public,anon;
grant execute on function public.erp_set_cloud_user_permissions(text,text[]) to authenticated;
revoke all on function public.erp_clear_cloud_user_permissions(text) from public,anon;
grant execute on function public.erp_clear_cloud_user_permissions(text) to authenticated;

create or replace function public.erp_cloud_detailed_accounting_report(
  p_company_id uuid,
  p_report_type text,
  p_currency text default 'ALL',
  p_branch_id text default null,
  p_cost_center_id text default null,
  p_from_date timestamptz default null,
  p_to_date timestamptz default null
) returns setof jsonb
language plpgsql security definer set search_path=public
as $$
begin
  if not public.is_active_company_member(p_company_id) then
    raise exception 'access denied';
  end if;

  if p_report_type='trialBalance' then
    return query
    with recursive account_tree as (
      select
        a.account_id,a.parent_account_id,a.code,a.name,a.account_type,
        a.currency,a.opening_balance,
        array[a.account_id]::text[] id_path,
        array[coalesce(a.name,'')]::text[] name_path,
        0 hierarchy_depth,
        a.code root_account_code,a.name root_account_name
      from public.erp_accounts a
      where a.organization_id=p_company_id and a.is_active
        and (
          a.parent_account_id is null
          or not exists(
            select 1 from public.erp_accounts parent
            where parent.organization_id=a.organization_id
              and parent.account_id=a.parent_account_id
              and parent.is_active
          )
        )
      union all
      select
        child.account_id,child.parent_account_id,child.code,child.name,
        child.account_type,child.currency,child.opening_balance,
        tree.id_path||child.account_id,
        tree.name_path||coalesce(child.name,''),
        tree.hierarchy_depth+1,
        tree.root_account_code,tree.root_account_name
      from public.erp_accounts child
      join account_tree tree
        on child.organization_id=p_company_id
       and child.parent_account_id=tree.account_id
      where child.is_active and not child.account_id=any(tree.id_path)
    ), posted_lines as (
      select
        jl.data->>'accountId' account_id,
        upper(coalesce(nullif(je.data->>'currency',''),'IQD')) currency,
        public.erp_try_timestamptz(je.data->>'entryDate',je.created_at) entry_date,
        public.erp_try_numeric(jl.data->>'debit',0::numeric) debit,
        public.erp_try_numeric(jl.data->>'credit',0::numeric) credit
      from public.erp_journal_lines jl
      join public.erp_journal_entries je
        on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
      where jl.company_id=p_company_id
        and not jl.is_deleted and not je.is_deleted
        and lower(coalesce(je.data->>'status',je.data->>'postingStatus','posted'))
          in ('posted','approved','confirmed')
        and (upper(p_currency)='ALL' or upper(coalesce(nullif(je.data->>'currency',''),'IQD'))=upper(p_currency))
        and (p_branch_id is null or coalesce(je.data->>'branchId',je.data->>'branch_id')=p_branch_id)
        and (p_cost_center_id is null or coalesce(jl.data->>'costCenterId',jl.data->>'cost_center_id',je.data->>'costCenterId',je.data->>'cost_center_id')=p_cost_center_id)
        and (p_to_date is null or public.erp_try_timestamptz(je.data->>'entryDate',je.created_at)<=p_to_date)
    ), balances as (
      select
        tree.*,
        upper(tree.currency) report_currency,
        case when tree.account_type in ('liability','equity','revenue')
          then -tree.opening_balance else tree.opening_balance end
          + coalesce(sum(line.debit-line.credit) filter(
              where p_from_date is not null and line.entry_date<p_from_date
            ),0) opening_signed,
        coalesce(sum(line.debit) filter(
          where p_from_date is null or line.entry_date>=p_from_date
        ),0) period_debit,
        coalesce(sum(line.credit) filter(
          where p_from_date is null or line.entry_date>=p_from_date
        ),0) period_credit
      from account_tree tree
      left join posted_lines line
        on line.account_id=tree.account_id
       and line.currency=upper(tree.currency)
      where upper(p_currency)='ALL' or upper(tree.currency)=upper(p_currency)
      group by
        tree.account_id,tree.parent_account_id,tree.code,tree.name,
        tree.account_type,tree.currency,tree.opening_balance,tree.id_path,
        tree.name_path,tree.hierarchy_depth,tree.root_account_code,
        tree.root_account_name
    ), final_balances as (
      select *,opening_signed+period_debit-period_credit closing_signed
      from balances
    )
    select jsonb_build_object(
      'accountId',account_id,
      'accountCode',code,
      'accountName',name,
      'accountType',account_type,
      'parentAccountId',parent_account_id,
      'rootAccountCode',coalesce(root_account_code,''),
      'rootAccountName',coalesce(root_account_name,''),
      'hierarchyPath',array_to_string(name_path,' / '),
      'hierarchyDepth',hierarchy_depth,
      'currency',report_currency,
      'openingDebit',greatest(opening_signed,0),
      'openingCredit',greatest(-opening_signed,0),
      'periodDebit',period_debit,
      'periodCredit',period_credit,
      'closingDebit',greatest(closing_signed,0),
      'closingCredit',greatest(-closing_signed,0),
      'debit',greatest(closing_signed,0),
      'credit',greatest(-closing_signed,0),
      'balance',case when account_type in ('liability','equity','revenue')
        then -closing_signed else closing_signed end
    )
    from final_balances
    where opening_signed<>0 or period_debit<>0 or period_credit<>0
    order by account_type,name_path;

  elsif p_report_type='generalLedger' then
    return query
    with recursive account_tree as (
      select
        a.account_id,a.parent_account_id,a.code,a.name,a.account_type,
        a.currency,a.opening_balance,
        array[a.account_id]::text[] id_path,
        array[coalesce(a.name,'')]::text[] name_path,
        0 hierarchy_depth,
        a.code root_account_code,a.name root_account_name
      from public.erp_accounts a
      where a.organization_id=p_company_id and a.is_active
        and (a.parent_account_id is null or not exists(
          select 1 from public.erp_accounts parent
          where parent.organization_id=a.organization_id
            and parent.account_id=a.parent_account_id and parent.is_active
        ))
      union all
      select
        child.account_id,child.parent_account_id,child.code,child.name,
        child.account_type,child.currency,child.opening_balance,
        tree.id_path||child.account_id,tree.name_path||coalesce(child.name,''),
        tree.hierarchy_depth+1,tree.root_account_code,tree.root_account_name
      from public.erp_accounts child
      join account_tree tree
        on child.organization_id=p_company_id
       and child.parent_account_id=tree.account_id
      where child.is_active and not child.account_id=any(tree.id_path)
    ), all_lines as (
      select
        tree.*,
        upper(coalesce(nullif(je.data->>'currency',''),tree.currency)) line_currency,
        public.erp_try_timestamptz(je.data->>'entryDate',je.created_at) entry_date,
        coalesce(je.data->>'entryNumber',je.id) entry_number,
        coalesce(jl.data->>'description',je.data->>'description','') description,
        coalesce(je.data->>'partyName',je.data->>'counterpartyName','') party_name,
        coalesce(je.data->>'referenceType',je.data->>'sourceType','') reference_type,
        coalesce(je.data->>'referenceId',je.data->>'sourceId','') reference_id,
        public.erp_try_numeric(jl.data->>'debit',0::numeric) debit,
        public.erp_try_numeric(jl.data->>'credit',0::numeric) credit,
        case when tree.account_type in ('liability','equity','revenue')
          then public.erp_try_numeric(jl.data->>'credit',0::numeric)
             - public.erp_try_numeric(jl.data->>'debit',0::numeric)
          else public.erp_try_numeric(jl.data->>'debit',0::numeric)
             - public.erp_try_numeric(jl.data->>'credit',0::numeric)
        end natural_delta,
        je.created_at,jl.created_at line_created_at
      from public.erp_journal_lines jl
      join public.erp_journal_entries je
        on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
      join account_tree tree on tree.account_id=jl.data->>'accountId'
      where jl.company_id=p_company_id
        and not jl.is_deleted and not je.is_deleted
        and lower(coalesce(je.data->>'status',je.data->>'postingStatus','posted'))
          in ('posted','approved','confirmed')
        and (upper(p_currency)='ALL' or upper(coalesce(nullif(je.data->>'currency',''),tree.currency))=upper(p_currency))
        and (p_branch_id is null or coalesce(je.data->>'branchId',je.data->>'branch_id')=p_branch_id)
        and (p_cost_center_id is null or coalesce(jl.data->>'costCenterId',jl.data->>'cost_center_id',je.data->>'costCenterId',je.data->>'cost_center_id')=p_cost_center_id)
        and (p_to_date is null or public.erp_try_timestamptz(je.data->>'entryDate',je.created_at)<=p_to_date)
    ), openings as (
      select account_id,line_currency,
        max(opening_balance)+coalesce(sum(natural_delta) filter(
          where p_from_date is not null and entry_date<p_from_date
        ),0) opening_natural
      from all_lines group by account_id,line_currency
    ), period_lines as (
      select line.*,
        coalesce(opening.opening_natural,line.opening_balance)
          + sum(line.natural_delta) over(
              partition by line.account_id,line.line_currency
              order by line.entry_date,line.created_at,line.line_created_at
              rows between unbounded preceding and current row
            ) running_balance,
        coalesce(opening.opening_natural,line.opening_balance) opening_balance_for_period
      from all_lines line
      left join openings opening
        on opening.account_id=line.account_id
       and opening.line_currency=line.line_currency
      where p_from_date is null or line.entry_date>=p_from_date
    )
    select jsonb_build_object(
      'entryDate',entry_date,
      'entryNumber',entry_number,
      'accountId',account_id,
      'accountCode',code,
      'accountName',name,
      'accountType',account_type,
      'parentAccountId',parent_account_id,
      'rootAccountCode',coalesce(root_account_code,''),
      'rootAccountName',coalesce(root_account_name,''),
      'hierarchyPath',array_to_string(name_path,' / '),
      'hierarchyDepth',hierarchy_depth,
      'description',description,
      'partyName',party_name,
      'referenceType',reference_type,
      'referenceId',reference_id,
      'currency',line_currency,
      'openingBalance',opening_balance_for_period,
      'debit',debit,
      'credit',credit,
      'runningBalance',running_balance
    ) from period_lines
    order by account_type,name_path,entry_date,created_at,line_created_at;

  elsif p_report_type='cashFlow' then
    return query
    with cash_rows as (
      select
        ct.*,
        lower(coalesce(ct.data->>'type','')) movement_type,
        public.erp_try_numeric(ct.data->>'amount',0::numeric) amount,
        public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at) movement_date,
        coalesce(ct.data->>'cashAccountId',ct.data->>'cash_account_id','') cash_account_id,
        lower(coalesce(ct.data->>'category',ct.data->>'referenceType','')) category_key
      from public.erp_cash_transactions ct
      where ct.company_id=p_company_id and not ct.is_deleted
        and (upper(p_currency)='ALL' or upper(coalesce(nullif(ct.data->>'currency',''),'IQD'))=upper(p_currency))
        and (p_branch_id is null or coalesce(ct.data->>'branchId',ct.data->>'branch_id')=p_branch_id)
        and (p_cost_center_id is null or coalesce(ct.data->>'costCenterId',ct.data->>'cost_center_id')=p_cost_center_id)
        and (p_from_date is null or public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at)>=p_from_date)
        and (p_to_date is null or public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at)<=p_to_date)
    )
    select jsonb_build_object(
      'entryDate',row.movement_date,
      'entryNumber',coalesce(row.data->>'voucherNumber',row.id),
      'flowSection',case
        when row.category_key similar to '%(capital|loan|financ|transfer|رأس|تمويل|قرض|تحويل)%' then 'financing'
        when row.category_key similar to '%(asset|fixed_asset|investment|أصل|اصول|أصول|استثمار)%' then 'investing'
        else 'operating'
      end,
      'cashAccountId',row.cash_account_id,
      'accountId',coalesce(account.account_id,''),
      'accountCode',coalesce(account.code,''),
      'accountName',coalesce(account.name,cash_account.data->>'name',row.data->>'accountName',''),
      'accountType',coalesce(account.account_type,'asset'),
      'hierarchyPath',coalesce(account.name,cash_account.data->>'name',row.data->>'accountName',''),
      'description',coalesce(row.data->>'description',row.data->>'notes',row.data->>'category',''),
      'partyName',coalesce(row.data->>'partyName',''),
      'paymentMethod',coalesce(row.data->>'paymentMethod',''),
      'referenceType',coalesce(row.data->>'referenceType',''),
      'referenceId',coalesce(row.data->>'referenceId',''),
      'currency',upper(coalesce(nullif(row.data->>'currency',''),'IQD')),
      'debit',case when row.movement_type in ('income','receipt','in','cash_in','customer_receipt','transfer_in') then row.amount else 0 end,
      'credit',case when row.movement_type in ('expense','payment','out','cash_out','supplier_payment','transfer_out') then row.amount else 0 end,
      'cashIn',case when row.movement_type in ('income','receipt','in','cash_in','customer_receipt','transfer_in') then row.amount else 0 end,
      'cashOut',case when row.movement_type in ('expense','payment','out','cash_out','supplier_payment','transfer_out') then row.amount else 0 end,
      'netCashFlow',case
        when row.movement_type in ('income','receipt','in','cash_in','customer_receipt','transfer_in') then row.amount
        when row.movement_type in ('expense','payment','out','cash_out','supplier_payment','transfer_out') then -row.amount
        else 0
      end
    )
    from cash_rows row
    left join public.erp_cash_accounts cash_account
      on cash_account.company_id=p_company_id
     and cash_account.id=row.cash_account_id
     and not cash_account.is_deleted
    left join public.erp_accounts account
      on account.organization_id=p_company_id
     and account.account_id=coalesce(cash_account.data->>'accountId',cash_account.data->>'account_id')
     and account.is_active
    order by row.movement_date,row.created_at;
  else
    return query select * from public.erp_cloud_professional_accounting_report(
      p_company_id,p_report_type,p_currency,p_branch_id,p_cost_center_id,
      p_from_date,p_to_date
    );
  end if;
end $$;

revoke all on function public.erp_cloud_detailed_accounting_report(uuid,text,text,text,text,timestamptz,timestamptz) from public,anon;
grant execute on function public.erp_cloud_detailed_accounting_report(uuid,text,text,text,text,timestamptz,timestamptz) to authenticated;

create or replace function public.erp_delete_cloud_maintenance_order(
  p_company_id uuid,
  p_order_id uuid,
  p_reason text default null
) returns void
language plpgsql security definer set search_path=public
as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_reason text := coalesce(nullif(btrim(p_reason),''),'حذف أمر الصيانة وتحديث ارتباطاته');
begin
  perform public.erp_active_company_context(p_company_id);
  select * into v_order
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id
  for update;
  if not found then raise exception 'أمر الصيانة غير موجود'; end if;
  if v_order.is_deleted then return; end if;

  begin
    perform public.erp_cancel_cloud_maintenance_order(
      p_company_id,p_order_id,v_reason
    );
  exception when others then
    -- Legacy orders can have incomplete links. The direct cleanup below keeps
    -- them deletable while preserving the successfully reversed paths.
    null;
  end;

  begin perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_stock_issue',p_order_id::text); exception when others then null; end;
  begin perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_invoice',p_order_id::text); exception when others then null; end;
  begin perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_payment',p_order_id::text); exception when others then null; end;
  begin perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance',p_order_id::text); exception when others then null; end;

  update public.erp_inventory_movements
     set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=p_company_id and not is_deleted
     and coalesce(data->>'referenceId',data->>'reference_id',data->>'maintenanceOrderId')=p_order_id::text;

  update public.erp_cash_transactions
     set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=p_company_id and not is_deleted
     and coalesce(data->>'referenceId',data->>'reference_id',data->>'maintenanceOrderId')=p_order_id::text;

  update public.erp_maintenance_parts
     set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=p_company_id
     and maintenance_order_id=p_order_id
     and not is_deleted;

  update public.erp_maintenance_payments
     set is_deleted=true,deleted_at=now()
   where company_id=p_company_id
     and maintenance_order_id=p_order_id
     and not is_deleted;

  update public.erp_maintenance_orders
     set paid_amount=0,
         status='cancelled',
         workflow_stage='cancelled',
         cancel_reason=v_reason,
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
