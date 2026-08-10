begin;

-- Runtime-visible maintenance selector completion. Expose separate vehicle-card
-- fields so the Flutter client can localize every label instead of embedding
-- English labels in a server-composed display string.
drop function if exists public.erp_list_cloud_maintenance_eligible_cars(uuid);
create function public.erp_list_cloud_maintenance_eligible_cars(p_company_id uuid)
returns table(
  "carId" text,
  "displayName" text,
  "customerId" text,
  "customerName" text,
  "saleSequence" integer,
  brand text,
  model text,
  year integer,
  chassis text,
  "plateNumber" text,
  "carNumber" text,
  color text
)
language sql security definer set search_path=public as $$
  with latest_sale as (
    select distinct on (coalesce(nullif(s.data->>'carId',''),nullif(s.data->>'vehicleId','')))
      coalesce(nullif(s.data->>'carId',''),nullif(s.data->>'vehicleId','')) car_id,
      coalesce(nullif(s.data->>'customerId',''),nullif(s.data->>'clientId','')) customer_id,
      public.erp_try_numeric(s.data->>'saleSequence',0)::integer sale_sequence
    from public.erp_sales s
    where s.company_id=p_company_id and not s.is_deleted
      and coalesce(nullif(s.data->>'carId',''),nullif(s.data->>'vehicleId','')) is not null
      and coalesce(nullif(s.data->>'customerId',''),nullif(s.data->>'clientId','')) is not null
      and lower(coalesce(s.data->>'status','completed')) not in ('cancelled','deleted')
    order by coalesce(nullif(s.data->>'carId',''),nullif(s.data->>'vehicleId','')),
      public.erp_try_numeric(s.data->>'saleSequence',0) desc,
      coalesce(s.data->>'saleDate',s.created_at::text) desc
  )
  select c.id::text,
    nullif(concat_ws(' ',c.data->>'brand',c.data->>'model',c.data->>'year'),' '),
    ls.customer_id,
    coalesce(nullif(cu.data->>'name',''),nullif(concat_ws(' ',cu.data->>'firstName',cu.data->>'lastName'),' '),ls.customer_id),
    ls.sale_sequence,
    nullif(c.data->>'brand',''),
    nullif(c.data->>'model',''),
    public.erp_try_numeric(c.data->>'year',0)::integer,
    nullif(c.data->>'chassis',''),
    nullif(c.data->>'plateNumber',''),
    nullif(c.data->>'carNumber',''),
    nullif(c.data->>'color','')
  from latest_sale ls
  join public.erp_cars c on c.company_id=p_company_id and c.id::text=ls.car_id and not c.is_deleted
  left join public.erp_customers cu on cu.company_id=p_company_id and cu.id::text=ls.customer_id and not cu.is_deleted
  where public.erp_active_company_context(p_company_id) is not null
  order by 2;
$$;
revoke all on function public.erp_list_cloud_maintenance_eligible_cars(uuid) from public,anon;
grant execute on function public.erp_list_cloud_maintenance_eligible_cars(uuid) to authenticated;

commit;
