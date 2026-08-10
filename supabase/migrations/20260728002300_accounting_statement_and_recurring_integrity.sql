-- Accounting statement accuracy and recurring-entry idempotency.
-- Recurring templates may post once per posting date, while commercial
--    references remain strictly idempotent.
-- Account statements begin with the true balance immediately before the
--    selected period, including opening balance and all prior posted movements.

begin;

drop index if exists public.erp_journal_entries_unique_business_reference;

create unique index if not exists erp_journal_entries_unique_business_reference
  on public.erp_journal_entries (
    company_id,
    (data->>'referenceType'),
    (data->>'referenceId')
  )
  where not is_deleted
    and coalesce(data->>'status', 'posted') = 'posted'
    and nullif(data->>'referenceType', '') is not null
    and nullif(data->>'referenceId', '') is not null
    and data->>'referenceType' <> 'recurring_journal';

create unique index if not exists erp_journal_entries_unique_recurring_post
  on public.erp_journal_entries (
    company_id,
    (data->>'referenceId'),
    (left(data->>'entryDate', 10))
  )
  where not is_deleted
    and coalesce(data->>'status', 'posted') = 'posted'
    and data->>'referenceType' = 'recurring_journal'
    and nullif(data->>'referenceId', '') is not null
    and nullif(data->>'entryDate', '') is not null;

create or replace function public.erp_cloud_account_balance_before(
  p_company_id uuid,
  p_account_id text,
  p_before_date timestamptz
) returns numeric
language sql
security definer
set search_path=public
as $$
  with account_data as (
    select
      coalesce(a.opening_balance, 0) as opening_balance,
      a.account_type
    from public.erp_accounts a
    where a.organization_id = p_company_id
      and a.account_id = p_account_id
      and a.is_active
      and public.is_active_company_member(p_company_id)
  ), movement as (
    select
      coalesce(sum(coalesce(nullif(jl.data->>'debit','')::numeric, 0)), 0) as debit,
      coalesce(sum(coalesce(nullif(jl.data->>'credit','')::numeric, 0)), 0) as credit
    from public.erp_journal_lines jl
    join public.erp_journal_entries je
      on je.company_id = jl.company_id
     and je.id = jl.data->>'entryId'
    where jl.company_id = p_company_id
      and not jl.is_deleted
      and not je.is_deleted
      and coalesce(je.data->>'status', 'posted') = 'posted'
      and jl.data->>'accountId' = p_account_id
      and (je.data->>'entryDate')::timestamptz < p_before_date
  )
  select case
    when a.account_type in ('liability', 'equity', 'revenue')
      then a.opening_balance + m.credit - m.debit
    else a.opening_balance + m.debit - m.credit
  end
  from account_data a cross join movement m;
$$;

-- The trial-balance summary includes opening balances so its debit and credit
-- columns agree with account statements at the same point in time.
create or replace function public.erp_cloud_trial_balance(
  p_company_id uuid,
  p_currency text
) returns jsonb
language sql
security definer
set search_path=public
as $$
  with account_totals as (
    select
      a.account_id,
      a.account_type,
      a.opening_balance,
      coalesce(sum(coalesce(nullif(jl.data->>'debit','')::numeric, 0))
        filter (where je.id is not null), 0) as movement_debit,
      coalesce(sum(coalesce(nullif(jl.data->>'credit','')::numeric, 0))
        filter (where je.id is not null), 0) as movement_credit
    from public.erp_accounts a
    left join public.erp_journal_lines jl
      on jl.company_id = a.organization_id
     and jl.data->>'accountId' = a.account_id
     and not jl.is_deleted
    left join public.erp_journal_entries je
      on je.company_id = jl.company_id
     and je.id = jl.data->>'entryId'
     and not je.is_deleted
     and coalesce(je.data->>'status', 'posted') = 'posted'
     and je.data->>'currency' = p_currency
    where a.organization_id = p_company_id
      and a.is_active
      and a.currency = p_currency
      and public.is_active_company_member(p_company_id)
    group by a.account_id, a.account_type, a.opening_balance
  )
  select jsonb_build_object(
    'debit', coalesce(sum(
      movement_debit + case when account_type in ('asset','expense') then opening_balance else 0 end
    ), 0),
    'credit', coalesce(sum(
      movement_credit + case when account_type in ('liability','equity','revenue') then opening_balance else 0 end
    ), 0)
  )
  from account_totals;
$$;

grant execute on function public.erp_cloud_account_balance_before(uuid,text,timestamptz) to authenticated;
grant execute on function public.erp_cloud_trial_balance(uuid,text) to authenticated;

commit;
