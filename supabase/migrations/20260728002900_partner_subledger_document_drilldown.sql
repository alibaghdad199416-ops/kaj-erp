-- Document-level drilldown for customer and supplier subledgers.
-- Values remain in the original document currency; no exchange conversion occurs.

begin;

create or replace function public.erp_cloud_partner_subledger_documents(
  p_company_id uuid,
  p_kind text,
  p_party_id text,
  p_currency text
)
returns table(
  document_number text,
  document_date timestamptz,
  due_date timestamptz,
  currency text,
  total_amount numeric,
  paid_amount numeric,
  outstanding_amount numeric,
  payment_count bigint,
  is_overdue boolean,
  status text
)
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not public.is_active_company_member(p_company_id) then
    raise exception 'company_access_denied';
  end if;

  if lower(coalesce(p_kind,'')) = 'receivables' then
    return query
    select
      coalesce(
        nullif(s.data->>'invoiceNumber',''),
        nullif(s.data->>'saleNumber',''),
        nullif(s.data->>'documentNumber',''),
        'بدون رقم'
      ) as document_number,
      coalesce(public.erp_try_timestamptz(s.data->>'saleDate',null),s.created_at) as document_date,
      coalesce(
        public.erp_try_timestamptz(s.data->>'dueDate',null),
        public.erp_try_timestamptz(s.data->>'saleDate',null),
        s.created_at
      ) as due_date,
      upper(coalesce(nullif(s.data->>'currencyCode',''),nullif(s.data->>'currency',''),'USD')) as currency,
      greatest(public.erp_try_numeric(coalesce(s.data->>'totalAmount',s.data->>'salePrice'),0),0) as total_amount,
      greatest(public.erp_try_numeric(s.data->>'paidAmount',0),0) as paid_amount,
      greatest(public.erp_try_numeric(s.data->>'remainingAmount',0),0) as outstanding_amount,
      (case when jsonb_typeof(s.data->'payments')='array' then jsonb_array_length(s.data->'payments') else 0 end)::bigint as payment_count,
      coalesce(
        public.erp_try_timestamptz(s.data->>'dueDate',null),
        public.erp_try_timestamptz(s.data->>'saleDate',null),
        s.created_at
      ) < now() as is_overdue,
      coalesce(nullif(s.data->>'paymentStatus',''),nullif(s.data->>'status',''),'unpaid') as status
    from public.erp_sales s
    where s.company_id=p_company_id
      and not s.is_deleted
      and coalesce(s.data->>'customerId','')=coalesce(p_party_id,'')
      and upper(coalesce(nullif(s.data->>'currencyCode',''),nullif(s.data->>'currency',''),'USD'))=upper(coalesce(p_currency,'USD'))
      and public.erp_try_numeric(s.data->>'remainingAmount',0)>0
    order by due_date,document_date,document_number;
    return;
  end if;

  if lower(coalesce(p_kind,'')) = 'payables' then
    return query
    select
      coalesce(
        nullif(p.data->>'invoiceNumber',''),
        nullif(p.data->>'purchaseNumber',''),
        nullif(p.data->>'documentNumber',''),
        'بدون رقم'
      ) as document_number,
      coalesce(public.erp_try_timestamptz(p.data->>'purchaseDate',null),p.created_at) as document_date,
      coalesce(
        public.erp_try_timestamptz(p.data->>'dueDate',null),
        public.erp_try_timestamptz(p.data->>'purchaseDate',null),
        p.created_at
      ) as due_date,
      upper(coalesce(nullif(p.data->>'currencyCode',''),nullif(p.data->>'currency',''),'USD')) as currency,
      greatest(public.erp_try_numeric(p.data->>'totalAmount',0),0) as total_amount,
      greatest(public.erp_try_numeric(p.data->>'paidAmount',0),0) as paid_amount,
      greatest(
        public.erp_try_numeric(
          p.data->>'remainingAmount',
          public.erp_try_numeric(p.data->>'totalAmount',0)-public.erp_try_numeric(p.data->>'paidAmount',0)
        ),0
      ) as outstanding_amount,
      (case when jsonb_typeof(p.data->'payments')='array' then jsonb_array_length(p.data->'payments') else 0 end)::bigint as payment_count,
      coalesce(
        public.erp_try_timestamptz(p.data->>'dueDate',null),
        public.erp_try_timestamptz(p.data->>'purchaseDate',null),
        p.created_at
      ) < now() as is_overdue,
      coalesce(nullif(p.data->>'paymentStatus',''),nullif(p.data->>'status',''),'unpaid') as status
    from public.erp_purchases p
    where p.company_id=p_company_id
      and not p.is_deleted
      and coalesce(p.data->>'supplierId','')=coalesce(p_party_id,'')
      and upper(coalesce(nullif(p.data->>'currencyCode',''),nullif(p.data->>'currency',''),'USD'))=upper(coalesce(p_currency,'USD'))
      and public.erp_try_numeric(
        p.data->>'remainingAmount',
        public.erp_try_numeric(p.data->>'totalAmount',0)-public.erp_try_numeric(p.data->>'paidAmount',0)
      )>0
    order by due_date,document_date,document_number;
    return;
  end if;

  raise exception 'unsupported_subledger_kind';
end;
$$;

comment on function public.erp_cloud_partner_subledger_documents(uuid,text,text,text) is
  'Lists outstanding partner documents in their original currency without exposing internal identifiers or applying exchange conversion.';

grant execute on function public.erp_cloud_partner_subledger_documents(uuid,text,text,text) to authenticated;

commit;
