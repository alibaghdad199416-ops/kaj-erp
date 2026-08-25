-- One sales order per opportunity and lifecycle synchronization.
begin;

-- Preserve the newest active link and detach legacy duplicates before enforcing uniqueness.
with ranked as (
  select id, row_number() over (
    partition by company_id, opportunity_id order by updated_at desc, created_at desc, id desc
  ) as rn
  from public.erp_sales_orders_cloud
  where opportunity_id is not null and btrim(opportunity_id) <> '' and not is_deleted
)
update public.erp_sales_orders_cloud o
set opportunity_id=null, updated_at=now()
from ranked r where r.id=o.id and r.rn>1;

create unique index if not exists erp_sales_orders_one_active_per_opportunity_uq
  on public.erp_sales_orders_cloud(company_id, opportunity_id)
  where opportunity_id is not null and btrim(opportunity_id) <> '' and not is_deleted;

create or replace function public.erp_sync_opportunity_from_sales_order(
  p_company_id uuid,
  p_opportunity_id text,
  p_order_id uuid,
  p_order_number text,
  p_order_status text,
  p_deleted boolean default false
) returns void
language plpgsql security definer set search_path=public as $$
declare v_slug text; v_status text;
begin
  if nullif(btrim(p_opportunity_id),'') is null then return; end if;
  select slug into v_slug from public.companies where id=p_company_id;
  if v_slug is null then return; end if;
  v_status := case
                   when p_deleted or lower(coalesce(p_order_status,'')) in ('cancelled','canceled','deleted','void') then 'lost'
                   when lower(coalesce(p_order_status,''))='approved' then 'won'
                   else 'pending' end;
  update public.erp_records
     set payload = payload || jsonb_build_object(
           'status',v_status,
           'salesOrderId',p_order_id::text,
           'salesOrderNumber',p_order_number,
           'saleId',p_order_id::text,
           'invoiceNumber',p_order_number,
           'closedAt',case when v_status in ('won','lost') then now() else null end,
           'updatedAt',now()),
         updated_at=now()
   where company_id=v_slug and entity_type='opportunities'
     and record_id=p_opportunity_id and deleted_at is null;
end $$;

create or replace function public.erp_sales_order_opportunity_sync_trigger()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_sync_opportunity_from_sales_order(
    new.company_id,new.opportunity_id,new.id,new.order_number,new.status,new.is_deleted);
  return new;
end $$;

drop trigger if exists erp_sales_order_opportunity_sync on public.erp_sales_orders_cloud;
create trigger erp_sales_order_opportunity_sync
after insert or update of status,is_deleted,opportunity_id,order_number
on public.erp_sales_orders_cloud for each row
execute function public.erp_sales_order_opportunity_sync_trigger();

-- Make creation idempotent for opportunity-originated orders.
create or replace function public.erp_create_cloud_sales_order(
  p_company_id uuid,p_customer_id text,p_currency text,p_exchange_rate numeric,
  p_items jsonb,p_opportunity_id text default null,p_discount numeric default 0,
  p_notes text default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  v_order_id uuid:=gen_random_uuid(); v_existing uuid;
  v_number text:='SO-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  v_subtotal numeric; v_item jsonb; v_opportunity text:=nullif(btrim(p_opportunity_id),'');
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if v_opportunity is not null then
    select id into v_existing from public.erp_sales_orders_cloud
     where company_id=p_company_id and opportunity_id=v_opportunity and not is_deleted
     order by updated_at desc limit 1 for update;
    if v_existing is not null then return v_existing; end if;
  end if;
  if trim(coalesce(p_customer_id,''))='' then raise exception 'customer required'; end if;
  if p_currency not in ('USD','IQD') or coalesce(p_exchange_rate,0)<=0 then
    raise exception 'invalid currency or exchange rate';
  end if;
  perform 1 from public.erp_customers where company_id=p_company_id and id=p_customer_id and not is_deleted;
  if not found then raise exception 'customer not found'; end if;
  v_subtotal:=public.erp_cloud_commercial_items_subtotal(p_company_id,p_items,false);
  if coalesce(p_discount,-1)<0 or p_discount>v_subtotal then raise exception 'invalid discount'; end if;
  insert into public.erp_sales_orders_cloud(
    id,company_id,order_number,customer_id,opportunity_id,status,currency,
    exchange_rate,subtotal,discount,total,notes)
  values(v_order_id,p_company_id,v_number,p_customer_id,v_opportunity,'draft',p_currency,
    p_exchange_rate,v_subtotal,p_discount,v_subtotal-p_discount,p_notes);
  for v_item in select value from jsonb_array_elements(p_items) loop
    insert into public.erp_sales_order_items_cloud(
      company_id,order_id,item_type,item_id,description,quantity,unit_price,line_total)
    values(p_company_id,v_order_id,lower(v_item->>'itemType'),v_item->>'itemId',
      v_item->>'description',(v_item->>'quantity')::int,(v_item->>'unitPrice')::numeric,
      (v_item->>'quantity')::numeric*(v_item->>'unitPrice')::numeric);
  end loop;
  return v_order_id;
exception when unique_violation then
  select id into v_existing from public.erp_sales_orders_cloud
   where company_id=p_company_id and opportunity_id=v_opportunity and not is_deleted
   order by updated_at desc limit 1;
  if v_existing is not null then return v_existing; end if;
  raise;
end $$;

grant execute on function public.erp_sync_opportunity_from_sales_order(uuid,text,uuid,text,text,boolean) to authenticated;
grant execute on function public.erp_create_cloud_sales_order(uuid,text,text,numeric,jsonb,text,numeric,text) to authenticated;

-- Backfill current links.
select public.erp_sync_opportunity_from_sales_order(
  company_id,opportunity_id,id,order_number,status,is_deleted)
from public.erp_sales_orders_cloud
where opportunity_id is not null and btrim(opportunity_id)<>'';

commit;
