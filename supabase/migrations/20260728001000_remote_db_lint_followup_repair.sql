begin;

-- ---------------------------------------------------------------------------
-- Follow-up repair for the real linked-database lint run.
--
-- First: multi-warehouse allocation quantities are normalized as JSON numeric
--    values. PostgreSQL therefore resolves the movement call with a numeric
--    fifth argument, while the original stock movement function accepts an
--    integer. Keep the original contract and add a strict numeric adapter that
--    rejects fractional/out-of-range quantities before delegating.
-- Second: product rename propagation updates draft commercial item timestamps.
--    The original item tables did not have created_at/updated_at columns.
-- ---------------------------------------------------------------------------

alter table public.erp_sales_order_items_cloud
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

alter table public.erp_purchase_order_items_cloud
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

-- Normalize pre-existing installations where a column may have been added
-- manually without defaults or a NOT NULL constraint.
update public.erp_sales_order_items_cloud
set created_at=coalesce(created_at,now()),
    updated_at=coalesce(updated_at,created_at,now())
where created_at is null or updated_at is null;

update public.erp_purchase_order_items_cloud
set created_at=coalesce(created_at,now()),
    updated_at=coalesce(updated_at,created_at,now())
where created_at is null or updated_at is null;

alter table public.erp_sales_order_items_cloud
  alter column created_at set default now(),
  alter column created_at set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

alter table public.erp_purchase_order_items_cloud
  alter column created_at set default now(),
  alter column created_at set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

create or replace function public.erp_touch_commercial_item_updated_at()
returns trigger
language plpgsql
security invoker
set search_path=public
as $$
begin
  if tg_op='INSERT' then
    new.created_at:=coalesce(new.created_at,now());
  else
    new.created_at:=coalesce(new.created_at,old.created_at,now());
  end if;
  new.updated_at:=now();
  return new;
end;
$$;

drop trigger if exists erp_touch_commercial_item_updated_at
  on public.erp_sales_order_items_cloud;
create trigger erp_touch_commercial_item_updated_at
before insert or update on public.erp_sales_order_items_cloud
for each row execute function public.erp_touch_commercial_item_updated_at();

drop trigger if exists erp_touch_commercial_item_updated_at
  on public.erp_purchase_order_items_cloud;
create trigger erp_touch_commercial_item_updated_at
before insert or update on public.erp_purchase_order_items_cloud
for each row execute function public.erp_touch_commercial_item_updated_at();

create or replace function public.erp_inventory_insert_movement(
  p_company_id uuid,
  p_product_id text,
  p_warehouse_id text,
  p_type text,
  p_quantity numeric,
  p_unit_cost numeric,
  p_reference_type text,
  p_reference_id text,
  p_notes text
) returns text
language plpgsql
security definer
set search_path=public
as $$
begin
  if p_quantity is null
     or p_quantity<>trunc(p_quantity)
     or p_quantity>2147483647
     or p_quantity<(-2147483648) then
    raise exception 'inventory_movement_quantity_must_be_integer'
      using errcode='22003';
  end if;

  return public.erp_inventory_insert_movement(
    p_company_id,
    p_product_id,
    p_warehouse_id,
    p_type,
    p_quantity::integer,
    p_unit_cost,
    p_reference_type,
    p_reference_id,
    p_notes
  );
end;
$$;

revoke all on function public.erp_inventory_insert_movement(
  uuid,text,text,text,numeric,numeric,text,text,text
) from public,anon;
grant execute on function public.erp_inventory_insert_movement(
  uuid,text,text,text,numeric,numeric,text,text,text
) to authenticated,service_role;

commit;
