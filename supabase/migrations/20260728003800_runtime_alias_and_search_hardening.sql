-- Quality Line ERP 17.20.1
-- Runtime compatibility repair for normalized vehicle/product JSON fields.
-- This migration is additive: it does not edit any previously applied migration
-- and does not remove operational data.

begin;

-- The one-time archive from the accepted-module cleanup must never be exposed
-- to browser roles. Operators can export it with a privileged PostgreSQL role.
revoke all on schema qualityline_retired from public, anon, authenticated;
grant usage on schema qualityline_retired to postgres, service_role;

do $$
declare
  v_table record;
begin
  for v_table in
    select schemaname, tablename
    from pg_tables
    where schemaname = 'qualityline_retired'
  loop
    execute format(
      'revoke all on table %I.%I from public, anon, authenticated',
      v_table.schemaname,
      v_table.tablename
    );
    execute format(
      'grant select on table %I.%I to postgres, service_role',
      v_table.schemaname,
      v_table.tablename
    );
  end loop;
end $$;

-- Pick the alias that actually changed. This lets old SQL functions update a
-- camelCase field while newer Flutter writes snake_case (or both) without one
-- alias becoming stale.
create or replace function public.erp_pick_changed_json_alias(
  p_new jsonb,
  p_old jsonb,
  p_keys text[]
) returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  v_key text;
begin
  if p_old is not null then
    foreach v_key in array p_keys loop
      if (p_new -> v_key) is distinct from (p_old -> v_key) then
        return p_new -> v_key;
      end if;
    end loop;
  end if;

  foreach v_key in array p_keys loop
    if p_new ? v_key then
      return p_new -> v_key;
    end if;
  end loop;

  return 'null'::jsonb;
end;
$$;

revoke all on function public.erp_pick_changed_json_alias(jsonb,jsonb,text[])
  from public, anon, authenticated;
grant execute on function public.erp_pick_changed_json_alias(jsonb,jsonb,text[])
  to postgres, service_role;

create or replace function public.erp_sync_car_json_aliases()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old jsonb := case when tg_op = 'INSERT' then null else old.data end;
  v_vehicle_type jsonb;
  v_brand jsonb;
  v_chassis jsonb;
  v_plate jsonb;
  v_car_number jsonb;
  v_purchase_price jsonb;
  v_sale_price jsonb;
  v_image_path jsonb;
  v_maintenance_cost jsonb;
  v_warehouse_id jsonb;
  v_supplier_id jsonb;
  v_supplier_name jsonb;
  v_purchase_date jsonb;
  v_updated_at jsonb;
begin
  new.data := coalesce(new.data, '{}'::jsonb);

  v_vehicle_type := public.erp_pick_changed_json_alias(
    new.data, v_old, array['vehicle_type','vehicleType','type']
  );
  v_brand := public.erp_pick_changed_json_alias(
    new.data, v_old, array['brand','make']
  );
  v_chassis := public.erp_pick_changed_json_alias(
    new.data, v_old, array['chassis','chassis_number','chassisNumber','vin']
  );
  v_plate := public.erp_pick_changed_json_alias(
    new.data, v_old, array['plate_number','plateNumber','plate']
  );
  v_car_number := public.erp_pick_changed_json_alias(
    new.data, v_old, array['car_number','carNumber']
  );
  v_purchase_price := public.erp_pick_changed_json_alias(
    new.data, v_old, array['purchase_price','purchasePrice','costPrice']
  );
  v_sale_price := public.erp_pick_changed_json_alias(
    new.data, v_old, array['sale_price','salePrice']
  );
  v_image_path := public.erp_pick_changed_json_alias(
    new.data, v_old, array['image_path','imagePath','image']
  );
  v_maintenance_cost := public.erp_pick_changed_json_alias(
    new.data, v_old, array['maintenance_cost','maintenanceCost']
  );
  v_warehouse_id := public.erp_pick_changed_json_alias(
    new.data, v_old, array['warehouse_id','warehouseId']
  );
  v_supplier_id := public.erp_pick_changed_json_alias(
    new.data, v_old, array['supplier_id','supplierId']
  );
  v_supplier_name := public.erp_pick_changed_json_alias(
    new.data, v_old, array['supplier_name','supplierName']
  );
  v_purchase_date := public.erp_pick_changed_json_alias(
    new.data, v_old, array['purchase_date','purchaseDate']
  );
  v_updated_at := to_jsonb(now()::text);

  new.data := new.data || jsonb_build_object(
    'vehicle_type', v_vehicle_type,
    'vehicleType', v_vehicle_type,
    'brand', v_brand,
    'make', v_brand,
    'chassis', v_chassis,
    'vin', v_chassis,
    'plate_number', v_plate,
    'plateNumber', v_plate,
    'plate', v_plate,
    'car_number', v_car_number,
    'carNumber', v_car_number,
    'purchase_price', v_purchase_price,
    'purchasePrice', v_purchase_price,
    'costPrice', v_purchase_price,
    'sale_price', v_sale_price,
    'salePrice', v_sale_price,
    'image_path', v_image_path,
    'imagePath', v_image_path,
    'image', v_image_path,
    'maintenance_cost', v_maintenance_cost,
    'maintenanceCost', v_maintenance_cost,
    'warehouse_id', v_warehouse_id,
    'warehouseId', v_warehouse_id,
    'supplier_id', v_supplier_id,
    'supplierId', v_supplier_id,
    'supplier_name', v_supplier_name,
    'supplierName', v_supplier_name,
    'purchase_date', v_purchase_date,
    'purchaseDate', v_purchase_date,
    'updated_at', v_updated_at,
    'updatedAt', v_updated_at,
    'schema_version', 3
  );

  return new;
end;
$$;

revoke all on function public.erp_sync_car_json_aliases()
  from public, anon, authenticated;
grant execute on function public.erp_sync_car_json_aliases()
  to postgres, service_role;

drop trigger if exists zz_erp_cars_alias_sync on public.erp_cars;
create trigger zz_erp_cars_alias_sync
before insert or update of data on public.erp_cars
for each row execute function public.erp_sync_car_json_aliases();

-- Backfill aliases for existing active and soft-deleted records. The trigger
-- preserves the logical deletion state and only normalizes the JSON payload.
update public.erp_cars
set data = data
where data is not null
  and (
    data->'plate_number' is distinct from data->'plateNumber'
    or data->'chassis' is distinct from data->'vin'
    or data->'purchase_price' is distinct from data->'purchasePrice'
    or data->'sale_price' is distinct from data->'salePrice'
    or data->'warehouse_id' is distinct from data->'warehouseId'
    or data->'maintenance_cost' is distinct from data->'maintenanceCost'
    or data->'car_number' is distinct from data->'carNumber'
  );

-- Uniqueness applies only to active vehicles and supports both historical and
-- normalized JSON key names. A soft-deleted vehicle therefore never reserves
-- its old chassis or plate.
drop index if exists public.erp_cars_company_chassis_key;
drop index if exists public.erp_cars_company_plate_key;

create unique index erp_cars_company_chassis_key
  on public.erp_cars(
    company_id,
    lower(btrim(coalesce(
      data->>'chassis', data->>'chassis_number', data->>'chassisNumber', data->>'vin'
    )))
  )
  where not is_deleted
    and coalesce(btrim(coalesce(
      data->>'chassis', data->>'chassis_number', data->>'chassisNumber', data->>'vin'
    )), '') <> '';

create unique index erp_cars_company_plate_key
  on public.erp_cars(
    company_id,
    lower(btrim(coalesce(
      data->>'plate_number', data->>'plateNumber', data->>'plate'
    )))
  )
  where not is_deleted
    and coalesce(btrim(coalesce(
      data->>'plate_number', data->>'plateNumber', data->>'plate'
    )), '') <> '';

-- Product master identifiers also ignore soft-deleted products. These indexes
-- are the database-level guard; Flutter validation is not treated as proof of
-- uniqueness.
drop index if exists public.erp_inventory_code_uq;
create unique index erp_inventory_code_uq
  on public.erp_inventory(company_id, lower(btrim(data->>'code')))
  where not is_deleted and coalesce(btrim(data->>'code'), '') <> '';

create unique index if not exists erp_inventory_sku_uq
  on public.erp_inventory(company_id, lower(btrim(data->>'sku')))
  where not is_deleted and coalesce(btrim(data->>'sku'), '') <> '';

create unique index if not exists erp_inventory_barcode_uq
  on public.erp_inventory(company_id, btrim(data->>'barcode'))
  where not is_deleted and coalesce(btrim(data->>'barcode'), '') <> '';

create unique index if not exists erp_inventory_serial_uq
  on public.erp_inventory(
    company_id,
    lower(btrim(coalesce(data->>'serialNumber', data->>'serial_number')))
  )
  where not is_deleted
    and coalesce(btrim(coalesce(data->>'serialNumber', data->>'serial_number')), '') <> '';

-- Canonical cross-module search. All routes point to accepted Flutter modules,
-- soft-deleted rows are excluded, and vehicle/product aliases are handled.
create or replace function public.erp_cloud_global_search(
  p_company_id uuid,
  p_query text,
  p_limit integer default 50
) returns setof jsonb
language sql
security definer
set search_path = public
as $$
  with q as (
    select '%' || btrim(coalesce(p_query,'')) || '%' pattern
  ), rows as (
    select c.id::text id, 'السيارات'::text type,
      concat_ws(' ',coalesce(c.data->>'brand',c.data->>'make'),c.data->>'model',c.data->>'year') title,
      concat_ws(' • ',
        coalesce(c.data->>'chassis',c.data->>'chassis_number',c.data->>'chassisNumber',c.data->>'vin'),
        coalesce(c.data->>'plate_number',c.data->>'plateNumber',c.data->>'plate'),
        coalesce(c.data->>'car_number',c.data->>'carNumber')) subtitle,
      '/inventory'::text route, 'cars.view'::text permission, 'car'::text icon,
      c.data->>'status' status,
      public.erp_try_numeric(coalesce(c.data->>'sale_price',c.data->>'salePrice'),0) amount,
      c.created_at occurred_at, 1 rank
    from public.erp_cars c cross join q
    where c.company_id=p_company_id and not c.is_deleted and (
      coalesce(c.data->>'brand',c.data->>'make','') ilike q.pattern or
      coalesce(c.data->>'model','') ilike q.pattern or
      coalesce(c.data->>'chassis',c.data->>'chassis_number',c.data->>'chassisNumber',c.data->>'vin','') ilike q.pattern or
      coalesce(c.data->>'plate_number',c.data->>'plateNumber',c.data->>'plate','') ilike q.pattern or
      coalesce(c.data->>'car_number',c.data->>'carNumber','') ilike q.pattern)
    union all
    select i.id, 'المنتجات',
      coalesce(i.data->>'nameAr',i.data->>'name_ar',i.data->>'name',i.data->>'nameEn',i.data->>'name_en',i.data->>'code',''),
      concat_ws(' • ',i.data->>'code',i.data->>'sku',i.data->>'barcode',coalesce(i.data->>'serialNumber',i.data->>'serial_number')),
      '/products','inventory.view','inventory',
      case when public.erp_try_boolean(coalesce(i.data->>'isActive',i.data->>'is_active'),true) then 'active' else 'inactive' end,
      public.erp_try_numeric(coalesce(i.data->>'salePrice',i.data->>'sale_price'),0),i.created_at,2
    from public.erp_inventory i cross join q
    where i.company_id=p_company_id and not i.is_deleted and (
      coalesce(i.data->>'nameAr',i.data->>'name_ar',i.data->>'name',i.data->>'nameEn',i.data->>'name_en','') ilike q.pattern or
      coalesce(i.data->>'description','') ilike q.pattern or
      coalesce(i.data->>'code','') ilike q.pattern or
      coalesce(i.data->>'sku','') ilike q.pattern or
      coalesce(i.data->>'barcode','') ilike q.pattern or
      coalesce(i.data->>'serialNumber',i.data->>'serial_number','') ilike q.pattern)
    union all
    select w.id, 'المخازن', coalesce(w.data->>'name',''),
      concat_ws(' • ',w.data->>'code',w.data->>'address'),
      '/inventory','inventory.view','inventory',
      case when public.erp_try_boolean(w.data->>'isActive',true) then 'active' else 'inactive' end,
      null::numeric,w.created_at,3
    from public.erp_warehouses w cross join q
    where w.company_id=p_company_id and not w.is_deleted and (
      coalesce(w.data->>'name','') ilike q.pattern or
      coalesce(w.data->>'code','') ilike q.pattern or
      coalesce(w.data->>'address','') ilike q.pattern)
    union all
    select x.id, 'العملاء', coalesce(x.data->>'name',''),coalesce(x.data->>'phone',''),
      '/business-partners','customers.view','customer',
      case when public.erp_try_boolean(x.data->>'isActive',true) then 'active' else 'inactive' end,
      public.erp_try_numeric(x.data->>'balance',0),x.created_at,4
    from public.erp_customers x cross join q
    where x.company_id=p_company_id and not x.is_deleted and (
      coalesce(x.data->>'name','') ilike q.pattern or coalesce(x.data->>'phone','') ilike q.pattern or
      coalesce(x.data->>'email','') ilike q.pattern or coalesce(x.data->>'taxNumber','') ilike q.pattern)
    union all
    select x.id, 'المجهزون', coalesce(x.data->>'name',''),coalesce(x.data->>'phone',''),
      '/business-partners','suppliers.view','supplier',
      case when public.erp_try_boolean(x.data->>'isActive',true) then 'active' else 'inactive' end,
      public.erp_try_numeric(x.data->>'balance',0),x.created_at,5
    from public.erp_suppliers x cross join q
    where x.company_id=p_company_id and not x.is_deleted and (
      coalesce(x.data->>'name','') ilike q.pattern or coalesce(x.data->>'phone','') ilike q.pattern or
      coalesce(x.data->>'email','') ilike q.pattern or coalesce(x.data->>'taxNumber','') ilike q.pattern)
    union all
    select m.id::text, 'الصيانة', m.order_number,concat_ws(' • ',m.customer_name,m.car_name),
      '/maintenance','maintenance.view','maintenance',m.status,m.total_cost,m.created_at,6
    from public.erp_maintenance_orders m cross join q
    where m.company_id=p_company_id and not m.is_deleted and (
      m.order_number ilike q.pattern or coalesce(m.customer_name,'') ilike q.pattern or
      coalesce(m.car_name,'') ilike q.pattern or coalesce(m.invoice_number,'') ilike q.pattern)
    union all
    select sc.id::text, 'خدمة العملاء', sc.case_number,concat_ws(' • ',sc.title,sc.description),
      '/customer-service','customer_service.view','service',sc.status,null::numeric,sc.created_at,7
    from public.erp_service_cases sc cross join q
    where sc.company_id=p_company_id and not sc.is_deleted and (
      sc.case_number ilike q.pattern or sc.title ilike q.pattern or coalesce(sc.description,'') ilike q.pattern)
    union all
    select o.id::text, 'أوامر البيع', o.order_number,coalesce(c.data->>'name',''),
      '/sales','sales.view','sale',o.status,o.total,o.created_at,8
    from public.erp_sales_orders_cloud o cross join q
    left join public.erp_customers c on c.company_id=o.company_id and c.id=o.customer_id and not c.is_deleted
    where o.company_id=p_company_id and not o.is_deleted and (
      o.order_number ilike q.pattern or coalesce(c.data->>'name','') ilike q.pattern)
    union all
    select o.id::text, 'أوامر الشراء', o.order_number,coalesce(sp.data->>'name',''),
      '/purchases','purchases.view','purchase',o.status,o.total,o.created_at,9
    from public.erp_purchase_orders_cloud o cross join q
    left join public.erp_suppliers sp on sp.company_id=o.company_id and sp.id=o.supplier_id and not sp.is_deleted
    where o.company_id=p_company_id and not o.is_deleted and (
      o.order_number ilike q.pattern or coalesce(sp.data->>'name','') ilike q.pattern)
    union all
    select d.id::text,
      case when d.document_type='delivery' then 'التجهيز' when d.document_type='receipt' then 'الاستلام' else 'الفواتير' end,
      d.document_number,coalesce(d.payload->>'partnerName',''),
      case when d.module='sales' then '/sales' else '/purchases' end,
      case when d.module='sales' then 'sales.view' else 'purchases.view' end,
      case when d.document_type='delivery' then 'delivery' when d.document_type='receipt' then 'receipt' else 'invoice' end,
      d.status,public.erp_try_numeric(d.payload->>'totalAmount',0),d.created_at,10
    from public.erp_commercial_workflow_documents d cross join q
    where d.company_id=p_company_id and not d.is_deleted and (
      d.document_number ilike q.pattern or coalesce(d.payload->>'invoiceNumber','') ilike q.pattern)
    union all
    select j.id::text, 'القيود المحاسبية',coalesce(j.data->>'entryNumber',j.data->>'number',j.id::text),
      coalesce(j.data->>'description',''),'/accounting','accounting.view','journal',
      coalesce(j.data->>'status','posted'),public.erp_try_numeric(j.data->>'totalDebit',0),j.created_at,11
    from public.erp_journal_entries j cross join q
    where j.company_id=p_company_id and not j.is_deleted and (
      coalesce(j.data->>'entryNumber',j.data->>'number','') ilike q.pattern or
      coalesce(j.data->>'description','') ilike q.pattern or coalesce(j.data->>'reference','') ilike q.pattern)
    union all
    select ins.id, 'الدفعات',coalesce(ins.data->>'invoiceNumber',ins.data->>'installmentNumber',ins.id),
      coalesce(ins.data->>'customerName',''),'/accounting','installments.view','payment',
      coalesce(ins.data->>'status','pending'),public.erp_try_numeric(ins.data->>'remainingAmount',0),ins.created_at,12
    from public.erp_installments ins cross join q
    where ins.company_id=p_company_id and not ins.is_deleted and (
      coalesce(ins.data->>'invoiceNumber','') ilike q.pattern or
      coalesce(ins.data->>'installmentNumber','') ilike q.pattern or
      coalesce(ins.data->>'customerName','') ilike q.pattern)
  )
  select jsonb_build_object(
    'id',id,'type',type,'title',title,'subtitle',subtitle,'route',route,
    'permission',permission,'icon',icon,'status',status,'amount',amount,
    'date',occurred_at::text)
  from rows
  where public.erp_is_company_member(p_company_id)
    and length(btrim(coalesce(p_query,''))) >= 2
  order by rank, occurred_at desc
  limit greatest(1,least(coalesce(p_limit,50),200));
$$;

revoke all on function public.erp_cloud_global_search(uuid,text,integer)
  from public, anon;
grant execute on function public.erp_cloud_global_search(uuid,text,integer)
  to authenticated;

comment on function public.erp_cloud_global_search(uuid,text,integer) is
  'Accepted-module tenant search with soft-delete filtering and vehicle/product JSON alias compatibility.';

commit;
