-- Partner subledger progress by original document currency.
-- No currency conversion is performed in this read model.

begin;

create or replace function public.erp_cloud_partner_subledger_details_v2(
  p_company_id uuid,
  p_kind text
)
returns table(
  party_id text,
  party_name text,
  currency text,
  document_count bigint,
  total_amount numeric,
  paid_amount numeric,
  outstanding_amount numeric,
  payment_count bigint,
  overdue_document_count bigint,
  oldest_due_date timestamptz,
  latest_document_date timestamptz
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
      coalesce(s.data->>'customerId','') as party_id,
      coalesce(
        nullif(c.data->>'name',''),
        nullif(c.data->>'fullName',''),
        nullif(s.data->>'customerName',''),
        'عميل غير مسمى'
      ) as party_name,
      upper(coalesce(nullif(s.data->>'currencyCode',''), nullif(s.data->>'currency',''), 'USD')) as currency,
      count(*)::bigint as document_count,
      sum(greatest(public.erp_try_numeric(coalesce(s.data->>'totalAmount',s.data->>'salePrice'),0),0)) as total_amount,
      sum(greatest(public.erp_try_numeric(s.data->>'paidAmount',0),0)) as paid_amount,
      sum(greatest(public.erp_try_numeric(s.data->>'remainingAmount',0),0)) as outstanding_amount,
      sum(case when jsonb_typeof(s.data->'payments')='array' then jsonb_array_length(s.data->'payments') else 0 end)::bigint as payment_count,
      count(*) filter (
        where coalesce(
          public.erp_try_timestamptz(s.data->>'dueDate',null),
          public.erp_try_timestamptz(s.data->>'saleDate',null),
          s.created_at
        ) < now()
        and public.erp_try_numeric(s.data->>'remainingAmount',0) > 0
      )::bigint as overdue_document_count,
      min(coalesce(
        public.erp_try_timestamptz(s.data->>'dueDate',null),
        public.erp_try_timestamptz(s.data->>'saleDate',null),
        s.created_at
      )) as oldest_due_date,
      max(coalesce(public.erp_try_timestamptz(s.data->>'saleDate',null),s.created_at)) as latest_document_date
    from public.erp_sales s
    left join public.erp_customers c
      on c.company_id=s.company_id
     and c.id::text=s.data->>'customerId'
     and not c.is_deleted
    where s.company_id=p_company_id
      and not s.is_deleted
      and public.erp_try_numeric(s.data->>'remainingAmount',0) > 0
    group by 1,2,3
    order by 3,7 desc,2;
    return;
  end if;

  if lower(coalesce(p_kind,'')) = 'payables' then
    return query
    select
      coalesce(p.data->>'supplierId','') as party_id,
      coalesce(
        nullif(sp.data->>'name',''),
        nullif(sp.data->>'companyName',''),
        nullif(p.data->>'supplierName',''),
        'مورد غير مسمى'
      ) as party_name,
      upper(coalesce(nullif(p.data->>'currencyCode',''), nullif(p.data->>'currency',''), 'USD')) as currency,
      count(*)::bigint as document_count,
      sum(greatest(public.erp_try_numeric(p.data->>'totalAmount',0),0)) as total_amount,
      sum(greatest(public.erp_try_numeric(p.data->>'paidAmount',0),0)) as paid_amount,
      sum(greatest(
        public.erp_try_numeric(
          p.data->>'remainingAmount',
          public.erp_try_numeric(p.data->>'totalAmount',0)-public.erp_try_numeric(p.data->>'paidAmount',0)
        ),0
      )) as outstanding_amount,
      sum(case when jsonb_typeof(p.data->'payments')='array' then jsonb_array_length(p.data->'payments') else 0 end)::bigint as payment_count,
      count(*) filter (
        where coalesce(
          public.erp_try_timestamptz(p.data->>'dueDate',null),
          public.erp_try_timestamptz(p.data->>'purchaseDate',null),
          p.created_at
        ) < now()
        and public.erp_try_numeric(
          p.data->>'remainingAmount',
          public.erp_try_numeric(p.data->>'totalAmount',0)-public.erp_try_numeric(p.data->>'paidAmount',0)
        ) > 0
      )::bigint as overdue_document_count,
      min(coalesce(
        public.erp_try_timestamptz(p.data->>'dueDate',null),
        public.erp_try_timestamptz(p.data->>'purchaseDate',null),
        p.created_at
      )) as oldest_due_date,
      max(coalesce(public.erp_try_timestamptz(p.data->>'purchaseDate',null),p.created_at)) as latest_document_date
    from public.erp_purchases p
    left join public.erp_suppliers sp
      on sp.company_id=p.company_id
     and sp.id::text=p.data->>'supplierId'
     and not sp.is_deleted
    where p.company_id=p_company_id
      and not p.is_deleted
      and public.erp_try_numeric(
        p.data->>'remainingAmount',
        public.erp_try_numeric(p.data->>'totalAmount',0)-public.erp_try_numeric(p.data->>'paidAmount',0)
      ) > 0
    group by 1,2,3
    order by 3,7 desc,2;
    return;
  end if;

  raise exception 'unsupported_subledger_kind';
end;
$$;

comment on function public.erp_cloud_partner_subledger_details_v2(uuid,text) is
  'Lists partner balances, payment progress, and overdue document counts by original document currency without conversion.';

grant execute on function public.erp_cloud_partner_subledger_details_v2(uuid,text) to authenticated;

commit;
