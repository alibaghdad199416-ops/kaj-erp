-- 17.71.0: consolidated financial reporting dashboard and report diagnostics.
begin;

create or replace function public.erp_financial_report_summary(
  p_company_id uuid,
  p_currency text default 'ALL',
  p_from_date timestamptz default null,
  p_to_date timestamptz default null,
  p_branch_id text default null,
  p_cost_center_id text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_trial jsonb := '[]'::jsonb;
  v_profit_loss jsonb := '[]'::jsonb;
  v_balance_sheet jsonb := '[]'::jsonb;
  v_cash_flow jsonb := '[]'::jsonb;
  v_integrity jsonb;
  v_entry_count integer := 0;
  v_line_count integer := 0;
begin
  if not public.is_active_company_member(p_company_id) then
    raise exception 'access denied';
  end if;

  select coalesce(jsonb_agg(r), '[]'::jsonb) into v_trial
  from public.erp_cloud_professional_accounting_report(
    p_company_id,'trialBalance',p_currency,p_branch_id,p_cost_center_id,p_from_date,p_to_date
  ) r;

  select coalesce(jsonb_agg(r), '[]'::jsonb) into v_profit_loss
  from public.erp_cloud_professional_accounting_report(
    p_company_id,'profitLoss',p_currency,p_branch_id,p_cost_center_id,p_from_date,p_to_date
  ) r;

  select coalesce(jsonb_agg(r), '[]'::jsonb) into v_balance_sheet
  from public.erp_cloud_professional_accounting_report(
    p_company_id,'balanceSheet',p_currency,p_branch_id,p_cost_center_id,p_from_date,p_to_date
  ) r;

  select coalesce(jsonb_agg(r), '[]'::jsonb) into v_cash_flow
  from public.erp_cloud_professional_accounting_report(
    p_company_id,'cashFlow',p_currency,p_branch_id,p_cost_center_id,p_from_date,p_to_date
  ) r;

  select count(*) into v_entry_count
  from public.erp_journal_entries je
  where je.company_id=p_company_id and not je.is_deleted
    and lower(coalesce(je.data->>'status','posted'))='posted'
    and (p_from_date is null or (je.data->>'entryDate')::timestamptz >= p_from_date)
    and (p_to_date is null or (je.data->>'entryDate')::timestamptz <= p_to_date)
    and (p_currency='ALL' or coalesce(nullif(je.data->>'currency',''),'IQD')=p_currency)
    and (p_branch_id is null or je.data->>'branchId'=p_branch_id);

  select count(*) into v_line_count
  from public.erp_journal_lines jl
  join public.erp_journal_entries je on je.company_id=jl.company_id and je.id=jl.data->>'entryId'
  where jl.company_id=p_company_id and not jl.is_deleted and not je.is_deleted
    and lower(coalesce(je.data->>'status','posted'))='posted'
    and (p_from_date is null or (je.data->>'entryDate')::timestamptz >= p_from_date)
    and (p_to_date is null or (je.data->>'entryDate')::timestamptz <= p_to_date)
    and (p_currency='ALL' or coalesce(nullif(je.data->>'currency',''),'IQD')=p_currency)
    and (p_branch_id is null or je.data->>'branchId'=p_branch_id)
    and (p_cost_center_id is null or coalesce(jl.data->>'costCenterId',je.data->>'costCenterId')=p_cost_center_id);

  v_integrity := public.erp_accounting_integrity_health(p_company_id);

  return jsonb_build_object(
    'ok',coalesce((v_integrity->>'ok')::boolean,false),
    'companyId',p_company_id,
    'generatedAt',now(),
    'currency',p_currency,
    'fromDate',p_from_date,
    'toDate',p_to_date,
    'postedEntryCount',v_entry_count,
    'journalLineCount',v_line_count,
    'trialBalance',v_trial,
    'profitLoss',v_profit_loss,
    'balanceSheet',v_balance_sheet,
    'cashFlow',v_cash_flow,
    'integrity',v_integrity
  );
end
$$;

create or replace function public.erp_financial_reporting_health(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_integrity jsonb;
  v_invalid_dates integer := 0;
  v_missing_currency integer := 0;
  v_unclassified_accounts integer := 0;
  v_report_error text;
begin
  if not public.is_active_company_member(p_company_id) then raise exception 'access denied'; end if;

  select count(*) into v_invalid_dates
  from public.erp_journal_entries
  where company_id=p_company_id and not is_deleted
    and nullif(data->>'entryDate','') is not null
    and (data->>'entryDate') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}';

  select count(*) into v_missing_currency
  from public.erp_journal_entries
  where company_id=p_company_id and not is_deleted
    and lower(coalesce(data->>'status','posted'))='posted'
    and nullif(trim(data->>'currency'),'') is null;

  select count(*) into v_unclassified_accounts
  from public.erp_accounts
  where organization_id=p_company_id and is_active
    and account_type not in ('asset','liability','equity','revenue','expense');

  v_integrity := public.erp_accounting_integrity_health(p_company_id);

  begin
    perform public.erp_financial_report_summary(p_company_id,'ALL',null,now(),null,null);
  exception when others then
    v_report_error := sqlerrm;
  end;

  return jsonb_build_object(
    'ok',coalesce((v_integrity->>'ok')::boolean,false)
      and v_invalid_dates=0 and v_missing_currency=0
      and v_unclassified_accounts=0 and v_report_error is null,
    'checkedAt',now(),
    'invalidEntryDates',v_invalid_dates,
    'postedEntriesMissingCurrency',v_missing_currency,
    'unclassifiedAccounts',v_unclassified_accounts,
    'reportExecutionError',v_report_error,
    'accountingIntegrity',v_integrity
  );
end
$$;

grant execute on function public.erp_financial_report_summary(uuid,text,timestamptz,timestamptz,text,text) to authenticated;
grant execute on function public.erp_financial_reporting_health(uuid) to authenticated;

commit;
