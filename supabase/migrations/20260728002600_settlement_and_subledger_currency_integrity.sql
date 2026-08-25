-- Settlement and subledger currency integrity.
-- Document values stay in their own currency. Exchange rates are used only by
-- payment settlement and cash-transfer workflows, never to merge balances.

begin;

create or replace function public.erp_assert_cash_transaction_currency()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_cash_currency text;
  v_transaction_currency text;
begin
  if new.is_deleted then
    return new;
  end if;

  select upper(coalesce(data->>'currency',''))
    into v_cash_currency
  from public.erp_cash_accounts
  where company_id=new.company_id
    and id=new.data->>'cashAccountId'
    and not is_deleted;

  if v_cash_currency is null or v_cash_currency='' then
    raise exception 'cash_account_not_found';
  end if;

  v_transaction_currency := upper(coalesce(new.data->>'currency',''));
  if v_transaction_currency not in ('USD','IQD') then
    raise exception 'unsupported_cash_currency';
  end if;
  if v_transaction_currency <> v_cash_currency then
    raise exception 'cash_transaction_currency_mismatch';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_erp_cash_transactions_currency on public.erp_cash_transactions;
create trigger trg_erp_cash_transactions_currency
before insert or update of data,is_deleted on public.erp_cash_transactions
for each row execute function public.erp_assert_cash_transaction_currency();

create or replace function public.erp_cloud_receivables_payables(p_company_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  with receivables as (
    select
      upper(coalesce(data->>'currency','USD')) as currency,
      sum(greatest(coalesce(nullif(data->>'remainingAmount','')::numeric,0),0)) as amount
    from public.erp_sales
    where company_id=p_company_id
      and not is_deleted
      and public.is_active_company_member(p_company_id)
    group by upper(coalesce(data->>'currency','USD'))
  ), payables as (
    select
      upper(coalesce(data->>'currency','USD')) as currency,
      sum(greatest(
        coalesce(nullif(data->>'totalAmount','')::numeric,0)
        - coalesce(nullif(data->>'paidAmount','')::numeric,0),
        0
      )) as amount
    from public.erp_purchases
    where company_id=p_company_id
      and not is_deleted
      and public.is_active_company_member(p_company_id)
    group by upper(coalesce(data->>'currency','USD'))
  )
  select jsonb_build_object(
    'receivablesByCurrency', coalesce(
      (select jsonb_object_agg(currency,amount) from receivables),
      '{}'::jsonb
    ),
    'payablesByCurrency', coalesce(
      (select jsonb_object_agg(currency,amount) from payables),
      '{}'::jsonb
    ),
    'receivables', coalesce((select sum(amount) from receivables where currency='USD'),0),
    'payables', coalesce((select sum(amount) from payables where currency='USD'),0),
    'displayCurrency', 'USD',
    'mixedCurrencyAggregationDisabled', true
  );
$$;

comment on function public.erp_cloud_receivables_payables(uuid) is
  'Returns receivables/payables separated by document currency. Legacy scalar fields contain USD only; currencies are never converted or merged here.';

grant execute on function public.erp_assert_cash_transaction_currency() to authenticated;
grant execute on function public.erp_cloud_receivables_payables(uuid) to authenticated;

commit;
