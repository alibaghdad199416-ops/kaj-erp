-- R23: canonical vehicle lifecycle + exact Phase26 PostgREST contract.
--
-- Runtime vehicle eligibility is derived from current normalized workflow
-- documents/tombstones, not from legacy erp_cars.data.status labels.

create or replace function public.erp_r23_vehicle_operational_state(
  p_company_id uuid,
  p_car_id text,
  p_fallback_warehouse text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_exists boolean:=false;
  v_purchase_order_id uuid;
  v_purchase_receipt_id uuid;
  v_purchase_warehouse text;
  v_sales_order_id uuid;
  v_sales_delivery_id uuid;
  v_sales_invoice_id uuid;
  v_transfer_warehouse text;
  v_status_value text;
  v_status_label text;
  v_warehouse text;
  v_source text;
begin
  select true into v_exists
  from public.erp_cars c
  where c.company_id=p_company_id
    and c.id=p_car_id
    and not c.is_deleted
    and not public.erp_r15_pending_delete_exists(p_company_id,'erp_cars',c.id)
  limit 1;

  if not coalesce(v_exists,false) then
    return jsonb_build_object(
      'carId',p_car_id,'carExists',false,'deletedOrTombstoned',true,
      'statusValue','deleted','status','محذوفة',
      'eligibleForPurchase',false,'eligibleForSale',false,
      'canonicalVehicleStateVersion',23
    );
  end if;

  select coalesce(t.data->>'toWarehouseId',t.data->>'to_warehouse_id')
    into v_transfer_warehouse
  from public.erp_car_warehouse_transfers t
  where t.company_id=p_company_id
    and not t.is_deleted
    and coalesce(t.data->>'carId',t.data->>'car_id')=p_car_id
  order by public.erp_try_timestamptz(
      coalesce(t.data->>'transferDate',t.data->>'transfer_date'),t.created_at
    ) desc,t.created_at desc,t.id desc
  limit 1;

  select d.id,o.id,coalesce(
      nullif(a.warehouse_id,''),nullif(d.warehouse_id,''),
      nullif(v_transfer_warehouse,''),nullif(p_fallback_warehouse,'')
    )
    into v_purchase_receipt_id,v_purchase_order_id,v_purchase_warehouse
  from public.erp_purchase_order_items_cloud i
  join public.erp_purchase_orders_cloud o
    on o.company_id=i.company_id and o.id=i.order_id
   and not o.is_deleted
   and lower(coalesce(o.status,'')) not in ('cancelled','canceled','reversed','deleted','void')
  join public.erp_commercial_workflow_documents d
    on d.company_id=i.company_id and d.parent_id=i.order_id
   and d.module='purchases' and d.document_type='receipt'
   and not d.is_deleted
   and lower(coalesce(d.status,'')) in ('approved','received','completed')
  left join lateral (
    select coalesce(x->>'warehouseId',x->>'warehouse_id') warehouse_id
    from jsonb_array_elements(
      case when jsonb_typeof(d.payload->'allocations')='array'
        then d.payload->'allocations' else '[]'::jsonb end
    ) x
    where coalesce(x->>'itemId',x->>'item_id')=p_car_id
    limit 1
  ) a on true
  where i.company_id=p_company_id
    and i.item_type='car' and i.item_id=p_car_id and not i.is_deleted
  order by coalesce(d.effective_at,d.updated_at,d.created_at) desc,d.id desc
  limit 1;

  if v_purchase_order_id is null then
    select o.id into v_purchase_order_id
    from public.erp_purchase_order_items_cloud i
    join public.erp_purchase_orders_cloud o
      on o.company_id=i.company_id and o.id=i.order_id
    where i.company_id=p_company_id
      and i.item_type='car' and i.item_id=p_car_id and not i.is_deleted
      and not o.is_deleted
      and lower(coalesce(o.status,'')) not in ('cancelled','canceled','reversed','deleted','void')
    order by o.updated_at desc,o.created_at desc,o.id desc
    limit 1;
  end if;

  select d.id,o.id into v_sales_invoice_id,v_sales_order_id
  from public.erp_sales_order_items_cloud i
  join public.erp_sales_orders_cloud o
    on o.company_id=i.company_id and o.id=i.order_id
   and not o.is_deleted
   and lower(coalesce(o.status,'')) not in ('cancelled','canceled','reversed','deleted','void')
  join public.erp_commercial_workflow_documents d
    on d.company_id=i.company_id and d.parent_id=i.order_id
   and d.module='sales' and d.document_type='invoice'
   and not d.is_deleted
   and lower(coalesce(d.status,'')) in ('approved','paid','completed')
  where i.company_id=p_company_id
    and i.item_type='car' and i.item_id=p_car_id and not i.is_deleted
  order by coalesce(d.effective_at,d.updated_at,d.created_at) desc,d.id desc
  limit 1;

  if v_sales_invoice_id is null then
    select d.id,o.id into v_sales_delivery_id,v_sales_order_id
    from public.erp_sales_order_items_cloud i
    join public.erp_sales_orders_cloud o
      on o.company_id=i.company_id and o.id=i.order_id
     and not o.is_deleted
     and lower(coalesce(o.status,'')) not in ('cancelled','canceled','reversed','deleted','void')
    join public.erp_commercial_workflow_documents d
      on d.company_id=i.company_id and d.parent_id=i.order_id
     and d.module='sales' and d.document_type='delivery'
     and not d.is_deleted
     and lower(coalesce(d.status,'')) in ('approved','delivered','completed')
    where i.company_id=p_company_id
      and i.item_type='car' and i.item_id=p_car_id and not i.is_deleted
    order by coalesce(d.effective_at,d.updated_at,d.created_at) desc,d.id desc
    limit 1;
  end if;

  if v_sales_order_id is null then
    select o.id into v_sales_order_id
    from public.erp_sales_order_items_cloud i
    join public.erp_sales_orders_cloud o
      on o.company_id=i.company_id and o.id=i.order_id
    where i.company_id=p_company_id
      and i.item_type='car' and i.item_id=p_car_id and not i.is_deleted
      and not o.is_deleted
      and lower(coalesce(o.status,'')) not in ('cancelled','canceled','reversed','deleted','void')
    order by o.updated_at desc,o.created_at desc,o.id desc
    limit 1;
  end if;

  if v_sales_invoice_id is not null then
    v_status_value:='sold'; v_status_label:='مباعة'; v_warehouse:=null; v_source:='approved_sales_invoice';
  elsif v_sales_delivery_id is not null or v_sales_order_id is not null then
    v_status_value:='pending_sale'; v_status_label:='قيد البيع';
    v_warehouse:=case when v_sales_delivery_id is null
      then coalesce(nullif(v_transfer_warehouse,''),nullif(v_purchase_warehouse,''),nullif(p_fallback_warehouse,''))
      else null end;
    v_source:=case when v_sales_delivery_id is not null then 'approved_sales_delivery' else 'active_sales_order' end;
  elsif v_purchase_receipt_id is not null then
    v_status_value:='available'; v_status_label:='متوفرة';
    v_warehouse:=coalesce(nullif(v_transfer_warehouse,''),nullif(v_purchase_warehouse,''),nullif(p_fallback_warehouse,''));
    v_source:='approved_purchase_receipt';
  elsif v_purchase_order_id is not null then
    v_status_value:='pending_purchase'; v_status_label:='قيد الشراء'; v_warehouse:=null; v_source:='active_purchase_order';
  elsif nullif(v_transfer_warehouse,'') is not null then
    v_status_value:='available'; v_status_label:='متوفرة'; v_warehouse:=v_transfer_warehouse; v_source:='active_warehouse_transfer';
  elsif nullif(p_fallback_warehouse,'') is not null then
    v_status_value:='available'; v_status_label:='متوفرة'; v_warehouse:=p_fallback_warehouse; v_source:='trusted_workflow_fallback';
  else
    v_status_value:='known'; v_status_label:='معرفة'; v_warehouse:=null; v_source:='master_definition';
  end if;

  return jsonb_build_object(
    'carId',p_car_id,'carExists',true,'deletedOrTombstoned',false,
    'statusValue',v_status_value,'status',v_status_label,'warehouseId',v_warehouse,
    'purchaseOrderId',v_purchase_order_id,'purchaseReceiptId',v_purchase_receipt_id,
    'salesOrderId',v_sales_order_id,'salesDeliveryId',v_sales_delivery_id,'salesInvoiceId',v_sales_invoice_id,
    'authoritativeSource',v_source,
    'eligibleForPurchase',v_status_value='known','eligibleForSale',v_status_value='available',
    'legacyStatusIgnored',true,'canonicalVehicleStateVersion',23
  );
end;
$$;

create or replace function public.erp_r23_refresh_vehicle_state(
  p_company_id uuid,p_car_id text,p_fallback_warehouse text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_state jsonb; v_now timestamptz:=clock_timestamp();
begin
  v_state:=public.erp_r23_vehicle_operational_state(p_company_id,p_car_id,p_fallback_warehouse);
  if coalesce((v_state->>'carExists')::boolean,false) is not true then return v_state; end if;
  update public.erp_cars c
  set data=(c.data
      - 'status' - 'statusValue' - 'status_value'
      - 'warehouseId' - 'warehouse_id'
      - 'purchaseOrderId' - 'purchase_order_id'
      - 'purchaseReceiptId' - 'purchase_receipt_id'
      - 'salesOrderId' - 'sales_order_id'
      - 'salesDeliveryId' - 'sales_delivery_id'
      - 'salesInvoiceId' - 'sales_invoice_id')
    || jsonb_strip_nulls(jsonb_build_object(
      'status',v_state->>'status','statusValue',v_state->>'statusValue','status_value',v_state->>'statusValue',
      'warehouseId',nullif(v_state->>'warehouseId',''),'warehouse_id',nullif(v_state->>'warehouseId',''),
      'purchaseOrderId',nullif(v_state->>'purchaseOrderId',''),'purchase_order_id',nullif(v_state->>'purchaseOrderId',''),
      'purchaseReceiptId',nullif(v_state->>'purchaseReceiptId',''),'purchase_receipt_id',nullif(v_state->>'purchaseReceiptId',''),
      'salesOrderId',nullif(v_state->>'salesOrderId',''),'sales_order_id',nullif(v_state->>'salesOrderId',''),
      'salesDeliveryId',nullif(v_state->>'salesDeliveryId',''),'sales_delivery_id',nullif(v_state->>'salesDeliveryId',''),
      'salesInvoiceId',nullif(v_state->>'salesInvoiceId',''),'sales_invoice_id',nullif(v_state->>'salesInvoiceId',''),
      'canonicalVehicleStateVersion',23,'canonicalVehicleStateSource',v_state->>'authoritativeSource',
      'legacyStatusIgnored',true,'operationalStateRebuiltAt',v_now,'updatedAt',v_now
    )),updated_at=v_now,updated_by=auth.uid()
  where c.company_id=p_company_id and c.id=p_car_id and not c.is_deleted
    and not public.erp_r15_pending_delete_exists(p_company_id,'erp_cars',c.id);
  return v_state||jsonb_build_object('statePersisted',true,'refreshedAt',v_now);
end;
$$;

create or replace function public.erp_v732_refresh_car_state(
  p_company_id uuid,p_car_id text,p_fallback_warehouse text default null
) returns jsonb
language sql security definer set search_path=public
as $$ select public.erp_r23_refresh_vehicle_state($1,$2,$3) $$;

create or replace function public.erp_cloud_commercial_items_subtotal(
  p_company_id uuid,p_items jsonb,p_purchase boolean
) returns numeric
language plpgsql security definer set search_path=public
as $$
declare
  v_item jsonb; v_type text; v_id text; v_description text;
  v_qty numeric; v_unit numeric; v_state jsonb; v_subtotal numeric:=0;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if coalesce(jsonb_typeof(p_items),'null')<>'array' or jsonb_array_length(p_items)=0 then raise exception 'يجب إضافة بند واحد على الأقل'; end if;
  if exists(select 1 from jsonb_array_elements(p_items) x group by lower(coalesce(x->>'itemType','')),coalesce(x->>'itemId','') having count(*)>1) then raise exception 'لا يمكن تكرار البند نفسه داخل الأمر'; end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_type:=lower(btrim(coalesce(v_item->>'itemType','')));
    v_id:=btrim(coalesce(v_item->>'itemId',''));
    v_description:=btrim(coalesce(v_item->>'description',''));
    v_qty:=public.erp_try_numeric(v_item->>'quantity',0);
    v_unit:=public.erp_try_numeric(v_item->>(case when p_purchase then 'unitCost' else 'unitPrice' end),-1);
    if v_type not in ('car','product') or v_id='' or v_description='' or v_qty<=0 or v_qty<>trunc(v_qty) or v_unit<0 or (v_type='car' and v_qty<>1) then raise exception 'بيانات بند الأمر غير صحيحة: %',v_description; end if;
    if v_type='car' then
      v_state:=public.erp_r23_vehicle_operational_state(p_company_id,v_id,null);
      if coalesce((v_state->>'carExists')::boolean,false) is not true then raise exception 'السيارة المعرفة غير موجودة أو محذوفة: %',v_description using errcode='23503'; end if;
      if p_purchase and coalesce((v_state->>'eligibleForPurchase')::boolean,false) is not true then
        raise exception 'حالة السيارة المرجعية لا تسمح بإضافتها إلى أمر شراء: % (الحالة: %)',v_description,v_state->>'statusValue' using errcode='P0001';
      end if;
      if not p_purchase and coalesce((v_state->>'eligibleForSale')::boolean,false) is not true then
        raise exception 'السيارة غير متاحة للبيع وفق الحالة المرجعية: % (الحالة: %)',v_description,v_state->>'statusValue' using errcode='P0001';
      end if;
    else
      perform 1 from public.erp_inventory i
      where i.company_id=p_company_id and i.id=v_id and not i.is_deleted
        and not public.erp_r15_pending_delete_exists(p_company_id,'erp_inventory',i.id)
        and public.erp_try_boolean(i.data->>'isActive',true);
      if not found then raise exception 'المنتج غير موجود أو غير فعال: %',v_description; end if;
    end if;
    v_subtotal:=v_subtotal+v_qty*v_unit;
  end loop;
  return round(v_subtotal,2);
end;
$$;

create or replace function public.erp_cloud_purchase_order_catalog(p_company_id uuid)
returns setof jsonb
language sql security definer set search_path=public
as $$
  select jsonb_build_object(
    'itemType','car','id',c.id,
    'description',concat_ws(' ',coalesce(c.data->>'brand',c.data->>'make'),c.data->>'model',c.data->>'year'),
    'baseCost',coalesce(public.erp_try_numeric(c.data->>'purchasePrice',null),public.erp_try_numeric(c.data->>'costPrice',null),public.erp_try_numeric(c.data->>'unitCost',0)),
    'imagePath',coalesce(c.data->>'imagePath',c.data->>'image'),
    'details',c.data||jsonb_build_object('id',c.id,'canonicalStatusValue',s.state->>'statusValue','canonicalVehicleStateVersion',23)
  )
  from public.erp_cars c
  cross join lateral (select public.erp_r23_vehicle_operational_state(p_company_id,c.id,null) state) s
  where c.company_id=p_company_id and not c.is_deleted
    and not public.erp_r15_pending_delete_exists(p_company_id,'erp_cars',c.id)
    and public.erp_is_company_member(p_company_id)
    and coalesce((s.state->>'eligibleForPurchase')::boolean,false)
  union all
  select jsonb_build_object(
    'itemType','product','id',i.id,'description',coalesce(i.data->>'name',i.data->>'code',i.id),
    'baseCost',coalesce(public.erp_try_numeric(i.data->>'unitCost',null),public.erp_try_numeric(i.data->>'costPrice',null),public.erp_try_numeric(i.data->>'purchasePrice',0)),
    'imagePath',coalesce(i.data->>'imagePath',i.data->>'image'),'details',i.data||jsonb_build_object('id',i.id)
  )
  from public.erp_inventory i
  where i.company_id=p_company_id and not i.is_deleted
    and not public.erp_r15_pending_delete_exists(p_company_id,'erp_inventory',i.id)
    and public.erp_try_boolean(i.data->>'isActive',true)
    and public.erp_is_company_member(p_company_id);
$$;

-- Keep exactly one PostgREST-visible overload. No defaults/overload ambiguity.
do $$
declare v_sig regprocedure;
begin
  for v_sig in
    select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='erp_r22_phase26_cloud_command'
  loop execute format('drop function %s',v_sig); end loop;
end $$;

create function public.erp_r22_phase26_cloud_command(p_area text,p_action text,p_payload jsonb)
returns jsonb
language sql security definer set search_path=public
as $$ select public.erp_r14_phase26_cloud_command($1,$2,coalesce($3,'{}'::jsonb)) $$;

grant usage on schema public to authenticated,service_role;
revoke all on function public.erp_r22_phase26_cloud_command(text,text,jsonb) from public,anon;
grant execute on function public.erp_r22_phase26_cloud_command(text,text,jsonb) to authenticated,service_role;
grant execute on function public.erp_r23_vehicle_operational_state(uuid,text,text) to authenticated,service_role;
revoke all on function public.erp_r23_refresh_vehicle_state(uuid,text,text) from public,anon,authenticated;
grant execute on function public.erp_r23_refresh_vehicle_state(uuid,text,text) to service_role;
grant execute on function public.erp_v732_refresh_car_state(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_cloud_purchase_order_catalog(uuid) to authenticated,service_role;

-- Persist display state only for active, non-tombstoned cars.
do $$
declare r record;
begin
  for r in select c.company_id,c.id from public.erp_cars c
           where not c.is_deleted and not public.erp_r15_pending_delete_exists(c.company_id,'erp_cars',c.id)
  loop perform public.erp_r23_refresh_vehicle_state(r.company_id,r.id,null); end loop;
end $$;

notify pgrst,'reload schema';
