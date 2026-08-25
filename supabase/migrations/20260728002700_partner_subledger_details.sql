-- Detailed customer and supplier subledgers by document currency.
-- Amounts are never converted or aggregated across currencies.

begin;

create or replace function public.erp_cloud_partner_subledger_details(
  p_company_id uuid,
  p_kind text
)
returns table(
  party_id text,
  party_name text,
  currency text,
  document_count bigint,
  outstanding_amount numeric,
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
      sum(greatest(coalesce(nullif(s.data->>'remainingAmount','')::numeric,0),0)) as outstanding_amount,
      min(coalesce(
        nullif(s.data->>'dueDate','')::timestamptz,
        nullif(s.data->>'saleDate','')::timestamptz,
        s.created_at
      )) as oldest_due_date,
      max(coalesce(nullif(s.data->>'saleDate','')::timestamptz,s.created_at)) as latest_document_date
    from public.erp_sales s
    left join public.erp_customers c
      on c.company_id=s.company_id
     and c.id::text=s.data->>'customerId'
     and not c.is_deleted
    where s.company_id=p_company_id
      and not s.is_deleted
      and greatest(coalesce(nullif(s.data->>'remainingAmount','')::numeric,0),0) > 0
    group by 1,2,3
    order by 3,5 desc,2;
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
      sum(greatest(
        coalesce(nullif(p.data->>'remainingAmount','')::numeric,
          coalesce(nullif(p.data->>'totalAmount','')::numeric,0)
          - coalesce(nullif(p.data->>'paidAmount','')::numeric,0)
        ),0
      )) as outstanding_amount,
      min(coalesce(
        nullif(p.data->>'dueDate','')::timestamptz,
        nullif(p.data->>'purchaseDate','')::timestamptz,
        p.created_at
      )) as oldest_due_date,
      max(coalesce(nullif(p.data->>'purchaseDate','')::timestamptz,p.created_at)) as latest_document_date
    from public.erp_purchases p
    left join public.erp_suppliers sp
      on sp.company_id=p.company_id
     and sp.id::text=p.data->>'supplierId'
     and not sp.is_deleted
    where p.company_id=p_company_id
      and not p.is_deleted
      and greatest(
        coalesce(nullif(p.data->>'remainingAmount','')::numeric,
          coalesce(nullif(p.data->>'totalAmount','')::numeric,0)
          - coalesce(nullif(p.data->>'paidAmount','')::numeric,0)
        ),0
      ) > 0
    group by 1,2,3
    order by 3,5 desc,2;
    return;
  end if;

  raise exception 'unsupported_subledger_kind';
end;
$$;

comment on function public.erp_cloud_partner_subledger_details(uuid,text) is
  'Lists customer receivables or supplier payables by party and original document currency without exchange-rate conversion.';

grant execute on function public.erp_cloud_partner_subledger_details(uuid,text) to authenticated;

commit;
