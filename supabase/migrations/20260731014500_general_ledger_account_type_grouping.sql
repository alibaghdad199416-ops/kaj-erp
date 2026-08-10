begin;

create or replace function public.erp_cloud_professional_accounting_report(
  p_company_id uuid,
  p_report_type text,
  p_currency text default 'ALL',
  p_branch_id text default null,
  p_cost_center_id text default null,
  p_from_date timestamptz default null,
  p_to_date timestamptz default null
)
returns setof jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_active_company_member(p_company_id) then
    raise exception 'access denied';
  end if;

  if p_report_type = 'cashFlow' then
    return query
    with cash_rows as (
      select
        coalesce(nullif(data->>'currency', ''), 'IQD') as currency,
        coalesce((data->>'amount')::numeric, 0) as amount,
        data->>'type' as transaction_type
      from public.erp_cash_transactions
      where company_id = p_company_id
        and not is_deleted
        and (p_currency = 'ALL' or data->>'currency' = p_currency)
        and (p_from_date is null or (data->>'transactionDate')::timestamptz >= p_from_date)
        and (p_to_date is null or (data->>'transactionDate')::timestamptz <= p_to_date)
    )
    select jsonb_build_object(
      'currency', currency,
      'cashIn', sum(case when transaction_type in ('income','receipt','in','customer_receipt','transfer_in') then amount else 0 end),
      'cashOut', sum(case when transaction_type in ('expense','payment','out','supplier_payment','transfer_out') then amount else 0 end),
      'netCashFlow', sum(case
        when transaction_type in ('income','receipt','in','customer_receipt','transfer_in') then amount
        when transaction_type in ('expense','payment','out','supplier_payment','transfer_out') then -amount
        else 0
      end)
    )
    from cash_rows
    group by currency
    order by currency;

  elsif p_report_type = 'generalLedger' then
    return query
    with ledger_rows as (
      select
        a.code as account_code,
        a.name as account_name,
        a.account_type,
        a.opening_balance,
        coalesce(nullif(je.data->>'currency', ''), a.currency) as currency,
        (je.data->>'entryDate')::timestamptz as entry_date,
        je.data->>'entryNumber' as entry_number,
        coalesce(jl.data->>'description', je.data->>'description', '') as description,
        coalesce((jl.data->>'debit')::numeric, 0) as debit,
        coalesce((jl.data->>'credit')::numeric, 0) as credit,
        je.created_at,
        jl.created_at as line_created_at
      from public.erp_journal_lines jl
      join public.erp_journal_entries je
        on je.company_id = jl.company_id
       and je.id = jl.data->>'entryId'
      join public.erp_accounts a
        on a.organization_id = jl.company_id
       and a.account_id = jl.data->>'accountId'
      where jl.company_id = p_company_id
        and not jl.is_deleted
        and not je.is_deleted
        and a.is_active
        and je.data->>'status' = 'posted'
        and (p_currency = 'ALL' or coalesce(nullif(je.data->>'currency', ''), a.currency) = p_currency)
        and (p_branch_id is null or je.data->>'branchId' = p_branch_id)
        and (p_cost_center_id is null or coalesce(jl.data->>'costCenterId', je.data->>'costCenterId') = p_cost_center_id)
        and (p_to_date is null or (je.data->>'entryDate')::timestamptz <= p_to_date)
    ),
    with_running as (
      select *,
        opening_balance + sum(
          case when account_type in ('liability','equity','revenue')
            then credit - debit
            else debit - credit
          end
        ) over (
          partition by account_code, currency
          order by entry_date, created_at, line_created_at
          rows between unbounded preceding and current row
        ) as running_balance
      from ledger_rows
    )
    select jsonb_build_object(
      'entryDate', entry_date,
      'entryNumber', entry_number,
      'accountCode', account_code,
      'accountName', account_name,
      'accountType', account_type,
      'currency', currency,
      'debit', debit,
      'credit', credit,
      'description', description,
      'runningBalance', running_balance
    )
    from with_running
    where p_from_date is null or entry_date >= p_from_date
    order by account_code, entry_date, created_at, line_created_at;

  elsif p_report_type = 'balanceSheet' then
    return query
    with balances as (
      select
        a.account_type,
        a.currency,
        a.opening_balance + coalesce(sum(
          case when a.account_type in ('liability','equity','revenue')
            then coalesce((jl.data->>'credit')::numeric,0) - coalesce((jl.data->>'debit')::numeric,0)
            else coalesce((jl.data->>'debit')::numeric,0) - coalesce((jl.data->>'credit')::numeric,0)
          end
        ) filter (where je.id is not null), 0) as balance
      from public.erp_accounts a
      left join public.erp_journal_lines jl
        on jl.company_id = a.organization_id
       and jl.data->>'accountId' = a.account_id
       and not jl.is_deleted
      left join public.erp_journal_entries je
        on je.company_id = jl.company_id
       and je.id = jl.data->>'entryId'
       and not je.is_deleted
       and je.data->>'status' = 'posted'
       and (p_branch_id is null or je.data->>'branchId' = p_branch_id)
       and (p_cost_center_id is null or coalesce(jl.data->>'costCenterId', je.data->>'costCenterId') = p_cost_center_id)
       and (p_to_date is null or (je.data->>'entryDate')::timestamptz <= p_to_date)
      where a.organization_id = p_company_id
        and a.is_active
        and a.account_type in ('asset','liability','equity')
        and (p_currency = 'ALL' or a.currency = p_currency)
      group by a.account_id, a.account_type, a.currency, a.opening_balance
    )
    select jsonb_build_object(
      'currency', currency,
      'assets', sum(case when account_type = 'asset' then balance else 0 end),
      'liabilities', sum(case when account_type = 'liability' then balance else 0 end),
      'equity', sum(case when account_type = 'equity' then balance else 0 end),
      'difference',
        sum(case when account_type = 'asset' then balance else 0 end)
        - sum(case when account_type in ('liability','equity') then balance else 0 end)
    )
    from balances
    group by currency
    order by currency;

  elsif p_report_type = 'profitLoss' then
    return query
    with balances as (
      select
        a.account_type,
        a.currency,
        coalesce(sum(
          case when a.account_type = 'revenue'
            then coalesce((jl.data->>'credit')::numeric,0) - coalesce((jl.data->>'debit')::numeric,0)
            else coalesce((jl.data->>'debit')::numeric,0) - coalesce((jl.data->>'credit')::numeric,0)
          end
        ) filter (where je.id is not null), 0) as balance
      from public.erp_accounts a
      left join public.erp_journal_lines jl
        on jl.company_id = a.organization_id
       and jl.data->>'accountId' = a.account_id
       and not jl.is_deleted
      left join public.erp_journal_entries je
        on je.company_id = jl.company_id
       and je.id = jl.data->>'entryId'
       and not je.is_deleted
       and je.data->>'status' = 'posted'
       and (p_branch_id is null or je.data->>'branchId' = p_branch_id)
       and (p_cost_center_id is null or coalesce(jl.data->>'costCenterId', je.data->>'costCenterId') = p_cost_center_id)
       and (p_from_date is null or (je.data->>'entryDate')::timestamptz >= p_from_date)
       and (p_to_date is null or (je.data->>'entryDate')::timestamptz <= p_to_date)
      where a.organization_id = p_company_id
        and a.is_active
        and a.account_type in ('revenue','expense')
        and (p_currency = 'ALL' or a.currency = p_currency)
      group by a.account_id, a.account_type, a.currency
    )
    select jsonb_build_object(
      'currency', currency,
      'revenue', sum(case when account_type = 'revenue' then balance else 0 end),
      'expenses', sum(case when account_type = 'expense' then balance else 0 end),
      'netProfit',
        sum(case when account_type = 'revenue' then balance else 0 end)
        - sum(case when account_type = 'expense' then balance else 0 end)
    )
    from balances
    group by currency
    order by currency;

  else
    return query
    with account_movements as (
      select
        a.account_id,
        a.code,
        a.name,
        a.account_type,
        a.currency,
        a.opening_balance,
        coalesce(sum(coalesce((jl.data->>'debit')::numeric,0)) filter (
          where je.id is not null
            and (p_from_date is null or (je.data->>'entryDate')::timestamptz >= p_from_date)
        ), 0) as debit,
        coalesce(sum(coalesce((jl.data->>'credit')::numeric,0)) filter (
          where je.id is not null
            and (p_from_date is null or (je.data->>'entryDate')::timestamptz >= p_from_date)
        ), 0) as credit,
        a.opening_balance + coalesce(sum(
          case when a.account_type in ('liability','equity','revenue')
            then coalesce((jl.data->>'credit')::numeric,0) - coalesce((jl.data->>'debit')::numeric,0)
            else coalesce((jl.data->>'debit')::numeric,0) - coalesce((jl.data->>'credit')::numeric,0)
          end
        ) filter (
          where je.id is not null
            and p_from_date is not null
            and (je.data->>'entryDate')::timestamptz < p_from_date
        ), 0) as period_opening
      from public.erp_accounts a
      left join public.erp_journal_lines jl
        on jl.company_id = a.organization_id
       and jl.data->>'accountId' = a.account_id
       and not jl.is_deleted
      left join public.erp_journal_entries je
        on je.company_id = jl.company_id
       and je.id = jl.data->>'entryId'
       and not je.is_deleted
       and je.data->>'status' = 'posted'
       and (p_branch_id is null or je.data->>'branchId' = p_branch_id)
       and (p_cost_center_id is null or coalesce(jl.data->>'costCenterId', je.data->>'costCenterId') = p_cost_center_id)
       and (p_to_date is null or (je.data->>'entryDate')::timestamptz <= p_to_date)
      where a.organization_id = p_company_id
        and a.is_active
        and (p_currency = 'ALL' or a.currency = p_currency)
      group by a.account_id, a.code, a.name, a.account_type, a.currency, a.opening_balance
    )
    select jsonb_build_object(
      'code', code,
      'name', name,
      'type', account_type,
      'currency', currency,
      'openingBalance', period_opening,
      'debit', debit,
      'credit', credit,
      'balance', period_opening + case when account_type in ('liability','equity','revenue') then credit - debit else debit - credit end
    )
    from account_movements
    order by code;
  end if;
end
$$;

grant execute on function public.erp_cloud_professional_accounting_report(uuid,text,text,text,text,timestamptz,timestamptz) to authenticated;

commit;
