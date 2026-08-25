-- Accounting and currency integrity rules.
-- Rule 1: Commercial documents never persist an exchange rate.
-- Rule 2: Exchange rates are accepted only by settlement/payment records.
-- Rule 3: Posted journals generated from the same business reference are idempotent.

create or replace function public.erp_reject_document_exchange_rate()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_row jsonb := to_jsonb(new);
  v_document jsonb;
  v_is_deleted boolean;
begin
  v_document := coalesce(v_row -> 'data', v_row -> 'aggregate', '{}'::jsonb);
  v_is_deleted := coalesce((v_row ->> 'is_deleted')::boolean, false);

  if not v_is_deleted
     and (
       v_document ? 'exchangeRate'
       or v_document ? 'exchange_rate'
       or v_document ? 'currencyRate'
       or v_document ? 'fxRate'
     ) then
    raise exception 'معامل الصرف مسموح في تسوية الدفعات فقط، وليس في أوامر أو فواتير البيع والشراء.';
  end if;
  return new;
end;
$$;

do $$
declare
  v_table text;
  v_json_column text;
begin
  foreach v_table in array array[
    'erp_sales',
    'erp_purchases',
    'erp_sales_orders_cloud',
    'erp_purchase_orders_cloud',
    'erp_sales_workflows',
    'erp_purchase_workflows'
  ] loop
    if to_regclass('public.' || v_table) is null then
      continue;
    end if;

    -- The commercial tables do not all use the same JSON column. Legacy
    -- records use `data`, workflow caches use `aggregate`, while cloud order
    -- headers are relational and have neither. Only install this JSON-key
    -- guard where a compatible column actually exists.
    select a.attname
      into v_json_column
      from pg_attribute a
     where a.attrelid = to_regclass('public.' || v_table)
       and a.attnum > 0
       and not a.attisdropped
       and a.attname in ('data', 'aggregate')
     order by case a.attname when 'data' then 1 else 2 end
     limit 1;

    execute format(
      'drop trigger if exists trg_%I_no_exchange_rate on public.%I',
      v_table,
      v_table
    );

    if v_json_column is not null then
      execute format(
        'create trigger trg_%I_no_exchange_rate before insert or update of %I on public.%I for each row execute function public.erp_reject_document_exchange_rate()',
        v_table,
        v_json_column,
        v_table
      );
    end if;

    v_json_column := null;
  end loop;
end
$$;

-- A generated journal reference may be posted only once. Manual journals have
-- no business reference and are intentionally excluded.
create unique index if not exists erp_journal_entries_unique_business_reference
  on public.erp_journal_entries (
    company_id,
    (data->>'referenceType'),
    (data->>'referenceId')
  )
  where not is_deleted
    and coalesce(data->>'status', 'posted') = 'posted'
    and nullif(data->>'referenceType', '') is not null
    and nullif(data->>'referenceId', '') is not null;

create or replace function public.erp_assert_balanced_journal_entry()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_debit numeric;
  v_credit numeric;
begin
  if coalesce(new.is_deleted, false) then
    return new;
  end if;

  v_debit := coalesce(nullif(new.data->>'totalDebit', '')::numeric, 0);
  v_credit := coalesce(nullif(new.data->>'totalCredit', '')::numeric, 0);
  if abs(v_debit - v_credit) > 0.01 then
    raise exception 'لا يمكن حفظ قيد غير متوازن.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_erp_journal_entries_balanced on public.erp_journal_entries;
create trigger trg_erp_journal_entries_balanced
before insert or update of data, is_deleted on public.erp_journal_entries
for each row execute function public.erp_assert_balanced_journal_entry();

grant execute on function public.erp_reject_document_exchange_rate() to authenticated;
grant execute on function public.erp_assert_balanced_journal_entry() to authenticated;
