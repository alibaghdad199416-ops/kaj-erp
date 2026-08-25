-- R49 focused final closure: accounting-correct profit KPI and installment write-surface hardening.
-- Forward-only. Historical migrations remain untouched.
begin;

create or replace function public.erp_r49_accounting_net_profit_by_currency(
  p_company_id uuid,
  p_from_date date default null,
  p_to_date date default null
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_result jsonb := '{}'::jsonb;
  v_invalid integer := 0;
begin
  perform public.erp_active_company_context(p_company_id);

  -- A posted P&L line must resolve to a supported account currency. Never
  -- manufacture USD/IQD for malformed accounting master data.
  select count(*) into v_invalid
  from public.erp_journal_lines jl
  join public.erp_journal_entries je
    on je.company_id=jl.company_id
   and je.id=jl.data->>'entryId'
   and not je.is_deleted
  join public.erp_accounts a
    on a.organization_id=jl.company_id
   and a.account_id=jl.data->>'accountId'
  where jl.company_id=p_company_id
    and not jl.is_deleted
    and a.is_active
    and a.account_type in ('revenue','expense')
    and je.data->>'status'='posted'
    and (p_from_date is null or coalesce(public.erp_try_date(je.data->>'entryDate',null),je.created_at::date)>=p_from_date)
    and (p_to_date is null or coalesce(public.erp_try_date(je.data->>'entryDate',null),je.created_at::date)<=p_to_date)
    and public.erp_r49_normalize_supported_currency(a.currency) is null;
  if v_invalid>0 then
    raise exception 'financial_account_currency_invalid:%',v_invalid using errcode='22023';
  end if;

  with balances as (
    select
      public.erp_r49_normalize_supported_currency(a.currency) currency,
      sum(
        case when a.account_type='revenue'
          then public.erp_try_numeric(jl.data->>'credit',0)-public.erp_try_numeric(jl.data->>'debit',0)
          else public.erp_try_numeric(jl.data->>'debit',0)-public.erp_try_numeric(jl.data->>'credit',0)
        end
      ) amount
    from public.erp_journal_lines jl
    join public.erp_journal_entries je
      on je.company_id=jl.company_id
     and je.id=jl.data->>'entryId'
     and not je.is_deleted
    join public.erp_accounts a
      on a.organization_id=jl.company_id
     and a.account_id=jl.data->>'accountId'
    where jl.company_id=p_company_id
      and not jl.is_deleted
      and a.is_active
      and a.account_type in ('revenue','expense')
      and je.data->>'status'='posted'
      and (p_from_date is null or coalesce(public.erp_try_date(je.data->>'entryDate',null),je.created_at::date)>=p_from_date)
      and (p_to_date is null or coalesce(public.erp_try_date(je.data->>'entryDate',null),je.created_at::date)<=p_to_date)
    group by 1
  ), currencies as (
    select unnest(array['USD','IQD']) currency
  )
  select jsonb_object_agg(c.currency,coalesce(b.amount,0))
  into v_result
  from currencies c
  left join balances b on b.currency=c.currency;

  return coalesce(v_result,'{}'::jsonb);
end;
$$;

-- R49 browser endpoints preserve the existing R9 field/tenant permission
-- filtering, then replace only the visible per-currency profit KPI with the
-- accounting ledger source of truth (Revenue - Expense).
create or replace function public.erp_r49_cloud_dashboard_snapshot(
  p_company_id uuid,
  p_reference_day date default current_date
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v jsonb;
  v_profit jsonb;
begin
  v:=public.erp_r9_cloud_dashboard_snapshot(p_company_id,p_reference_day);
  if v ? 'netProfitByCurrency' then
    v_profit:=public.erp_r49_accounting_net_profit_by_currency(p_company_id,null,p_reference_day);
    v:=jsonb_set(v,'{netProfitByCurrency}',v_profit,true);
  end if;
  return v;
end;
$$;

create or replace function public.erp_r49_cloud_reports_summary(
  p_company_id uuid,
  p_start_date date default null,
  p_end_date date default null
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v jsonb;
  v_profit jsonb;
  d1 date:=coalesce(p_start_date,current_date-365);
  d2 date:=coalesce(p_end_date,current_date);
begin
  if d1>d2 then raise exception 'invalid_report_date_range' using errcode='22023'; end if;
  v:=public.erp_r9_cloud_reports_summary(p_company_id,p_start_date,p_end_date);
  if v ? 'netProfitByCurrency' then
    v_profit:=public.erp_r49_accounting_net_profit_by_currency(p_company_id,d1,d2);
    v:=jsonb_set(v,'{netProfitByCurrency}',v_profit,true);
  end if;
  return v;
end;
$$;

-- Installment schedules are owned by the sales workflow. The current UI is
-- read-only for schedule rows and collections flow through canonical payment
-- operations. Keep historical standalone schedule mutators internal so a
-- browser cannot bypass sales/payment permissions by calling them directly.
revoke all on function public.erp_save_cloud_installment(uuid,jsonb) from public,anon,authenticated;
revoke all on function public.erp_delete_cloud_installment(uuid,text) from public,anon,authenticated;
revoke all on function public.erp_cloud_installment_totals(uuid) from public,anon,authenticated;
grant execute on function public.erp_save_cloud_installment(uuid,jsonb) to service_role;
grant execute on function public.erp_delete_cloud_installment(uuid,text) to service_role;
grant execute on function public.erp_cloud_installment_totals(uuid) to service_role;

revoke all on function public.erp_r49_accounting_net_profit_by_currency(uuid,date,date) from public,anon,authenticated;
grant execute on function public.erp_r49_accounting_net_profit_by_currency(uuid,date,date) to service_role;
revoke all on function public.erp_r49_cloud_dashboard_snapshot(uuid,date) from public,anon;
revoke all on function public.erp_r49_cloud_reports_summary(uuid,date,date) from public,anon;
grant execute on function public.erp_r49_cloud_dashboard_snapshot(uuid,date) to authenticated,service_role;
grant execute on function public.erp_r49_cloud_reports_summary(uuid,date,date) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
