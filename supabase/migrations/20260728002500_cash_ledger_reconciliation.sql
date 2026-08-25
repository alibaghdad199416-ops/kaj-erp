-- Cash subledger / general-ledger reconciliation.
-- Currency summaries include cash-account opening balances, and every cash
-- account can be reconciled against its linked posted ledger account.

begin;

create or replace function public.erp_cloud_cash_currency_summary(
  p_company_id uuid,
  p_currency text
) returns jsonb
language sql
security definer
set search_path=public
as $$
  with accounts as (
    select
      coalesce(sum(coalesce(nullif(data->>'openingBalance','')::numeric, 0)), 0) as opening_balance
    from public.erp_cash_accounts
    where company_id = p_company_id
      and not is_deleted
      and upper(coalesce(data->>'currency','')) = upper(p_currency)
      and public.is_active_company_member(p_company_id)
  ), movements as (
    select
      coalesce(sum(case when data->>'type'='receipt'
        then coalesce(nullif(data->>'amount','')::numeric,0) else 0 end),0) as receipts,
      coalesce(sum(case when data->>'type'='payment'
        then coalesce(nullif(data->>'amount','')::numeric,0) else 0 end),0) as payments
    from public.erp_cash_transactions
    where company_id = p_company_id
      and not is_deleted
      and upper(coalesce(data->>'currency','')) = upper(p_currency)
      and public.is_active_company_member(p_company_id)
  )
  select jsonb_build_object(
    'openingBalance', a.opening_balance,
    'receipts', m.receipts,
    'payments', m.payments,
    'balance', a.opening_balance + m.receipts - m.payments
  )
  from accounts a cross join movements m;
$$;

create or replace function public.erp_cloud_cash_ledger_reconciliation(
  p_company_id uuid
) returns table(
  cash_account_id text,
  cash_account_name text,
  currency text,
  subledger_balance numeric,
  ledger_balance numeric,
  difference numeric
)
language sql
security definer
set search_path=public
as $$
  with cash as (
    select
      ca.id,
      ca.data->>'name' as name,
      upper(coalesce(ca.data->>'currency','')) as currency,
      ca.data->>'accountId' as ledger_account_id,
      coalesce(nullif(ca.data->>'openingBalance','')::numeric,0)
        + coalesce(sum(case
            when ct.data->>'type'='receipt' then coalesce(nullif(ct.data->>'amount','')::numeric,0)
            when ct.data->>'type'='payment' then -coalesce(nullif(ct.data->>'amount','')::numeric,0)
            else 0
          end),0) as subledger_balance
    from public.erp_cash_accounts ca
    left join public.erp_cash_transactions ct
      on ct.company_id=ca.company_id
     and ct.data->>'cashAccountId'=ca.id
     and not ct.is_deleted
    where ca.company_id=p_company_id
      and not ca.is_deleted
      and public.is_active_company_member(p_company_id)
    group by ca.id, ca.data
  ), ledger as (
    select
      a.account_id,
      coalesce(a.opening_balance,0)
        + coalesce(sum(case when je.id is not null
            then coalesce(nullif(jl.data->>'debit','')::numeric,0)
               - coalesce(nullif(jl.data->>'credit','')::numeric,0)
            else 0 end),0) as ledger_balance
    from public.erp_accounts a
    left join public.erp_journal_lines jl
      on jl.company_id=a.organization_id
     and jl.data->>'accountId'=a.account_id
     and not jl.is_deleted
    left join public.erp_journal_entries je
      on je.company_id=jl.company_id
     and je.id=jl.data->>'entryId'
     and not je.is_deleted
     and coalesce(je.data->>'status','posted')='posted'
    where a.organization_id=p_company_id
      and a.is_active
      and public.is_active_company_member(p_company_id)
    group by a.account_id, a.opening_balance
  )
  select
    c.id,
    c.name,
    c.currency,
    c.subledger_balance,
    coalesce(l.ledger_balance,0),
    c.subledger_balance-coalesce(l.ledger_balance,0)
  from cash c
  left join ledger l on l.account_id=c.ledger_account_id
  order by c.name;
$$;

grant execute on function public.erp_cloud_cash_currency_summary(uuid,text) to authenticated;
grant execute on function public.erp_cloud_cash_ledger_reconciliation(uuid) to authenticated;

commit;
