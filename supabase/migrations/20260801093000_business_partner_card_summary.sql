-- Rich business-partner card summary used by customer and supplier profiles.
create or replace function public.erp_business_partner_card_summary(
  p_company_id uuid,
  p_partner_kind text,
  p_partner_id text
) returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_kind text := lower(coalesce(p_partner_kind, ''));
  v_partner jsonb := '{}'::jsonb;
  v_documents jsonb := '[]'::jsonb;
  v_currencies jsonb := '[]'::jsonb;
  v_document_count bigint := 0;
  v_transaction_count bigint := 0;
  v_payment_count bigint := 0;
  v_total numeric := 0;
  v_paid numeric := 0;
  v_outstanding numeric := 0;
begin
  if not public.is_active_company_member(p_company_id) then
    raise exception 'company_access_denied';
  end if;

  if v_kind = 'customer' then
    select coalesce(data, '{}'::jsonb) into v_partner
    from public.erp_customers
    where company_id = p_company_id and id = p_partner_id and not is_deleted;

    select
      count(*),
      coalesce(sum(public.erp_try_numeric(coalesce(data->>'totalAmount', data->>'salePrice'), 0)), 0),
      coalesce(sum(public.erp_try_numeric(data->>'paidAmount', 0)), 0),
      coalesce(sum(public.erp_try_numeric(
        data->>'remainingAmount',
        public.erp_try_numeric(coalesce(data->>'totalAmount', data->>'salePrice'), 0) -
          public.erp_try_numeric(data->>'paidAmount', 0)
      )), 0),
      coalesce(sum(case when jsonb_typeof(data->'payments') = 'array'
        then jsonb_array_length(data->'payments') else 0 end), 0)
    into v_transaction_count, v_total, v_paid, v_outstanding, v_payment_count
    from public.erp_sales
    where company_id = p_company_id and not is_deleted
      and coalesce(data->>'customerId', data->>'clientId', '') = p_partner_id;

    select coalesce(jsonb_agg(to_jsonb(x) order by x.document_date desc), '[]'::jsonb)
    into v_documents
    from (
      select
        coalesce(nullif(data->>'invoiceNumber',''), nullif(data->>'saleNumber',''), id) document_number,
        coalesce(data->>'saleDate', data->>'createdAt', created_at::text) document_date,
        upper(coalesce(nullif(data->>'currencyCode',''), nullif(data->>'currency',''), 'USD')) currency,
        public.erp_try_numeric(coalesce(data->>'totalAmount', data->>'salePrice'), 0) total_amount,
        public.erp_try_numeric(data->>'paidAmount', 0) paid_amount,
        public.erp_try_numeric(
          data->>'remainingAmount',
          public.erp_try_numeric(coalesce(data->>'totalAmount', data->>'salePrice'), 0) -
            public.erp_try_numeric(data->>'paidAmount', 0)
        ) outstanding_amount,
        coalesce(nullif(data->>'paymentStatus',''), nullif(data->>'status',''), 'open') status
      from public.erp_sales
      where company_id = p_company_id and not is_deleted
        and coalesce(data->>'customerId', data->>'clientId', '') = p_partner_id
      order by coalesce(data->>'saleDate', data->>'createdAt', created_at::text) desc
      limit 12
    ) x;

    select coalesce(jsonb_agg(currency order by currency), '[]'::jsonb)
    into v_currencies
    from (
      select distinct upper(coalesce(nullif(data->>'currencyCode',''), nullif(data->>'currency',''), 'USD')) currency
      from public.erp_sales
      where company_id = p_company_id and not is_deleted
        and coalesce(data->>'customerId', data->>'clientId', '') = p_partner_id
    ) currencies;
  elsif v_kind = 'supplier' then
    select coalesce(data, '{}'::jsonb) into v_partner
    from public.erp_suppliers
    where company_id = p_company_id and id = p_partner_id and not is_deleted;

    select
      count(*),
      coalesce(sum(public.erp_try_numeric(data->>'totalAmount', 0)), 0),
      coalesce(sum(public.erp_try_numeric(data->>'paidAmount', 0)), 0),
      coalesce(sum(public.erp_try_numeric(
        data->>'remainingAmount',
        public.erp_try_numeric(data->>'totalAmount', 0) - public.erp_try_numeric(data->>'paidAmount', 0)
      )), 0),
      coalesce(sum(case when jsonb_typeof(data->'payments') = 'array'
        then jsonb_array_length(data->'payments') else 0 end), 0)
    into v_transaction_count, v_total, v_paid, v_outstanding, v_payment_count
    from public.erp_purchases
    where company_id = p_company_id and not is_deleted
      and coalesce(data->>'supplierId', '') = p_partner_id;

    select coalesce(jsonb_agg(to_jsonb(x) order by x.document_date desc), '[]'::jsonb)
    into v_documents
    from (
      select
        coalesce(nullif(data->>'invoiceNumber',''), nullif(data->>'purchaseNumber',''), id) document_number,
        coalesce(data->>'purchaseDate', data->>'createdAt', created_at::text) document_date,
        upper(coalesce(nullif(data->>'currencyCode',''), nullif(data->>'currency',''), 'USD')) currency,
        public.erp_try_numeric(data->>'totalAmount', 0) total_amount,
        public.erp_try_numeric(data->>'paidAmount', 0) paid_amount,
        public.erp_try_numeric(
          data->>'remainingAmount',
          public.erp_try_numeric(data->>'totalAmount', 0) - public.erp_try_numeric(data->>'paidAmount', 0)
        ) outstanding_amount,
        coalesce(nullif(data->>'paymentStatus',''), nullif(data->>'status',''), 'open') status
      from public.erp_purchases
      where company_id = p_company_id and not is_deleted
        and coalesce(data->>'supplierId', '') = p_partner_id
      order by coalesce(data->>'purchaseDate', data->>'createdAt', created_at::text) desc
      limit 12
    ) x;

    select coalesce(jsonb_agg(currency order by currency), '[]'::jsonb)
    into v_currencies
    from (
      select distinct upper(coalesce(nullif(data->>'currencyCode',''), nullif(data->>'currency',''), 'USD')) currency
      from public.erp_purchases
      where company_id = p_company_id and not is_deleted
        and coalesce(data->>'supplierId', '') = p_partner_id
    ) currencies;
  else
    raise exception 'unsupported_partner_kind';
  end if;

  -- Some installations do not enable the optional generic document registry.
  -- Dynamic SQL keeps the migration deployable while still counting linked
  -- documents whenever that module is present.
  if to_regclass('public.erp_documents') is not null then
    execute $query$
      select count(*)
      from public.erp_documents
      where company_id = $1 and not is_deleted
        and coalesce(data->>'partnerId', data->>'customerId', data->>'supplierId', '') = $2
    $query$ into v_document_count using p_company_id, p_partner_id;
  end if;

  return jsonb_build_object(
    'partnerKind', v_kind,
    'partnerId', p_partner_id,
    'accountId', coalesce(
      v_partner->>'ledgerAccountId',
      v_partner->>'accountId',
      v_partner->>'receivableAccountId',
      v_partner->>'payableAccountId'
    ),
    'openingBalance', public.erp_try_numeric(coalesce(v_partner->>'openingBalance', v_partner->>'opening_balance'), 0),
    'defaultCurrency', upper(coalesce(nullif(v_partner->>'currency',''), 'USD')),
    'currencies', v_currencies,
    'transactionCount', v_transaction_count,
    'transactionTotal', v_total,
    'paidTotal', v_paid,
    'outstandingTotal', v_outstanding,
    'paymentCount', v_payment_count,
    'linkedDocumentCount', v_document_count,
    'recentDocuments', v_documents
  );
end;
$$;

grant execute on function public.erp_business_partner_card_summary(uuid, text, text) to authenticated;
