-- Quality Line ERP 18.6.6 - per-user permission overrides and final web acceptance.
begin;

create or replace function public.erp_get_cloud_user_permissions(p_user_id text)
returns text[]
language plpgsql stable security definer set search_path=public
as $$
declare v_slug text; v_admin boolean; v_role_id text; v_result text[];
begin
  select company_slug,is_admin into v_slug,v_admin from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  if not v_admin and p_user_id <> coalesce((select local_user_id from public.company_memberships where user_uid=auth.uid()::text and is_active limit 1), auth.uid()::text) then
    raise exception 'permission_denied';
  end if;
  select payload->>'roleId' into v_role_id from public.erp_records
   where company_id=v_slug and entity_type='users' and record_id=p_user_id and deleted_at is null limit 1;
  select array_agg(p.payload->>'code' order by p.payload->>'code') into v_result
  from public.erp_records up
  join public.erp_records p on p.company_id=v_slug and p.entity_type='permissions'
    and p.record_id=up.payload->>'permissionId' and p.deleted_at is null
  where up.company_id=v_slug and up.entity_type='user_permissions'
    and up.payload->>'userId'=p_user_id and up.deleted_at is null;
  if coalesce(array_length(v_result,1),0)>0 then return v_result; end if;
  select array_agg(p.payload->>'code' order by p.payload->>'code') into v_result
  from public.erp_records rp
  join public.erp_records p on p.company_id=v_slug and p.entity_type='permissions'
    and p.record_id=rp.payload->>'permissionId' and p.deleted_at is null
  where rp.company_id=v_slug and rp.entity_type='role_permissions'
    and rp.payload->>'roleId'=v_role_id and rp.deleted_at is null;
  return coalesce(v_result,array[]::text[]);
end $$;

create or replace function public.erp_set_cloud_user_permissions(p_user_id text,p_permission_codes text[])
returns void language plpgsql security definer set search_path=public
as $$
declare v_slug text; v_admin boolean; v_code text; v_permission_id text;
begin
  select company_slug,is_admin into v_slug,v_admin from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  if not v_admin then raise exception 'permission_denied'; end if;
  update public.erp_records set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=v_slug and entity_type='user_permissions' and payload->>'userId'=p_user_id and deleted_at is null;
  foreach v_code in array coalesce(p_permission_codes,array[]::text[]) loop
    select record_id into v_permission_id from public.erp_records
     where company_id=v_slug and entity_type='permissions' and payload->>'code'=v_code and deleted_at is null limit 1;
    if v_permission_id is null then raise exception 'permission_code_not_found:%',v_code; end if;
    insert into public.erp_records(company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at)
    values(v_slug,'user_permissions',p_user_id||'::'||v_permission_id,jsonb_build_object('userId',p_user_id,'permissionId',v_permission_id),false,null,now())
    on conflict(company_id,entity_type,record_id) do update set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();
  end loop;
end $$;

revoke all on function public.erp_get_cloud_user_permissions(text) from public,anon;
grant execute on function public.erp_get_cloud_user_permissions(text) to authenticated;
revoke all on function public.erp_set_cloud_user_permissions(text,text[]) from public,anon;
grant execute on function public.erp_set_cloud_user_permissions(text,text[]) to authenticated;

commit;

-- Detailed accounting movements for Trial Balance, General Ledger and Cash In/Out.
create or replace function public.erp_cloud_detailed_accounting_report(
  p_company_id uuid,p_report_type text,p_currency text default 'ALL',
  p_branch_id text default null,p_cost_center_id text default null,
  p_from_date timestamptz default null,p_to_date timestamptz default null
) returns setof jsonb language plpgsql security definer set search_path=public as $$
begin
  if not public.is_active_company_member(p_company_id) then raise exception 'access denied'; end if;
  if p_report_type in ('trialBalance','generalLedger') then
    return query
    with lines as (
      select a.code account_code,a.name account_name,a.account_type,a.parent_id,
        coalesce(nullif(je.data->>'currency',''),a.currency) currency,
        (je.data->>'entryDate')::timestamptz entry_date,je.data->>'entryNumber' entry_number,
        coalesce(jl.data->>'description',je.data->>'description','') description,
        coalesce((jl.data->>'debit')::numeric,0) debit,
        coalesce((jl.data->>'credit')::numeric,0) credit,
        a.opening_balance,je.created_at,jl.created_at line_created_at
      from public.erp_journal_lines jl
      join public.erp_journal_entries je on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
      join public.erp_accounts a on a.organization_id=jl.company_id and a.account_id=jl.data->>'accountId'
      where jl.company_id=p_company_id and not jl.is_deleted and not je.is_deleted and a.is_active
        and je.data->>'status'='posted'
        and (p_currency='ALL' or coalesce(nullif(je.data->>'currency',''),a.currency)=p_currency)
        and (p_branch_id is null or je.data->>'branchId'=p_branch_id)
        and (p_cost_center_id is null or coalesce(jl.data->>'costCenterId',je.data->>'costCenterId')=p_cost_center_id)
        and (p_from_date is null or (je.data->>'entryDate')::timestamptz>=p_from_date)
        and (p_to_date is null or (je.data->>'entryDate')::timestamptz<=p_to_date)
    ), running as (
      select *,opening_balance+sum(case when account_type in ('liability','equity','revenue') then credit-debit else debit-credit end)
      over(partition by account_code,currency order by entry_date,created_at,line_created_at rows between unbounded preceding and current row) running_balance
      from lines
    )
    select jsonb_build_object('entryDate',entry_date,'entryNumber',entry_number,'accountCode',account_code,
      'accountName',account_name,'accountType',account_type,'parentAccountId',parent_id,'description',description,
      'currency',currency,'debit',debit,'credit',credit,'runningBalance',running_balance)
    from running order by account_type,account_code,entry_date,created_at,line_created_at;
  elsif p_report_type='cashFlow' then
    return query
    select jsonb_build_object(
      'entryDate',(ct.data->>'transactionDate')::timestamptz,
      'entryNumber',coalesce(ct.data->>'voucherNumber',ct.id),
      'accountCode',coalesce(a.code,''),'accountName',coalesce(a.name,ct.data->>'accountName',''),
      'accountType','asset','description',coalesce(ct.data->>'description',ct.data->>'notes',ct.data->>'category',''),
      'partyName',coalesce(ct.data->>'partyName',''),'paymentMethod',coalesce(ct.data->>'paymentMethod',''),
      'referenceType',coalesce(ct.data->>'referenceType',''),'referenceId',coalesce(ct.data->>'referenceId',''),
      'currency',coalesce(nullif(ct.data->>'currency',''),'IQD'),
      'cashIn',case when ct.data->>'type' in ('income','receipt','in','customer_receipt','transfer_in') then coalesce((ct.data->>'amount')::numeric,0) else 0 end,
      'cashOut',case when ct.data->>'type' in ('expense','payment','out','supplier_payment','transfer_out') then coalesce((ct.data->>'amount')::numeric,0) else 0 end,
      'netCashFlow',case when ct.data->>'type' in ('income','receipt','in','customer_receipt','transfer_in') then coalesce((ct.data->>'amount')::numeric,0) else -coalesce((ct.data->>'amount')::numeric,0) end
    )
    from public.erp_cash_transactions ct
    left join public.erp_accounts a on a.organization_id=ct.company_id and a.account_id=ct.data->>'accountId'
    where ct.company_id=p_company_id and not ct.is_deleted
      and (p_currency='ALL' or ct.data->>'currency'=p_currency)
      and (p_from_date is null or (ct.data->>'transactionDate')::timestamptz>=p_from_date)
      and (p_to_date is null or (ct.data->>'transactionDate')::timestamptz<=p_to_date)
    order by (ct.data->>'transactionDate')::timestamptz,ct.created_at;
  else
    return query select * from public.erp_cloud_professional_accounting_report(
      p_company_id,p_report_type,p_currency,p_branch_id,p_cost_center_id,p_from_date,p_to_date);
  end if;
end $$;
revoke all on function public.erp_cloud_detailed_accounting_report(uuid,text,text,text,text,timestamptz,timestamptz) from public,anon;
grant execute on function public.erp_cloud_detailed_accounting_report(uuid,text,text,text,text,timestamptz,timestamptz) to authenticated;

-- Deleting a maintenance order reverses linked inventory/journals first when possible.
create or replace function public.erp_delete_cloud_maintenance_order(p_company_id uuid,p_order_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
declare o public.erp_maintenance_orders%rowtype;
begin
 perform public.erp_active_company_context(p_company_id);
 select * into o from public.erp_maintenance_orders where company_id=p_company_id and id=p_order_id and not is_deleted for update;
 if not found then raise exception 'أمر الصيانة غير موجود'; end if;
 if o.paid_amount>0 then raise exception 'يجب عكس دفعات الصيانة قبل حذف الأمر'; end if;
 if o.workflow_stage not in ('order_draft','order_approved','cancelled') then
   perform public.erp_cancel_cloud_maintenance_order(p_company_id,p_order_id,coalesce(nullif(btrim(p_reason),''),'حذف أمر الصيانة'));
 end if;
 perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_stock_issue',p_order_id::text);
 update public.erp_maintenance_parts set is_deleted=true,deleted_at=now(),updated_at=now() where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;
 update public.erp_maintenance_payments set is_deleted=true,deleted_at=now() where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;
 update public.erp_maintenance_orders set is_deleted=true,deleted_at=now(),deleted_by=auth.uid(),deleted_reason=nullif(btrim(p_reason),''),updated_at=now() where id=p_order_id;
end $$;
grant execute on function public.erp_delete_cloud_maintenance_order(uuid,uuid,text) to authenticated;
