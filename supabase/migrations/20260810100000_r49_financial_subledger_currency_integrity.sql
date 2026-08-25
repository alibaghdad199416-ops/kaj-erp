begin;

-- R49 final failure-resistance closure: financial read models must never
-- invent USD/IQD for persisted commercial or cash records. New-record UI may
-- choose an application default, but authoritative subledger/report reads fail
-- closed when legacy/corrupt persisted rows do not carry a supported currency.

create or replace function public.erp_r49_normalize_supported_currency(p_value text)
returns text
language sql
immutable
security invoker
set search_path=public
as $$
  select case
    when upper(btrim(coalesce(p_value,''))) in ('USD','IQD')
      then upper(btrim(p_value))
    else null
  end
$$;

create or replace function public.erp_r49_assert_subledger_currency_integrity(p_company_id uuid)
returns void
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not public.is_active_company_member(p_company_id) then
    raise exception 'company_access_denied' using errcode='42501';
  end if;

  if exists(
    select 1
    from public.erp_sales s
    where s.company_id=p_company_id and not s.is_deleted
      and public.erp_try_numeric(s.data->>'remainingAmount',0)>0
      and public.erp_r49_normalize_supported_currency(
        coalesce(nullif(btrim(s.data->>'currencyCode'),''),nullif(btrim(s.data->>'currency'),''))
      ) is null
  ) then
    raise exception 'financial_document_currency_invalid:sales' using errcode='22023';
  end if;

  if exists(
    select 1
    from public.erp_purchases p
    where p.company_id=p_company_id and not p.is_deleted
      and public.erp_try_numeric(
        p.data->>'remainingAmount',
        public.erp_try_numeric(p.data->>'totalAmount',0)-public.erp_try_numeric(p.data->>'paidAmount',0)
      )>0
      and public.erp_r49_normalize_supported_currency(
        coalesce(nullif(btrim(p.data->>'currencyCode'),''),nullif(btrim(p.data->>'currency'),''))
      ) is null
  ) then
    raise exception 'financial_document_currency_invalid:purchases' using errcode='22023';
  end if;

  if exists(
    select 1
    from public.erp_cash_transactions ct
    where ct.company_id=p_company_id and not ct.is_deleted
      and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='partner_advance'
      and public.erp_try_boolean(ct.data->>'unapplied',false)
      and public.erp_r49_normalize_supported_currency(ct.data->>'currency') is null
  ) then
    raise exception 'financial_document_currency_invalid:cash' using errcode='22023';
  end if;
end;
$$;

create or replace function public.erp_cloud_receivables_payables(p_company_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_result jsonb;
begin
  perform public.erp_r49_assert_subledger_currency_integrity(p_company_id);

  with sales_docs as (
    select public.erp_r49_normalize_supported_currency(
             coalesce(nullif(btrim(data->>'currencyCode'),''),nullif(btrim(data->>'currency'),''))
           ) currency,
      sum(greatest(public.erp_try_numeric(data->>'remainingAmount',0),0)) amount
    from public.erp_sales
    where company_id=p_company_id and not is_deleted
      and public.erp_try_numeric(data->>'remainingAmount',0)>0
    group by 1
  ), purchase_docs as (
    select public.erp_r49_normalize_supported_currency(
             coalesce(nullif(btrim(data->>'currencyCode'),''),nullif(btrim(data->>'currency'),''))
           ) currency,
      sum(greatest(public.erp_try_numeric(
        data->>'remainingAmount',
        public.erp_try_numeric(data->>'totalAmount',0)-public.erp_try_numeric(data->>'paidAmount',0)
      ),0)) amount
    from public.erp_purchases
    where company_id=p_company_id and not is_deleted
      and public.erp_try_numeric(
        data->>'remainingAmount',
        public.erp_try_numeric(data->>'totalAmount',0)-public.erp_try_numeric(data->>'paidAmount',0)
      )>0
    group by 1
  ), customer_advances as (
    select public.erp_r49_normalize_supported_currency(data->>'currency') currency,
      sum(public.erp_try_numeric(data->>'amount',0)) amount
    from public.erp_cash_transactions
    where company_id=p_company_id and not is_deleted
      and lower(coalesce(data->>'referenceType',data->>'reference_type',''))='partner_advance'
      and public.erp_try_boolean(data->>'unapplied',false)
      and lower(coalesce(data->>'partyType',data->>'party_type',''))='customer'
    group by 1
  ), supplier_advances as (
    select public.erp_r49_normalize_supported_currency(data->>'currency') currency,
      sum(public.erp_try_numeric(data->>'amount',0)) amount
    from public.erp_cash_transactions
    where company_id=p_company_id and not is_deleted
      and lower(coalesce(data->>'referenceType',data->>'reference_type',''))='partner_advance'
      and public.erp_try_boolean(data->>'unapplied',false)
      and lower(coalesce(data->>'partyType',data->>'party_type',''))='supplier'
    group by 1
  ), currencies as (
    select currency from sales_docs where currency is not null
    union select currency from purchase_docs where currency is not null
    union select currency from customer_advances where currency is not null
    union select currency from supplier_advances where currency is not null
  ), receivables as (
    select c.currency,coalesce(s.amount,0)-coalesce(a.amount,0) amount
    from currencies c left join sales_docs s using(currency)
    left join customer_advances a using(currency)
  ), payables as (
    select c.currency,coalesce(p.amount,0)-coalesce(a.amount,0) amount
    from currencies c left join purchase_docs p using(currency)
    left join supplier_advances a using(currency)
  )
  select jsonb_build_object(
    'receivablesByCurrency',coalesce((select jsonb_object_agg(currency,amount) from receivables),'{}'::jsonb),
    'payablesByCurrency',coalesce((select jsonb_object_agg(currency,amount) from payables),'{}'::jsonb),
    -- Legacy scalar compatibility stays USD-only; mixed-currency aggregation is
    -- explicitly disabled and UI consumers use the per-currency maps.
    'receivables',coalesce((select amount from receivables where currency='USD'),0),
    'payables',coalesce((select amount from payables where currency='USD'),0),
    'displayCurrency','USD','mixedCurrencyAggregationDisabled',true,
    'unappliedPartnerPaymentsIncluded',true
  ) into v_result;
  return v_result;
end;
$$;

create or replace function public.erp_cloud_partner_subledger_details_v2(
  p_company_id uuid,
  p_kind text
) returns table(
  party_id text,party_name text,currency text,document_count bigint,
  total_amount numeric,paid_amount numeric,outstanding_amount numeric,
  payment_count bigint,overdue_document_count bigint,
  oldest_due_date timestamptz,latest_document_date timestamptz
)
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  perform public.erp_r49_assert_subledger_currency_integrity(p_company_id);

  if lower(coalesce(p_kind,''))='receivables' then
    return query
    with docs as (
      select coalesce(s.data->>'customerId','') party_id,
        public.erp_r49_normalize_supported_currency(
          coalesce(nullif(btrim(s.data->>'currencyCode'),''),nullif(btrim(s.data->>'currency'),''))
        ) currency,
        1::bigint document_count,
        greatest(public.erp_try_numeric(coalesce(s.data->>'totalAmount',s.data->>'salePrice'),0),0) total_amount,
        greatest(public.erp_try_numeric(s.data->>'paidAmount',0),0) paid_amount,
        greatest(public.erp_try_numeric(s.data->>'remainingAmount',0),0) outstanding_amount,
        (case when jsonb_typeof(s.data->'payments')='array' then jsonb_array_length(s.data->'payments') else 0 end)::bigint payment_count,
        case when coalesce(public.erp_try_timestamptz(s.data->>'dueDate',null),public.erp_try_timestamptz(s.data->>'saleDate',null),s.created_at)<now()
                  and public.erp_try_numeric(s.data->>'remainingAmount',0)>0 then 1 else 0 end::bigint overdue_count,
        coalesce(public.erp_try_timestamptz(s.data->>'dueDate',null),public.erp_try_timestamptz(s.data->>'saleDate',null),s.created_at) due_date,
        coalesce(public.erp_try_timestamptz(s.data->>'saleDate',null),s.created_at) document_date
      from public.erp_sales s
      where s.company_id=p_company_id and not s.is_deleted
        and public.erp_try_numeric(s.data->>'remainingAmount',0)>0
    ), advances as (
      select coalesce(ct.data->>'partyId',ct.data->>'party_id','') party_id,
        public.erp_r49_normalize_supported_currency(ct.data->>'currency') currency,
        0::bigint document_count,0::numeric total_amount,
        public.erp_try_numeric(ct.data->>'amount',0) paid_amount,
        -public.erp_try_numeric(ct.data->>'amount',0) outstanding_amount,
        1::bigint payment_count,0::bigint overdue_count,null::timestamptz due_date,
        coalesce(public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),ct.created_at) document_date
      from public.erp_cash_transactions ct
      where ct.company_id=p_company_id and not ct.is_deleted
        and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='partner_advance'
        and public.erp_try_boolean(ct.data->>'unapplied',false)
        and lower(coalesce(ct.data->>'partyType',ct.data->>'party_type',''))='customer'
    ), combined as (select * from docs union all select * from advances)
    select c.party_id,
      coalesce(nullif(cu.data->>'name',''),nullif(cu.data->>'fullName',''),'عميل غير مسمى') party_name,
      c.currency,sum(c.document_count)::bigint,sum(c.total_amount),sum(c.paid_amount),sum(c.outstanding_amount),
      sum(c.payment_count)::bigint,sum(c.overdue_count)::bigint,min(c.due_date),max(c.document_date)
    from combined c
    left join public.erp_customers cu on cu.company_id=p_company_id and cu.id::text=c.party_id and not cu.is_deleted
    where c.party_id<>'' and c.currency is not null
    group by c.party_id,party_name,c.currency
    having abs(sum(c.outstanding_amount))>0.005 or sum(c.payment_count)>0
    order by c.currency,sum(c.outstanding_amount) desc,party_name;
    return;
  end if;

  if lower(coalesce(p_kind,''))='payables' then
    return query
    with docs as (
      select coalesce(p.data->>'supplierId','') party_id,
        public.erp_r49_normalize_supported_currency(
          coalesce(nullif(btrim(p.data->>'currencyCode'),''),nullif(btrim(p.data->>'currency'),''))
        ) currency,
        1::bigint document_count,
        greatest(public.erp_try_numeric(p.data->>'totalAmount',0),0) total_amount,
        greatest(public.erp_try_numeric(p.data->>'paidAmount',0),0) paid_amount,
        greatest(public.erp_try_numeric(
          p.data->>'remainingAmount',
          public.erp_try_numeric(p.data->>'totalAmount',0)-public.erp_try_numeric(p.data->>'paidAmount',0)
        ),0) outstanding_amount,
        (case when jsonb_typeof(p.data->'payments')='array' then jsonb_array_length(p.data->'payments') else 0 end)::bigint payment_count,
        case when coalesce(public.erp_try_timestamptz(p.data->>'dueDate',null),public.erp_try_timestamptz(p.data->>'purchaseDate',null),p.created_at)<now()
                  and public.erp_try_numeric(
                    p.data->>'remainingAmount',
                    public.erp_try_numeric(p.data->>'totalAmount',0)-public.erp_try_numeric(p.data->>'paidAmount',0)
                  )>0 then 1 else 0 end::bigint overdue_count,
        coalesce(public.erp_try_timestamptz(p.data->>'dueDate',null),public.erp_try_timestamptz(p.data->>'purchaseDate',null),p.created_at) due_date,
        coalesce(public.erp_try_timestamptz(p.data->>'purchaseDate',null),p.created_at) document_date
      from public.erp_purchases p
      where p.company_id=p_company_id and not p.is_deleted
        and public.erp_try_numeric(
          p.data->>'remainingAmount',
          public.erp_try_numeric(p.data->>'totalAmount',0)-public.erp_try_numeric(p.data->>'paidAmount',0)
        )>0
    ), advances as (
      select coalesce(ct.data->>'partyId',ct.data->>'party_id','') party_id,
        public.erp_r49_normalize_supported_currency(ct.data->>'currency') currency,
        0::bigint document_count,0::numeric total_amount,
        public.erp_try_numeric(ct.data->>'amount',0) paid_amount,
        -public.erp_try_numeric(ct.data->>'amount',0) outstanding_amount,
        1::bigint payment_count,0::bigint overdue_count,null::timestamptz due_date,
        coalesce(public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),ct.created_at) document_date
      from public.erp_cash_transactions ct
      where ct.company_id=p_company_id and not ct.is_deleted
        and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='partner_advance'
        and public.erp_try_boolean(ct.data->>'unapplied',false)
        and lower(coalesce(ct.data->>'partyType',ct.data->>'party_type',''))='supplier'
    ), combined as (select * from docs union all select * from advances)
    select c.party_id,
      coalesce(nullif(sp.data->>'name',''),nullif(sp.data->>'companyName',''),'مورد غير مسمى') party_name,
      c.currency,sum(c.document_count)::bigint,sum(c.total_amount),sum(c.paid_amount),sum(c.outstanding_amount),
      sum(c.payment_count)::bigint,sum(c.overdue_count)::bigint,min(c.due_date),max(c.document_date)
    from combined c
    left join public.erp_suppliers sp on sp.company_id=p_company_id and sp.id::text=c.party_id and not sp.is_deleted
    where c.party_id<>'' and c.currency is not null
    group by c.party_id,party_name,c.currency
    having abs(sum(c.outstanding_amount))>0.005 or sum(c.payment_count)>0
    order by c.currency,sum(c.outstanding_amount) desc,party_name;
    return;
  end if;

  raise exception 'unsupported_subledger_kind' using errcode='22023';
end;
$$;

create or replace function public.erp_cloud_partner_subledger_documents(
  p_company_id uuid,
  p_kind text,
  p_party_id text,
  p_currency text
) returns table(
  document_number text,document_date timestamptz,due_date timestamptz,
  currency text,total_amount numeric,paid_amount numeric,
  outstanding_amount numeric,payment_count bigint,is_overdue boolean,status text
)
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_currency text;
begin
  perform public.erp_r49_assert_subledger_currency_integrity(p_company_id);
  v_currency:=public.erp_r49_normalize_supported_currency(p_currency);
  if v_currency is null then
    raise exception 'unsupported_currency:%',coalesce(p_currency,'') using errcode='22023';
  end if;

  if lower(coalesce(p_kind,''))='receivables' then
    return query
    select * from (
      select coalesce(nullif(s.data->>'invoiceNumber',''),nullif(s.data->>'saleNumber',''),nullif(s.data->>'documentNumber',''),'بدون رقم') document_number,
        coalesce(public.erp_try_timestamptz(s.data->>'saleDate',null),s.created_at) document_date,
        coalesce(public.erp_try_timestamptz(s.data->>'dueDate',null),public.erp_try_timestamptz(s.data->>'saleDate',null),s.created_at) due_date,
        public.erp_r49_normalize_supported_currency(
          coalesce(nullif(btrim(s.data->>'currencyCode'),''),nullif(btrim(s.data->>'currency'),''))
        ) currency,
        greatest(public.erp_try_numeric(coalesce(s.data->>'totalAmount',s.data->>'salePrice'),0),0) total_amount,
        greatest(public.erp_try_numeric(s.data->>'paidAmount',0),0) paid_amount,
        greatest(public.erp_try_numeric(s.data->>'remainingAmount',0),0) outstanding_amount,
        (case when jsonb_typeof(s.data->'payments')='array' then jsonb_array_length(s.data->'payments') else 0 end)::bigint payment_count,
        coalesce(public.erp_try_timestamptz(s.data->>'dueDate',null),public.erp_try_timestamptz(s.data->>'saleDate',null),s.created_at)<now() is_overdue,
        coalesce(nullif(s.data->>'paymentStatus',''),nullif(s.data->>'status',''),'unpaid') status
      from public.erp_sales s
      where s.company_id=p_company_id and not s.is_deleted
        and coalesce(s.data->>'customerId','')=coalesce(p_party_id,'')
        and public.erp_r49_normalize_supported_currency(
          coalesce(nullif(btrim(s.data->>'currencyCode'),''),nullif(btrim(s.data->>'currency'),''))
        )=v_currency
        and public.erp_try_numeric(s.data->>'remainingAmount',0)>0
      union all
      select coalesce(nullif(ct.data->>'voucherNumber',''),nullif(ct.data->>'voucher_number',''),'بدون رقم'),
        coalesce(public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),ct.created_at),
        coalesce(public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),ct.created_at),
        public.erp_r49_normalize_supported_currency(ct.data->>'currency'),0::numeric,
        public.erp_try_numeric(ct.data->>'amount',0),-public.erp_try_numeric(ct.data->>'amount',0),
        1::bigint,false,'unapplied_credit'::text
      from public.erp_cash_transactions ct
      where ct.company_id=p_company_id and not ct.is_deleted
        and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='partner_advance'
        and public.erp_try_boolean(ct.data->>'unapplied',false)
        and lower(coalesce(ct.data->>'partyType',ct.data->>'party_type',''))='customer'
        and coalesce(ct.data->>'partyId',ct.data->>'party_id','')=coalesce(p_party_id,'')
        and public.erp_r49_normalize_supported_currency(ct.data->>'currency')=v_currency
    ) x order by x.due_date,x.document_date,x.document_number;
    return;
  end if;

  if lower(coalesce(p_kind,''))='payables' then
    return query
    select * from (
      select coalesce(nullif(p.data->>'invoiceNumber',''),nullif(p.data->>'purchaseNumber',''),nullif(p.data->>'documentNumber',''),'بدون رقم') document_number,
        coalesce(public.erp_try_timestamptz(p.data->>'purchaseDate',null),p.created_at) document_date,
        coalesce(public.erp_try_timestamptz(p.data->>'dueDate',null),public.erp_try_timestamptz(p.data->>'purchaseDate',null),p.created_at) due_date,
        public.erp_r49_normalize_supported_currency(
          coalesce(nullif(btrim(p.data->>'currencyCode'),''),nullif(btrim(p.data->>'currency'),''))
        ) currency,
        greatest(public.erp_try_numeric(p.data->>'totalAmount',0),0) total_amount,
        greatest(public.erp_try_numeric(p.data->>'paidAmount',0),0) paid_amount,
        greatest(public.erp_try_numeric(
          p.data->>'remainingAmount',
          public.erp_try_numeric(p.data->>'totalAmount',0)-public.erp_try_numeric(p.data->>'paidAmount',0)
        ),0) outstanding_amount,
        (case when jsonb_typeof(p.data->'payments')='array' then jsonb_array_length(p.data->'payments') else 0 end)::bigint payment_count,
        coalesce(public.erp_try_timestamptz(p.data->>'dueDate',null),public.erp_try_timestamptz(p.data->>'purchaseDate',null),p.created_at)<now() is_overdue,
        coalesce(nullif(p.data->>'paymentStatus',''),nullif(p.data->>'status',''),'unpaid') status
      from public.erp_purchases p
      where p.company_id=p_company_id and not p.is_deleted
        and coalesce(p.data->>'supplierId','')=coalesce(p_party_id,'')
        and public.erp_r49_normalize_supported_currency(
          coalesce(nullif(btrim(p.data->>'currencyCode'),''),nullif(btrim(p.data->>'currency'),''))
        )=v_currency
        and public.erp_try_numeric(
          p.data->>'remainingAmount',
          public.erp_try_numeric(p.data->>'totalAmount',0)-public.erp_try_numeric(p.data->>'paidAmount',0)
        )>0
      union all
      select coalesce(nullif(ct.data->>'voucherNumber',''),nullif(ct.data->>'voucher_number',''),'بدون رقم'),
        coalesce(public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),ct.created_at),
        coalesce(public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),ct.created_at),
        public.erp_r49_normalize_supported_currency(ct.data->>'currency'),0::numeric,
        public.erp_try_numeric(ct.data->>'amount',0),-public.erp_try_numeric(ct.data->>'amount',0),
        1::bigint,false,'unapplied_debit'::text
      from public.erp_cash_transactions ct
      where ct.company_id=p_company_id and not ct.is_deleted
        and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='partner_advance'
        and public.erp_try_boolean(ct.data->>'unapplied',false)
        and lower(coalesce(ct.data->>'partyType',ct.data->>'party_type',''))='supplier'
        and coalesce(ct.data->>'partyId',ct.data->>'party_id','')=coalesce(p_party_id,'')
        and public.erp_r49_normalize_supported_currency(ct.data->>'currency')=v_currency
    ) x order by x.due_date,x.document_date,x.document_number;
    return;
  end if;

  raise exception 'unsupported_subledger_kind' using errcode='22023';
end;
$$;

-- Browser callers must use the R9/R22 permission-filtered report surface.
-- The underlying SECURITY DEFINER implementations stay internal so field-level
-- accounting/report permissions cannot be bypassed by calling the base RPCs.
revoke all on function public.erp_cloud_receivables_payables(uuid) from public,anon,authenticated;
revoke all on function public.erp_cloud_partner_subledger_details_v2(uuid,text) from public,anon,authenticated;
revoke all on function public.erp_cloud_partner_subledger_documents(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.erp_cloud_receivables_payables(uuid) to service_role;
grant execute on function public.erp_cloud_partner_subledger_details_v2(uuid,text) to service_role;
grant execute on function public.erp_cloud_partner_subledger_documents(uuid,text,text,text) to service_role;

revoke all on function public.erp_r49_normalize_supported_currency(text) from public,anon,authenticated;
revoke all on function public.erp_r49_assert_subledger_currency_integrity(uuid) from public,anon,authenticated;
grant execute on function public.erp_r49_normalize_supported_currency(text) to service_role;
grant execute on function public.erp_r49_assert_subledger_currency_integrity(uuid) to service_role;

-- Dashboard/report currency integrity is broader than open subledger balances:
-- every financial row that participates in a monetary aggregate must carry an
-- explicit supported currency. Never classify a persisted row as USD by
-- omission. Optional date bounds limit document/expense checks for reports;
-- inventory valuation is always a current balance and is therefore checked in
-- full.
create or replace function public.erp_r49_assert_financial_reporting_currency_integrity(
  p_company_id uuid,
  p_start_date date default null,
  p_end_date date default null
) returns void
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_start date:=p_start_date;
  v_end date:=p_end_date;
begin
  if not public.is_active_company_member(p_company_id) then
    raise exception 'company_access_denied' using errcode='42501';
  end if;
  if v_start is not null and v_end is not null and v_start>v_end then
    raise exception 'invalid_report_date_range' using errcode='22023';
  end if;

  if exists(
    select 1 from public.erp_sales s
    where s.company_id=p_company_id and not coalesce(s.is_deleted,false)
      and (v_start is null or coalesce(public.erp_try_date(s.data->>'saleDate',null),s.created_at::date)>=v_start)
      and (v_end is null or coalesce(public.erp_try_date(s.data->>'saleDate',null),s.created_at::date)<=v_end)
      and public.erp_r49_normalize_supported_currency(
        coalesce(nullif(btrim(s.data->>'currencyCode'),''),nullif(btrim(s.data->>'currency'),''))
      ) is null
  ) then
    raise exception 'financial_document_currency_invalid:sales' using errcode='22023';
  end if;

  if exists(
    select 1 from public.erp_commercial_workflow_documents d
    where d.company_id=p_company_id and d.module='sales' and d.document_type='invoice'
      and d.status='approved' and not d.is_deleted
      and (v_start is null or coalesce(d.effective_at,d.created_at)::date>=v_start)
      and (v_end is null or coalesce(d.effective_at,d.created_at)::date<=v_end)
      and public.erp_r49_normalize_supported_currency(d.payload->>'currency') is null
  ) then
    raise exception 'financial_document_currency_invalid:sales_invoice' using errcode='22023';
  end if;

  if exists(
    select 1 from public.erp_purchases p
    where p.company_id=p_company_id and not coalesce(p.is_deleted,false)
      and (v_start is null or coalesce(public.erp_try_date(p.data->>'purchaseDate',null),p.created_at::date)>=v_start)
      and (v_end is null or coalesce(public.erp_try_date(p.data->>'purchaseDate',null),p.created_at::date)<=v_end)
      and public.erp_r49_normalize_supported_currency(
        coalesce(nullif(btrim(p.data->>'currencyCode'),''),nullif(btrim(p.data->>'currency'),''))
      ) is null
  ) then
    raise exception 'financial_document_currency_invalid:purchases' using errcode='22023';
  end if;

  if exists(
    select 1 from public.erp_commercial_workflow_documents d
    where d.company_id=p_company_id and d.module='purchases' and d.document_type='invoice'
      and d.status='approved' and not d.is_deleted
      and (v_start is null or coalesce(d.effective_at,d.created_at)::date>=v_start)
      and (v_end is null or coalesce(d.effective_at,d.created_at)::date<=v_end)
      and public.erp_r49_normalize_supported_currency(d.payload->>'currency') is null
  ) then
    raise exception 'financial_document_currency_invalid:purchase_invoice' using errcode='22023';
  end if;

  if exists(
    select 1 from public.erp_expenses e
    where e.company_id=p_company_id and not coalesce(e.is_deleted,false)
      and (v_start is null or coalesce(public.erp_try_date(e.data->>'date',null),e.created_at::date)>=v_start)
      and (v_end is null or coalesce(public.erp_try_date(e.data->>'date',null),e.created_at::date)<=v_end)
      and public.erp_r49_normalize_supported_currency(
        coalesce(nullif(btrim(e.data->>'currency'),''),nullif(btrim(e.data->>'currencyCode'),''))
      ) is null
  ) then
    raise exception 'financial_document_currency_invalid:expenses' using errcode='22023';
  end if;

  if exists(
    select 1 from public.erp_inventory_cost_layers l
    where l.company_id=p_company_id and l.status in ('active','consumed')
      and l.remaining_quantity>0
      and l.item_type in ('product','car')
      and public.erp_r49_normalize_supported_currency(l.currency) is null
  ) then
    raise exception 'financial_document_currency_invalid:inventory_cost_layer' using errcode='22023';
  end if;
end;
$$;

create or replace function public.erp_r49_financial_summary_by_currency(
  p_company_id uuid,p_reference_day date default current_date
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_sales jsonb:='{}'::jsonb;
  v_today_sales jsonb:='{}'::jsonb;
  v_paid_sales jsonb:='{}'::jsonb;
  v_receivables jsonb:='{}'::jsonb;
  v_purchases jsonb:='{}'::jsonb;
  v_payables jsonb:='{}'::jsonb;
  v_expenses jsonb:='{}'::jsonb;
  v_inventory jsonb:='{}'::jsonb;
  v_profit jsonb:='{}'::jsonb;
begin
  perform public.erp_r49_assert_financial_reporting_currency_integrity(p_company_id,null,null);

  with rows as (
    select public.erp_r49_normalize_supported_currency(
             coalesce(nullif(btrim(s.data->>'currencyCode'),''),nullif(btrim(s.data->>'currency'),''))
           ) currency,
           public.erp_try_numeric(s.data->>'salePrice',0) total,
           public.erp_try_numeric(s.data->>'paidAmount',0) paid,
           public.erp_try_numeric(s.data->>'remainingAmount',0) remaining,
           public.erp_try_date(s.data->>'saleDate',null) effective_day
    from public.erp_sales s
    where s.company_id=p_company_id and not coalesce(s.is_deleted,false)
    union all
    select public.erp_r49_normalize_supported_currency(d.payload->>'currency'),
           public.erp_try_numeric(d.payload->>'totalAmount',0),
           public.erp_try_numeric(d.payload->>'paidAmount',0),
           public.erp_try_numeric(d.payload->>'remainingAmount',0),
           coalesce(d.effective_at,d.created_at)::date
    from public.erp_commercial_workflow_documents d
    where d.company_id=p_company_id and d.module='sales' and d.document_type='invoice'
      and d.status='approved' and not d.is_deleted
  ), grouped as (
    select currency,sum(total) total,sum(paid) paid,sum(remaining) remaining,
           sum(case when effective_day=p_reference_day then total else 0 end) today_total
    from rows group by currency
  )
  select coalesce(jsonb_object_agg(currency,total),'{}'::jsonb),
         coalesce(jsonb_object_agg(currency,paid),'{}'::jsonb),
         coalesce(jsonb_object_agg(currency,remaining),'{}'::jsonb),
         coalesce(jsonb_object_agg(currency,today_total),'{}'::jsonb)
  into v_sales,v_paid_sales,v_receivables,v_today_sales from grouped;

  with rows as (
    select public.erp_r49_normalize_supported_currency(
             coalesce(nullif(btrim(p.data->>'currencyCode'),''),nullif(btrim(p.data->>'currency'),''))
           ) currency,
           public.erp_try_numeric(p.data->>'totalAmount',0) total,
           public.erp_try_numeric(p.data->>'remainingAmount',0) remaining
    from public.erp_purchases p
    where p.company_id=p_company_id and not coalesce(p.is_deleted,false)
    union all
    select public.erp_r49_normalize_supported_currency(d.payload->>'currency'),
           public.erp_try_numeric(d.payload->>'totalAmount',0),
           public.erp_try_numeric(d.payload->>'remainingAmount',0)
    from public.erp_commercial_workflow_documents d
    where d.company_id=p_company_id and d.module='purchases' and d.document_type='invoice'
      and d.status='approved' and not d.is_deleted
  ), grouped as (
    select currency,sum(total) total,sum(remaining) remaining from rows group by currency
  )
  select coalesce(jsonb_object_agg(currency,total),'{}'::jsonb),
         coalesce(jsonb_object_agg(currency,remaining),'{}'::jsonb)
  into v_purchases,v_payables from grouped;

  with grouped as (
    select public.erp_r49_normalize_supported_currency(
             coalesce(nullif(btrim(e.data->>'currency'),''),nullif(btrim(e.data->>'currencyCode'),''))
           ) currency,
           sum(public.erp_try_numeric(e.data->>'amount',0)) amount
    from public.erp_expenses e
    where e.company_id=p_company_id and not coalesce(e.is_deleted,false)
    group by 1
  )
  select coalesce(jsonb_object_agg(currency,amount),'{}'::jsonb)
  into v_expenses from grouped;

  -- Both products and cars are authoritative FIFO inventory assets. Excluding
  -- car layers understates inventory value for an automotive ERP.
  with grouped as (
    select public.erp_r49_normalize_supported_currency(l.currency) currency,
           sum(l.remaining_quantity*l.unit_cost) amount
    from public.erp_inventory_cost_layers l
    where l.company_id=p_company_id and l.status in ('active','consumed')
      and l.remaining_quantity>0 and l.item_type in ('product','car')
    group by 1
  )
  select coalesce(jsonb_object_agg(currency,amount),'{}'::jsonb)
  into v_inventory from grouped;

  with currencies as (select unnest(array['USD','IQD']) currency), amounts as (
    select c.currency,
      coalesce((v_sales->>c.currency)::numeric,0)
      -coalesce((v_purchases->>c.currency)::numeric,0)
      -coalesce((v_expenses->>c.currency)::numeric,0) amount
    from currencies c
  ) select jsonb_object_agg(currency,amount) into v_profit from amounts;

  return jsonb_build_object(
    'totalSalesByCurrency',v_sales,'todaySalesByCurrency',v_today_sales,
    'totalPaidSalesByCurrency',v_paid_sales,'totalReceivablesByCurrency',v_receivables,
    'totalPurchasesByCurrency',v_purchases,'totalPayablesByCurrency',v_payables,
    'totalPurchaseDebtByCurrency',v_payables,'totalExpensesByCurrency',v_expenses,
    'inventoryValueByCurrency',v_inventory,'netProfitByCurrency',v_profit
  );
end;
$$;

create or replace function public.erp_r49_financial_report_summary_by_currency(
  p_company_id uuid,p_start_date date default null,p_end_date date default null
) returns jsonb
language plpgsql stable security definer set search_path=public
as $$
declare
  d1 date:=coalesce(p_start_date,current_date-365);
  d2 date:=coalesce(p_end_date,current_date);
  v_sales jsonb:='{}'::jsonb; v_paid jsonb:='{}'::jsonb; v_receivables jsonb:='{}'::jsonb;
  v_purchases jsonb:='{}'::jsonb; v_payables jsonb:='{}'::jsonb; v_expenses jsonb:='{}'::jsonb;
  v_inventory jsonb:='{}'::jsonb; v_profit jsonb:='{}'::jsonb;
begin
  if d1>d2 then raise exception 'invalid_report_date_range' using errcode='22023'; end if;
  perform public.erp_r49_assert_financial_reporting_currency_integrity(p_company_id,d1,d2);

  -- Reports and dashboard use the same source families: legacy direct-sale
  -- records plus the canonical approved workflow invoices. Restrict every row
  -- to the selected report period before aggregation.
  with rows as (
    select public.erp_r49_normalize_supported_currency(
             coalesce(nullif(btrim(s.data->>'currencyCode'),''),nullif(btrim(s.data->>'currency'),''))
           ) currency,
           public.erp_try_numeric(s.data->>'salePrice',0) total,
           public.erp_try_numeric(s.data->>'paidAmount',0) paid,
           public.erp_try_numeric(s.data->>'remainingAmount',0) remaining
    from public.erp_sales s
    where s.company_id=p_company_id and not coalesce(s.is_deleted,false)
      and coalesce(public.erp_try_date(s.data->>'saleDate',null),s.created_at::date) between d1 and d2
    union all
    select public.erp_r49_normalize_supported_currency(d.payload->>'currency'),
           public.erp_try_numeric(d.payload->>'totalAmount',0),
           public.erp_try_numeric(d.payload->>'paidAmount',0),
           public.erp_try_numeric(d.payload->>'remainingAmount',0)
    from public.erp_commercial_workflow_documents d
    where d.company_id=p_company_id and d.module='sales' and d.document_type='invoice'
      and d.status='approved' and not d.is_deleted
      and coalesce(d.effective_at,d.created_at)::date between d1 and d2
  ), grouped as (
    select currency,sum(total) total,sum(paid) paid,sum(remaining) remaining
    from rows group by currency
  )
  select coalesce(jsonb_object_agg(currency,total),'{}'::jsonb),
         coalesce(jsonb_object_agg(currency,paid),'{}'::jsonb),
         coalesce(jsonb_object_agg(currency,remaining),'{}'::jsonb)
  into v_sales,v_paid,v_receivables from grouped;

  with rows as (
    select public.erp_r49_normalize_supported_currency(
             coalesce(nullif(btrim(p.data->>'currencyCode'),''),nullif(btrim(p.data->>'currency'),''))
           ) currency,
           public.erp_try_numeric(p.data->>'totalAmount',0) total,
           public.erp_try_numeric(p.data->>'remainingAmount',0) remaining
    from public.erp_purchases p
    where p.company_id=p_company_id and not coalesce(p.is_deleted,false)
      and coalesce(public.erp_try_date(p.data->>'purchaseDate',null),p.created_at::date) between d1 and d2
    union all
    select public.erp_r49_normalize_supported_currency(d.payload->>'currency'),
           public.erp_try_numeric(d.payload->>'totalAmount',0),
           public.erp_try_numeric(d.payload->>'remainingAmount',0)
    from public.erp_commercial_workflow_documents d
    where d.company_id=p_company_id and d.module='purchases' and d.document_type='invoice'
      and d.status='approved' and not d.is_deleted
      and coalesce(d.effective_at,d.created_at)::date between d1 and d2
  ), grouped as (
    select currency,sum(total) total,sum(remaining) remaining from rows group by currency
  )
  select coalesce(jsonb_object_agg(currency,total),'{}'::jsonb),
         coalesce(jsonb_object_agg(currency,remaining),'{}'::jsonb)
  into v_purchases,v_payables from grouped;

  with grouped as (
    select public.erp_r49_normalize_supported_currency(
             coalesce(nullif(btrim(e.data->>'currency'),''),nullif(btrim(e.data->>'currencyCode'),''))
           ) currency,
           sum(public.erp_try_numeric(e.data->>'amount',0)) amount
    from public.erp_expenses e
    where e.company_id=p_company_id and not coalesce(e.is_deleted,false)
      and coalesce(public.erp_try_date(e.data->>'date',null),e.created_at::date) between d1 and d2
    group by 1
  ) select coalesce(jsonb_object_agg(currency,amount),'{}'::jsonb) into v_expenses from grouped;

  with grouped as (
    select public.erp_r49_normalize_supported_currency(l.currency) currency,
           sum(l.remaining_quantity*l.unit_cost) amount
    from public.erp_inventory_cost_layers l
    where l.company_id=p_company_id and l.status in ('active','consumed')
      and l.remaining_quantity>0 and l.item_type in ('product','car')
    group by 1
  ) select coalesce(jsonb_object_agg(currency,amount),'{}'::jsonb) into v_inventory from grouped;

  with currencies as (select unnest(array['USD','IQD']) currency), amounts as (
    select c.currency,coalesce((v_sales->>c.currency)::numeric,0)
      -coalesce((v_purchases->>c.currency)::numeric,0)
      -coalesce((v_expenses->>c.currency)::numeric,0) amount
    from currencies c
  ) select jsonb_object_agg(currency,amount) into v_profit from amounts;

  return jsonb_build_object(
    'totalSalesByCurrency',v_sales,'totalPaidSalesByCurrency',v_paid,
    'totalReceivablesByCurrency',v_receivables,'totalPurchasesByCurrency',v_purchases,
    'totalPurchaseDebtByCurrency',v_payables,'totalExpensesByCurrency',v_expenses,
    'inventoryValueByCurrency',v_inventory,'netProfitByCurrency',v_profit
  );
end;
$$;

-- These helpers are internal implementation details behind R9 permission-
-- filtered dashboard/report RPCs. Browser roles must not bypass those field
-- permissions by calling the helpers directly.
revoke all on function public.erp_r49_financial_summary_by_currency(uuid,date) from public,anon,authenticated;
revoke all on function public.erp_r49_financial_report_summary_by_currency(uuid,date,date) from public,anon,authenticated;
revoke all on function public.erp_r49_assert_financial_reporting_currency_integrity(uuid,date,date) from public,anon,authenticated;
grant execute on function public.erp_r49_financial_summary_by_currency(uuid,date) to service_role;
grant execute on function public.erp_r49_financial_report_summary_by_currency(uuid,date,date) to service_role;
grant execute on function public.erp_r49_assert_financial_reporting_currency_integrity(uuid,date,date) to service_role;

notify pgrst,'reload schema';
commit;
