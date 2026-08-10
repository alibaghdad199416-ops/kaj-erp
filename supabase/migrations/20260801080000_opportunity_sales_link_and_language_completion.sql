-- Quality Line ERP 18.7.1
-- Finalize the one-to-one operational link between commercial opportunities
-- and sales orders, and repair existing opportunity payloads.
begin;

-- Keep only one non-deleted sales order per opportunity. Existing duplicates
-- are retained for audit, but all except the newest active order are detached.
with ranked as (
  select id,
         row_number() over (
           partition by company_id, opportunity_id
           order by updated_at desc nulls last, created_at desc nulls last, id desc
         ) as rn
  from public.erp_sales_orders_cloud
  where not coalesce(is_deleted,false)
    and nullif(btrim(coalesce(opportunity_id,'')),'') is not null
)
update public.erp_sales_orders_cloud o
set opportunity_id=null,
    updated_at=now()
from ranked r
where o.id=r.id and r.rn>1;

create unique index if not exists erp_sales_orders_cloud_active_opportunity_uq
on public.erp_sales_orders_cloud(company_id, opportunity_id)
where not coalesce(is_deleted,false)
  and nullif(btrim(coalesce(opportunity_id,'')),'') is not null;

create or replace function public.erp_validate_sales_order_opportunity_link()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_slug text;
  v_payload jsonb;
  v_opportunity_customer text;
begin
  if nullif(btrim(coalesce(new.opportunity_id,'')),'') is null then
    return new;
  end if;

  select slug into v_slug from public.companies where id=new.company_id;
  if v_slug is null then
    raise exception 'company_not_found';
  end if;

  select payload into v_payload
  from public.erp_records
  where company_id=v_slug
    and entity_type='opportunities'
    and record_id=new.opportunity_id
    and deleted_at is null
  limit 1;

  if v_payload is null then
    raise exception 'opportunity_not_found';
  end if;

  if lower(coalesce(v_payload->>'status','pending'))='lost' then
    raise exception 'lost_opportunity_cannot_create_sales_order';
  end if;

  v_opportunity_customer := nullif(btrim(coalesce(v_payload->>'customerId','')),'');
  if v_opportunity_customer is not null
     and v_opportunity_customer is distinct from new.customer_id then
    raise exception 'opportunity_customer_mismatch';
  end if;

  return new;
end;
$$;

drop trigger if exists erp_validate_sales_order_opportunity_link_trg
on public.erp_sales_orders_cloud;
create trigger erp_validate_sales_order_opportunity_link_trg
before insert or update of company_id,customer_id,opportunity_id,is_deleted
on public.erp_sales_orders_cloud
for each row
when (not coalesce(new.is_deleted,false))
execute function public.erp_validate_sales_order_opportunity_link();

-- Extend lifecycle synchronization so the opportunity always carries the
-- authoritative linked sales-order identity and status.
create or replace function public.erp_sync_opportunity_sales_lifecycle(
  p_company_id uuid,
  p_opportunity_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_slug text;
  v_order public.erp_sales_orders_cloud%rowtype;
  v_status text := 'pending';
  v_closed_at timestamptz;
  v_order_id text;
  v_order_number text;
  v_order_status text;
begin
  if nullif(btrim(coalesce(p_opportunity_id,'')),'') is null then return; end if;
  select slug into v_slug from public.companies where id=p_company_id;
  if v_slug is null then return; end if;

  select * into v_order
  from public.erp_sales_orders_cloud
  where company_id=p_company_id
    and opportunity_id=p_opportunity_id
    and not coalesce(is_deleted,false)
  order by updated_at desc nulls last, created_at desc nulls last, id desc
  limit 1;

  if found then
    v_order_id := v_order.id::text;
    v_order_number := v_order.order_number;
    v_order_status := lower(coalesce(v_order.status,'draft'));
    if v_order_status='approved' then
      v_status := 'won';
      v_closed_at := now();
    end if;
  end if;

  update public.erp_records
  set payload = payload || jsonb_build_object(
        'status',v_status,
        'salesOrderId',v_order_id,
        'salesOrderNumber',v_order_number,
        'salesOrderStatus',v_order_status,
        'saleId',v_order_id,
        'invoiceNumber',v_order_number,
        'closedAt',v_closed_at,
        'opportunityStatusSource','sales_order',
        'updatedAt',now()
      ),
      updated_at=now()
  where company_id=v_slug
    and entity_type='opportunities'
    and record_id=p_opportunity_id
    and deleted_at is null;
end;
$$;

grant execute on function public.erp_sync_opportunity_sales_lifecycle(uuid,text) to authenticated;

-- Repair all current links after validation and de-duplication.
do $$
declare r record;
begin
  for r in
    select distinct company_id, opportunity_id
    from public.erp_sales_orders_cloud
    where not coalesce(is_deleted,false)
      and nullif(btrim(coalesce(opportunity_id,'')),'') is not null
  loop
    perform public.erp_sync_opportunity_sales_lifecycle(r.company_id,r.opportunity_id);
  end loop;
end;
$$;

commit;
