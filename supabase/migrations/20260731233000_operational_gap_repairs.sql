-- Quality Line ERP 18.6.6 - operational gap repairs verified from live web acceptance.
begin;

-- Detailed reports: use the real account hierarchy column and accept all posted
-- status aliases used by historical and current journal records.
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
      select a.account_id,a.code account_code,a.name account_name,a.account_type,
        a.parent_account_id,
        pa.code parent_account_code,pa.name parent_account_name,
        coalesce(nullif(je.data->>'currency',''),a.currency) currency,
        coalesce(nullif(je.data->>'entryDate','')::timestamptz,je.created_at) entry_date,
        coalesce(je.data->>'entryNumber',je.id) entry_number,
        coalesce(jl.data->>'description',je.data->>'description','') description,
        public.erp_try_numeric(jl.data->>'debit',0) debit,
        public.erp_try_numeric(jl.data->>'credit',0) credit,
        a.opening_balance,je.created_at,jl.created_at line_created_at
      from public.erp_journal_lines jl
      join public.erp_journal_entries je on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
      join public.erp_accounts a on a.organization_id=jl.company_id and a.account_id=jl.data->>'accountId'
      left join public.erp_accounts pa on pa.organization_id=a.organization_id and pa.account_id=a.parent_account_id
      where jl.company_id=p_company_id and not jl.is_deleted and not je.is_deleted and a.is_active
        and lower(coalesce(je.data->>'status',je.data->>'postingStatus','posted')) in ('posted','approved','confirmed')
        and (upper(p_currency)='ALL' or upper(coalesce(nullif(je.data->>'currency',''),a.currency))=upper(p_currency))
        and (p_branch_id is null or coalesce(je.data->>'branchId',je.data->>'branch_id')=p_branch_id)
        and (p_cost_center_id is null or coalesce(jl.data->>'costCenterId',jl.data->>'cost_center_id',je.data->>'costCenterId',je.data->>'cost_center_id')=p_cost_center_id)
        and (p_from_date is null or coalesce(nullif(je.data->>'entryDate','')::timestamptz,je.created_at)>=p_from_date)
        and (p_to_date is null or coalesce(nullif(je.data->>'entryDate','')::timestamptz,je.created_at)<=p_to_date)
    ), running as (
      select *,opening_balance+sum(case when account_type in ('liability','equity','revenue') then credit-debit else debit-credit end)
      over(partition by account_id,currency order by entry_date,created_at,line_created_at rows between unbounded preceding and current row) running_balance
      from lines
    )
    select jsonb_build_object(
      'entryDate',entry_date,'entryNumber',entry_number,
      'accountId',account_id,'accountCode',account_code,'accountName',account_name,
      'accountType',account_type,'parentAccountId',parent_account_id,
      'parentAccountCode',coalesce(parent_account_code,''),'parentAccountName',coalesce(parent_account_name,''),
      'description',description,'currency',currency,'debit',debit,'credit',credit,
      'runningBalance',running_balance)
    from running order by account_type,coalesce(parent_account_code,account_code),account_code,entry_date,created_at,line_created_at;
  elsif p_report_type='cashFlow' then
    return query
    select jsonb_build_object(
      'entryDate',coalesce(nullif(ct.data->>'transactionDate','')::timestamptz,ct.created_at),
      'entryNumber',coalesce(ct.data->>'voucherNumber',ct.id),
      'accountId',coalesce(ct.data->>'accountId',ct.data->>'account_id',''),
      'accountCode',coalesce(a.code,''),'accountName',coalesce(a.name,ct.data->>'accountName',''),
      'accountType',coalesce(a.account_type,'asset'),'parentAccountId',a.parent_account_id,
      'description',coalesce(ct.data->>'description',ct.data->>'notes',ct.data->>'category',''),
      'partyName',coalesce(ct.data->>'partyName',''),'paymentMethod',coalesce(ct.data->>'paymentMethod',''),
      'referenceType',coalesce(ct.data->>'referenceType',''),'referenceId',coalesce(ct.data->>'referenceId',''),
      'currency',upper(coalesce(nullif(ct.data->>'currency',''),'IQD')),
      'cashIn',case when lower(coalesce(ct.data->>'type','')) in ('income','receipt','in','cash_in','customer_receipt','transfer_in') then public.erp_try_numeric(ct.data->>'amount',0) else 0 end,
      'cashOut',case when lower(coalesce(ct.data->>'type','')) in ('expense','payment','out','cash_out','supplier_payment','transfer_out') then public.erp_try_numeric(ct.data->>'amount',0) else 0 end,
      'netCashFlow',case when lower(coalesce(ct.data->>'type','')) in ('income','receipt','in','cash_in','customer_receipt','transfer_in') then public.erp_try_numeric(ct.data->>'amount',0) else -public.erp_try_numeric(ct.data->>'amount',0) end
    )
    from public.erp_cash_transactions ct
    left join public.erp_accounts a on a.organization_id=ct.company_id and a.account_id=coalesce(ct.data->>'accountId',ct.data->>'account_id')
    where ct.company_id=p_company_id and not ct.is_deleted
      and (upper(p_currency)='ALL' or upper(coalesce(nullif(ct.data->>'currency',''),'IQD'))=upper(p_currency))
      and (p_branch_id is null or coalesce(ct.data->>'branchId',ct.data->>'branch_id')=p_branch_id)
      and (p_from_date is null or coalesce(nullif(ct.data->>'transactionDate','')::timestamptz,ct.created_at)>=p_from_date)
      and (p_to_date is null or coalesce(nullif(ct.data->>'transactionDate','')::timestamptz,ct.created_at)<=p_to_date)
    order by coalesce(a.code,''),coalesce(nullif(ct.data->>'transactionDate','')::timestamptz,ct.created_at),ct.created_at;
  else
    return query select * from public.erp_cloud_professional_accounting_report(
      p_company_id,p_report_type,p_currency,p_branch_id,p_cost_center_id,p_from_date,p_to_date);
  end if;
end $$;

-- Maintenance deletion now reverses linked workflow, stock, journals and payment
-- records in one transaction. Existing paid orders can be removed after their
-- linked payment journals are voided automatically.
create or replace function public.erp_delete_cloud_maintenance_order(p_company_id uuid,p_order_id uuid,p_reason text default null)
returns void language plpgsql security definer set search_path=public as $$
declare o public.erp_maintenance_orders%rowtype;
begin
 perform public.erp_active_company_context(p_company_id);
 select * into o from public.erp_maintenance_orders where company_id=p_company_id and id=p_order_id and not is_deleted for update;
 if not found then raise exception 'أمر الصيانة غير موجود'; end if;
 if o.workflow_stage not in ('order_draft','cancelled') then
   perform public.erp_cancel_cloud_maintenance_order(p_company_id,p_order_id,coalesce(nullif(btrim(p_reason),''),'حذف أمر الصيانة'));
 end if;
 perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_stock_issue',p_order_id::text);
 perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_invoice',p_order_id::text);
 perform public.erp_phase2_void_reference_journals(p_company_id,'maintenance_payment',p_order_id::text);
 update public.erp_maintenance_parts set is_deleted=true,deleted_at=now(),updated_at=now() where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;
 update public.erp_maintenance_payments set is_deleted=true,deleted_at=now() where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;
 update public.erp_maintenance_orders set paid_amount=0,is_deleted=true,deleted_at=now(),deleted_by=auth.uid(),deleted_reason=coalesce(nullif(btrim(p_reason),''),'حذف أمر الصيانة'),updated_at=now() where company_id=p_company_id and id=p_order_id;
end $$;
revoke all on function public.erp_delete_cloud_maintenance_order(uuid,uuid,text) from public,anon;
grant execute on function public.erp_delete_cloud_maintenance_order(uuid,uuid,text) to authenticated;

commit;
