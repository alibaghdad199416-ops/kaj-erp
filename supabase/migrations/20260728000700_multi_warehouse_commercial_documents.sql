begin;

-- ---------------------------------------------------------------------------
-- Commercial allocation context and validation.
-- A single delivery/receipt document may distribute its lines across many
-- warehouses while remaining one auditable workflow document.
-- ---------------------------------------------------------------------------
create or replace function public.erp_get_commercial_order_allocation_context(
  p_company_id uuid,
  p_order_id uuid,
  p_module text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_items jsonb:='[]'::jsonb;
  v_warehouses jsonb:='[]'::jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied';
  end if;
  if p_module not in ('sales','purchases') then
    raise exception 'invalid workflow module';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id',w.id,
      'name',coalesce(w.data->>'name',w.data->>'code',w.id),
      'code',w.data->>'code',
      'address',w.data->>'address'
    ) order by coalesce(w.data->>'name',w.data->>'code',w.id)),'[]'::jsonb)
  into v_warehouses
  from public.erp_warehouses w
  where w.company_id=p_company_id and not w.is_deleted
    and public.erp_try_boolean(w.data->>'isActive',true);

  if p_module='sales' then
    perform 1 from public.erp_sales_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted;
    if not found then raise exception 'أمر البيع غير موجود'; end if;

    select coalesce(jsonb_agg(jsonb_build_object(
      'itemType',x.item_type,
      'itemId',x.item_id,
      'description',x.description,
      'quantity',x.quantity,
      'unitPrice',x.unit_price,
      'suggestedWarehouseId',case when x.item_type='car'
        then coalesce(c.data->>'warehouseId',c.data->>'warehouse_id') else null end,
      'warehouseBalances',case when x.item_type='product' then coalesce((
        select jsonb_agg(jsonb_build_object(
          'warehouseId',ws.data->>'warehouseId',
          'quantity',public.erp_try_numeric(ws.data->>'quantity',0),
          'reservedQuantity',public.erp_try_numeric(ws.data->>'reservedQuantity',0),
          'availableQuantity',greatest(
            public.erp_try_numeric(ws.data->>'quantity',0)-
            public.erp_try_numeric(ws.data->>'reservedQuantity',0),0)
        ) order by ws.data->>'warehouseId')
        from public.erp_warehouse_stock ws
        where ws.company_id=p_company_id and not ws.is_deleted
          and ws.data->>'productId'=x.item_id
      ),'[]'::jsonb) else '[]'::jsonb end
    ) order by x.id),'[]'::jsonb)
    into v_items
    from public.erp_sales_order_items_cloud x
    left join public.erp_cars c
      on c.company_id=x.company_id and c.id=x.item_id and not c.is_deleted
    where x.company_id=p_company_id and x.order_id=p_order_id and not x.is_deleted;
  else
    perform 1 from public.erp_purchase_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted;
    if not found then raise exception 'أمر الشراء غير موجود'; end if;

    select coalesce(jsonb_agg(jsonb_build_object(
      'itemType',x.item_type,
      'itemId',x.item_id,
      'description',x.description,
      'quantity',x.quantity,
      'unitCost',x.unit_cost,
      'suggestedWarehouseId',null,
      'warehouseBalances','[]'::jsonb
    ) order by x.id),'[]'::jsonb)
    into v_items
    from public.erp_purchase_order_items_cloud x
    where x.company_id=p_company_id and x.order_id=p_order_id and not x.is_deleted;
  end if;

  return jsonb_build_object(
    'module',p_module,
    'orderId',p_order_id,
    'items',v_items,
    'warehouses',v_warehouses
  );
end;
$$;

create or replace function public.erp_validate_commercial_warehouse_allocations(
  p_company_id uuid,
  p_order_id uuid,
  p_module text,
  p_allocations jsonb,
  p_check_sales_stock boolean default true
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  a record;
  r record;
  g record;
  v_type text;
  v_item_id text;
  v_warehouse_id text;
  v_description text;
  v_quantity numeric;
  v_expected_quantity numeric;
  v_expected_type text;
  v_total numeric;
  v_available numeric;
  v_car_warehouse text;
  v_car_status text;
  v_normalized jsonb:='[]'::jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied';
  end if;
  if p_module not in ('sales','purchases') then
    raise exception 'invalid workflow module';
  end if;
  if coalesce(jsonb_typeof(p_allocations),'null')<>'array'
     or jsonb_array_length(p_allocations)=0 then
    raise exception 'يجب توزيع بنود المستند على مخزن واحد على الأقل';
  end if;

  for a in
    select * from jsonb_to_recordset(p_allocations) as x(
      "itemType" text,
      "itemId" text,
      "description" text,
      "warehouseId" text,
      quantity numeric
    )
  loop
    v_type:=lower(btrim(coalesce(a."itemType",'')));
    v_item_id:=btrim(coalesce(a."itemId",''));
    v_warehouse_id:=btrim(coalesce(a."warehouseId",''));
    v_description:=btrim(coalesce(a."description",''));
    v_quantity:=coalesce(a.quantity,0);
    if v_type not in ('car','product') or v_item_id='' or v_warehouse_id=''
       or v_quantity<=0 or v_quantity<>trunc(v_quantity) then
      raise exception 'بيانات توزيع المخزن غير صحيحة';
    end if;

    perform 1 from public.erp_warehouses w
    where w.company_id=p_company_id and w.id=v_warehouse_id
      and not w.is_deleted and public.erp_try_boolean(w.data->>'isActive',true);
    if not found then raise exception 'المخزن المحدد غير موجود أو غير فعال'; end if;

    if p_module='sales' then
      select x.item_type,x.quantity,x.description
      into v_expected_type,v_expected_quantity,v_description
      from public.erp_sales_order_items_cloud x
      where x.company_id=p_company_id and x.order_id=p_order_id
        and not x.is_deleted and x.item_id=v_item_id;
    else
      select x.item_type,x.quantity,x.description
      into v_expected_type,v_expected_quantity,v_description
      from public.erp_purchase_order_items_cloud x
      where x.company_id=p_company_id and x.order_id=p_order_id
        and not x.is_deleted and x.item_id=v_item_id;
    end if;
    if not found then raise exception 'البند الموزع غير موجود داخل الأمر: %',v_item_id; end if;
    if v_expected_type<>v_type then raise exception 'نوع البند الموزع غير صحيح: %',v_description; end if;

    v_normalized:=v_normalized||jsonb_build_array(jsonb_build_object(
      'itemType',v_type,
      'itemId',v_item_id,
      'description',v_description,
      'warehouseId',v_warehouse_id,
      'quantity',trunc(v_quantity)::int
    ));
  end loop;

  if p_module='sales' then
    for r in select item_type,item_id,description,quantity
      from public.erp_sales_order_items_cloud
      where company_id=p_company_id and order_id=p_order_id and not is_deleted
    loop
      select coalesce(sum(x.quantity),0) into v_total
      from jsonb_to_recordset(v_normalized) as x(
        "itemType" text,"itemId" text,"description" text,
        "warehouseId" text,quantity numeric
      ) where x."itemType"=r.item_type and x."itemId"=r.item_id;
      if v_total<>r.quantity then
        raise exception 'مجموع توزيع البند % يجب أن يساوي %',r.description,r.quantity;
      end if;
      if r.item_type='car' and r.quantity<>1 then
        raise exception 'كمية السيارة في أمر البيع يجب أن تكون واحدة';
      end if;
    end loop;
  else
    for r in select item_type,item_id,description,quantity
      from public.erp_purchase_order_items_cloud
      where company_id=p_company_id and order_id=p_order_id and not is_deleted
    loop
      select coalesce(sum(x.quantity),0) into v_total
      from jsonb_to_recordset(v_normalized) as x(
        "itemType" text,"itemId" text,"description" text,
        "warehouseId" text,quantity numeric
      ) where x."itemType"=r.item_type and x."itemId"=r.item_id;
      if v_total<>r.quantity then
        raise exception 'مجموع توزيع البند % يجب أن يساوي %',r.description,r.quantity;
      end if;
      if r.item_type='car' and r.quantity<>1 then
        raise exception 'كمية السيارة في أمر الشراء يجب أن تكون واحدة';
      end if;
    end loop;
  end if;

  if p_module='sales' then
    for g in
      select x."itemId" as item_id,x."warehouseId" as warehouse_id,sum(x.quantity) as quantity
      from jsonb_to_recordset(v_normalized) as x(
        "itemType" text,"itemId" text,"description" text,
        "warehouseId" text,quantity numeric
      )
      where x."itemType"='product'
      group by x."itemId",x."warehouseId"
    loop
      select coalesce(sum(greatest(
        public.erp_try_numeric(ws.data->>'quantity',0)-
        public.erp_try_numeric(ws.data->>'reservedQuantity',0),0)),0)
      into v_available
      from public.erp_warehouse_stock ws
      where ws.company_id=p_company_id and not ws.is_deleted
        and ws.data->>'productId'=g.item_id
        and ws.data->>'warehouseId'=g.warehouse_id;
      if p_check_sales_stock and v_available<g.quantity then
        raise exception 'الرصيد المتاح للمنتج % في المخزن % غير كافٍ (المتاح: %)',
          g.item_id,g.warehouse_id,v_available;
      end if;
    end loop;

    for g in
      select x."itemId" as item_id,x."warehouseId" as warehouse_id,sum(x.quantity) as quantity,count(*) as rows_count
      from jsonb_to_recordset(v_normalized) as x(
        "itemType" text,"itemId" text,"description" text,
        "warehouseId" text,quantity numeric
      )
      where x."itemType"='car'
      group by x."itemId",x."warehouseId"
    loop
      if g.quantity<>1 or g.rows_count<>1 then raise exception 'لا يمكن تقسيم السيارة على أكثر من مخزن'; end if;
      select coalesce(c.data->>'warehouseId',c.data->>'warehouse_id'),
             lower(btrim(coalesce(c.data->>'status','')))
      into v_car_warehouse,v_car_status
      from public.erp_cars c
      where c.company_id=p_company_id and c.id=g.item_id and not c.is_deleted;
      if not found then raise exception 'السيارة الموزعة غير موجودة'; end if;
      if v_car_warehouse is distinct from g.warehouse_id then
        raise exception 'السيارة % ليست في مخزن التجهيز المحدد',g.item_id;
      end if;
      if v_car_status not in ('available','متوفرة','متوفر','متاحة','selling','pending_sale','قيد البيع') then
        raise exception 'حالة السيارة % لا تسمح بالتجهيز',g.item_id;
      end if;
    end loop;
  else
    for g in
      select x."itemId" as item_id,sum(x.quantity) as quantity,count(*) as rows_count
      from jsonb_to_recordset(v_normalized) as x(
        "itemType" text,"itemId" text,"description" text,
        "warehouseId" text,quantity numeric
      )
      where x."itemType"='car'
      group by x."itemId"
    loop
      if g.quantity<>1 or g.rows_count<>1 then raise exception 'لا يمكن تقسيم السيارة على أكثر من مخزن'; end if;
    end loop;
  end if;

  return v_normalized;
end;
$$;

create or replace function public.erp_create_cloud_sales_delivery_multi(
  p_company_id uuid,
  p_order_id uuid,
  p_allocations jsonb,
  p_notes text default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  v_id uuid:=gen_random_uuid();
  v_number text;
  v_allocations jsonb;
  v_primary_warehouse text;
  v_warehouses jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  perform 1 from public.erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id and status='approved' and not is_deleted for update;
  if not found then raise exception 'أمر بيع مصدق غير موجود'; end if;
  if exists(select 1 from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=p_order_id and module='sales'
      and document_type='delivery' and not is_deleted and status<>'cancelled') then
    raise exception 'يوجد أمر تجهيز فعال لهذا الأمر';
  end if;
  v_allocations:=public.erp_validate_commercial_warehouse_allocations(
    p_company_id,p_order_id,'sales',p_allocations,true);
  v_primary_warehouse:=v_allocations->0->>'warehouseId';
  select coalesce(jsonb_agg(distinct x."warehouseId"),'[]'::jsonb)
  into v_warehouses
  from jsonb_to_recordset(v_allocations) as x(
    "itemType" text,"itemId" text,"description" text,
    "warehouseId" text,quantity numeric
  );
  v_number:='SD-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  insert into public.erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,warehouse_id,payload
  ) values(
    v_id,p_company_id,'sales','delivery',p_order_id,v_number,v_primary_warehouse,
    jsonb_build_object(
      'notes',p_notes,'createdBy',auth.uid(),'allocations',v_allocations,
      'warehouseIds',v_warehouses,'multiWarehouse',jsonb_array_length(v_warehouses)>1
    )
  );
  perform public.erp_commercial_audit(
    p_company_id,'sales',p_order_id,v_id,v_number,'create_delivery',null,'draft',
    'multi-warehouse allocation');
  return v_id;
end;
$$;

create or replace function public.erp_create_cloud_purchase_receipt_multi(
  p_company_id uuid,
  p_order_id uuid,
  p_allocations jsonb,
  p_notes text default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  v_id uuid:=gen_random_uuid();
  v_number text;
  v_allocations jsonb;
  v_primary_warehouse text;
  v_warehouses jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  perform 1 from public.erp_purchase_orders_cloud
  where company_id=p_company_id and id=p_order_id and status='approved' and not is_deleted for update;
  if not found then raise exception 'أمر شراء مصدق غير موجود'; end if;
  if exists(select 1 from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=p_order_id and module='purchases'
      and document_type='receipt' and not is_deleted and status<>'cancelled') then
    raise exception 'يوجد أمر استلام فعال لهذا الأمر';
  end if;
  v_allocations:=public.erp_validate_commercial_warehouse_allocations(
    p_company_id,p_order_id,'purchases',p_allocations,false);
  v_primary_warehouse:=v_allocations->0->>'warehouseId';
  select coalesce(jsonb_agg(distinct x."warehouseId"),'[]'::jsonb)
  into v_warehouses
  from jsonb_to_recordset(v_allocations) as x(
    "itemType" text,"itemId" text,"description" text,
    "warehouseId" text,quantity numeric
  );
  v_number:='PR-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  insert into public.erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,warehouse_id,payload
  ) values(
    v_id,p_company_id,'purchases','receipt',p_order_id,v_number,v_primary_warehouse,
    jsonb_build_object(
      'notes',p_notes,'createdBy',auth.uid(),'allocations',v_allocations,
      'warehouseIds',v_warehouses,'multiWarehouse',jsonb_array_length(v_warehouses)>1
    )
  );
  perform public.erp_commercial_audit(
    p_company_id,'purchases',p_order_id,v_id,v_number,'create_receipt',null,'draft',
    'multi-warehouse allocation');
  return v_id;
end;
$$;

-- Backward-compatible one-warehouse wrappers.
create or replace function public.erp_create_cloud_sales_delivery(
  p_company_id uuid,p_order_id uuid,p_warehouse_id text default null,p_notes text default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_allocations jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'itemType',x.item_type,'itemId',x.item_id,'description',x.description,
    'warehouseId',p_warehouse_id,'quantity',x.quantity
  ) order by x.id),'[]'::jsonb)
  into v_allocations
  from public.erp_sales_order_items_cloud x
  where x.company_id=p_company_id and x.order_id=p_order_id and not x.is_deleted;
  return public.erp_create_cloud_sales_delivery_multi(
    p_company_id,p_order_id,v_allocations,p_notes);
end;
$$;

create or replace function public.erp_create_cloud_purchase_receipt(
  p_company_id uuid,p_order_id uuid,p_warehouse_id text default null,p_notes text default null
) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_allocations jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object(
    'itemType',x.item_type,'itemId',x.item_id,'description',x.description,
    'warehouseId',p_warehouse_id,'quantity',x.quantity
  ) order by x.id),'[]'::jsonb)
  into v_allocations
  from public.erp_purchase_order_items_cloud x
  where x.company_id=p_company_id and x.order_id=p_order_id and not x.is_deleted;
  return public.erp_create_cloud_purchase_receipt_multi(
    p_company_id,p_order_id,v_allocations,p_notes);
end;
$$;

-- The approval/cancellation implementations below consume the normalized
-- allocation array and therefore post every warehouse movement atomically.
create or replace function public.erp_approve_cloud_purchase_receipt(
  p_company_id uuid,p_receipt_id uuid
) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_stock public.erp_warehouse_stock%rowtype;
  v_allocations jsonb;
  a record;
  v_unit_cost numeric;
  v_qty numeric;
  v_avg numeric;
  v_new_avg numeric;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select * into v_doc from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_receipt_id and module='purchases'
    and document_type='receipt' and not is_deleted for update;
  if not found then raise exception 'أمر الاستلام غير موجود'; end if;
  if v_doc.status='cancelled' then raise exception 'أمر الاستلام ملغي'; end if;
  if v_doc.payload ? 'inventoryPostedAt' then return; end if;

  v_allocations:=v_doc.payload->'allocations';
  if coalesce(jsonb_typeof(v_allocations),'null')<>'array' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'itemType',x.item_type,'itemId',x.item_id,'description',x.description,
      'warehouseId',v_doc.warehouse_id,'quantity',x.quantity
    ) order by x.id),'[]'::jsonb)
    into v_allocations
    from public.erp_purchase_order_items_cloud x
    where x.company_id=p_company_id and x.order_id=v_doc.parent_id and not x.is_deleted;
  end if;
  v_allocations:=public.erp_validate_commercial_warehouse_allocations(
    p_company_id,v_doc.parent_id,'purchases',v_allocations,false);

  for a in
    select * from jsonb_to_recordset(v_allocations) as x(
      "itemType" text,"itemId" text,"description" text,
      "warehouseId" text,quantity numeric
    )
  loop
    if a."itemType"='product' then
      select x.unit_cost into v_unit_cost
      from public.erp_purchase_order_items_cloud x
      where x.company_id=p_company_id and x.order_id=v_doc.parent_id
        and not x.is_deleted and x.item_type='product' and x.item_id=a."itemId";
      if not found then raise exception 'بند المنتج غير موجود في أمر الشراء'; end if;
      v_stock:=public.erp_inventory_ensure_stock(
        p_company_id,a."warehouseId",a."itemId");
      v_qty:=public.erp_try_numeric(v_stock.data->>'quantity',0);
      v_avg:=public.erp_try_numeric(v_stock.data->>'averageUnitCost',0);
      v_new_avg:=case when v_qty+a.quantity>0
        then ((v_qty*v_avg)+(a.quantity*v_unit_cost))/(v_qty+a.quantity)
        else v_unit_cost end;
      update public.erp_warehouse_stock
      set data=data||jsonb_build_object(
            'quantity',v_qty+a.quantity,
            'averageUnitCost',round(v_new_avg,4),
            'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=v_stock.id;
      perform public.erp_inventory_insert_movement(
        p_company_id,a."itemId",a."warehouseId",'purchase_in',a.quantity,
        v_unit_cost,'purchase_receipt',v_doc.id::text,v_doc.document_number);
      perform public.erp_inventory_refresh_product(p_company_id,a."itemId");
    else
      select x.unit_cost into v_unit_cost
      from public.erp_purchase_order_items_cloud x
      where x.company_id=p_company_id and x.order_id=v_doc.parent_id
        and not x.is_deleted and x.item_type='car' and x.item_id=a."itemId";
      if not found then raise exception 'بند السيارة غير موجود في أمر الشراء'; end if;
      perform 1 from public.erp_cars c
      where c.company_id=p_company_id and c.id=a."itemId" and not c.is_deleted for update;
      if not found then raise exception 'السيارة % لم تعد موجودة',a."description"; end if;
      update public.erp_cars
      set data=(data-'purchaseOrderId')||jsonb_build_object(
            'status','متوفرة','warehouseId',a."warehouseId",
            'purchasePrice',v_unit_cost,'receivedAt',now(),
            'purchaseReceiptId',v_doc.id::text,
            'sourcePurchaseOrderId',v_doc.parent_id::text,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=a."itemId";
    end if;
  end loop;

  update public.erp_commercial_workflow_documents
  set status='approved',
      payload=payload||jsonb_build_object(
        'allocations',v_allocations,'inventoryPostedAt',now(),
        'inventoryPostedBy',auth.uid()),
      updated_at=now()
  where company_id=p_company_id and id=p_receipt_id;
  perform public.erp_commercial_audit(
    p_company_id,'purchases',v_doc.parent_id,v_doc.id,v_doc.document_number,
    'approve_receipt',v_doc.status,'approved','multi-warehouse allocation');
end;
$$;

create or replace function public.erp_approve_cloud_sales_delivery(
  p_company_id uuid,p_delivery_id uuid
) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_stock public.erp_warehouse_stock%rowtype;
  v_allocations jsonb;
  a record;
  v_available numeric;
  v_cost numeric;
  v_total_cost numeric:=0;
  v_entry_id text;
  v_inventory_account text;
  v_cogs_account text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select * into v_doc from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_delivery_id and module='sales'
    and document_type='delivery' and not is_deleted for update;
  if not found then raise exception 'أمر التجهيز غير موجود'; end if;
  if v_doc.status='cancelled' then raise exception 'أمر التجهيز ملغي'; end if;
  if v_doc.payload ? 'inventoryPostedAt' then return; end if;

  v_allocations:=v_doc.payload->'allocations';
  if coalesce(jsonb_typeof(v_allocations),'null')<>'array' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'itemType',x.item_type,'itemId',x.item_id,'description',x.description,
      'warehouseId',v_doc.warehouse_id,'quantity',x.quantity
    ) order by x.id),'[]'::jsonb)
    into v_allocations
    from public.erp_sales_order_items_cloud x
    where x.company_id=p_company_id and x.order_id=v_doc.parent_id and not x.is_deleted;
  end if;
  v_allocations:=public.erp_validate_commercial_warehouse_allocations(
    p_company_id,v_doc.parent_id,'sales',v_allocations,true);

  for a in
    select * from jsonb_to_recordset(v_allocations) as x(
      "itemType" text,"itemId" text,"description" text,
      "warehouseId" text,quantity numeric
    )
  loop
    if a."itemType"='product' then
      v_stock:=public.erp_inventory_ensure_stock(
        p_company_id,a."warehouseId",a."itemId");
      v_available:=greatest(
        public.erp_try_numeric(v_stock.data->>'quantity',0)-
        public.erp_try_numeric(v_stock.data->>'reservedQuantity',0),0);
      v_cost:=public.erp_try_numeric(v_stock.data->>'averageUnitCost',0);
      if v_available<a.quantity then
        raise exception 'الرصيد في المخزن غير كافٍ للمنتج %',a."description";
      end if;
      update public.erp_warehouse_stock
      set data=data||jsonb_build_object(
            'quantity',public.erp_try_numeric(data->>'quantity',0)-a.quantity,
            'updatedAt',now()),updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=v_stock.id;
      perform public.erp_inventory_insert_movement(
        p_company_id,a."itemId",a."warehouseId",'sale_out',-a.quantity,
        v_cost,'sales_delivery',v_doc.id::text,v_doc.document_number);
      perform public.erp_inventory_refresh_product(p_company_id,a."itemId");
      v_total_cost:=v_total_cost+a.quantity*v_cost;
    else
      perform 1 from public.erp_cars c
      where c.company_id=p_company_id and c.id=a."itemId" and not c.is_deleted
        and coalesce(c.data->>'warehouseId',c.data->>'warehouse_id')=a."warehouseId"
        and lower(btrim(coalesce(c.data->>'status',''))) in
          ('available','متوفرة','متوفر','متاحة','selling','pending_sale','قيد البيع')
      for update;
      if not found then
        raise exception 'السيارة % غير موجودة في مخزن التجهيز أو ليست متاحة',a."description";
      end if;
      select coalesce(
        public.erp_try_numeric(c.data->>'purchasePrice',null),
        public.erp_try_numeric(c.data->>'costPrice',0),0)
      into v_cost
      from public.erp_cars c
      where c.company_id=p_company_id and c.id=a."itemId";
      v_total_cost:=v_total_cost+v_cost;
      update public.erp_cars
      set data=(data-'warehouseId'-'warehouse_id')||jsonb_build_object(
            'status','قيد البيع','salesOrderId',v_doc.parent_id::text,
            'lastWarehouseId',a."warehouseId",'deliveredAt',now(),
            'salesDeliveryId',v_doc.id::text,
            'sourceSalesOrderId',v_doc.parent_id::text,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=a."itemId";
    end if;
  end loop;

  if v_total_cost>0 then
    select account_id into v_inventory_account from public.erp_accounts
    where organization_id=p_company_id and code='1300' and is_active limit 1;
    select account_id into v_cogs_account from public.erp_accounts
    where organization_id=p_company_id and code='5100' and is_active limit 1;
    if v_inventory_account is null or v_cogs_account is null then
      raise exception 'حسابات المخزون أو تكلفة المبيعات غير مهيأة';
    end if;
    v_entry_id:=gen_random_uuid()::text;
    insert into public.erp_journal_entries(company_id,id,data,created_by,updated_by)
    values(p_company_id,v_entry_id,jsonb_build_object(
      'id',v_entry_id,'entryNumber','COGS-'||replace(v_doc.id::text,'-',''),
      'entryDate',now(),'description','تكلفة تجهيز '||v_doc.document_number,
      'currency','USD','referenceType','workflow_delivery_cost',
      'referenceId',v_doc.id::text,'orderId',v_doc.parent_id::text,
      'status','posted','totalDebit',v_total_cost,'totalCredit',v_total_cost,
      'createdAt',now()),auth.uid(),auth.uid());
    insert into public.erp_journal_lines(company_id,id,data,created_by,updated_by) values
    (p_company_id,gen_random_uuid()::text,jsonb_build_object(
      'entryId',v_entry_id,'accountId',v_cogs_account,'debit',v_total_cost,
      'credit',0,'description','تكلفة البضاعة المباعة'),auth.uid(),auth.uid()),
    (p_company_id,gen_random_uuid()::text,jsonb_build_object(
      'entryId',v_entry_id,'accountId',v_inventory_account,'debit',0,
      'credit',v_total_cost,'description','إخراج من المخزون'),auth.uid(),auth.uid());
  end if;

  update public.erp_commercial_workflow_documents
  set status='approved',payload=payload||jsonb_build_object(
        'allocations',v_allocations,'inventoryPostedAt',now(),
        'inventoryPostedBy',auth.uid(),'costJournalEntryId',v_entry_id,
        'totalCost',v_total_cost),updated_at=now()
  where company_id=p_company_id and id=p_delivery_id;
  perform public.erp_commercial_audit(
    p_company_id,'sales',v_doc.parent_id,v_doc.id,v_doc.document_number,
    'approve_delivery',v_doc.status,'approved','multi-warehouse allocation');
end;
$$;

create or replace function public.erp_cancel_cloud_purchase_receipt(
  p_company_id uuid,p_receipt_id uuid
) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_stock public.erp_warehouse_stock%rowtype;
  v_allocations jsonb;
  a record;
  v_qty numeric;
  v_unit_cost numeric;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select * into v_doc from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_receipt_id and module='purchases'
    and document_type='receipt' and not is_deleted for update;
  if not found then raise exception 'أمر الاستلام غير موجود'; end if;
  if v_doc.status='cancelled' then return; end if;
  if exists(select 1 from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=v_doc.parent_id and module='purchases'
      and document_type='invoice' and not is_deleted and status<>'cancelled') then
    raise exception 'لا يمكن إلغاء الاستلام لوجود فاتورة فعالة';
  end if;

  if v_doc.payload ? 'inventoryPostedAt' and not (v_doc.payload ? 'inventoryReversedAt') then
    v_allocations:=v_doc.payload->'allocations';
    if coalesce(jsonb_typeof(v_allocations),'null')<>'array' then
      select coalesce(jsonb_agg(jsonb_build_object(
        'itemType',x.item_type,'itemId',x.item_id,'description',x.description,
        'warehouseId',v_doc.warehouse_id,'quantity',x.quantity
      ) order by x.id),'[]'::jsonb)
      into v_allocations
      from public.erp_purchase_order_items_cloud x
      where x.company_id=p_company_id and x.order_id=v_doc.parent_id and not x.is_deleted;
    end if;
    for a in
      select * from jsonb_to_recordset(v_allocations) as x(
        "itemType" text,"itemId" text,"description" text,
        "warehouseId" text,quantity numeric
      )
    loop
      if a."itemType"='product' then
        select x.unit_cost into v_unit_cost
        from public.erp_purchase_order_items_cloud x
        where x.company_id=p_company_id and x.order_id=v_doc.parent_id
          and not x.is_deleted and x.item_type='product' and x.item_id=a."itemId";
        v_stock:=public.erp_inventory_ensure_stock(
          p_company_id,a."warehouseId",a."itemId");
        v_qty:=public.erp_try_numeric(v_stock.data->>'quantity',0);
        if v_qty<a.quantity then
          raise exception 'لا يمكن عكس الاستلام لأن رصيد المنتج % تم استخدامه',a."description";
        end if;
        update public.erp_warehouse_stock
        set data=data||jsonb_build_object('quantity',v_qty-a.quantity,'updatedAt',now()),
            updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=v_stock.id;
        perform public.erp_inventory_insert_movement(
          p_company_id,a."itemId",a."warehouseId",'purchase_receipt_reversal',
          -a.quantity,v_unit_cost,'purchase_receipt_cancel',v_doc.id::text,
          v_doc.document_number);
        perform public.erp_inventory_refresh_product(p_company_id,a."itemId");
      else
        perform 1 from public.erp_cars c
        where c.company_id=p_company_id and c.id=a."itemId" and not c.is_deleted
          and lower(btrim(coalesce(c.data->>'status',''))) in
            ('available','متوفرة','متوفر','متاحة')
          and coalesce(c.data->>'warehouseId',c.data->>'warehouse_id')=a."warehouseId"
        for update;
        if not found then
          raise exception 'لا يمكن عكس استلام السيارة % بعد تحريكها أو بيعها',a."description";
        end if;
        update public.erp_cars
        set data=(data-'warehouseId'-'warehouse_id')||jsonb_build_object(
              'status','قيد الشراء','purchaseOrderId',v_doc.parent_id::text,
              'updatedAt',now()),updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=a."itemId";
      end if;
    end loop;
  end if;

  update public.erp_commercial_workflow_documents
  set status='cancelled',payload=payload||jsonb_build_object(
      'inventoryReversedAt',now(),'cancelledAt',now()),updated_at=now()
  where company_id=p_company_id and id=p_receipt_id;
  perform public.erp_commercial_audit(
    p_company_id,'purchases',v_doc.parent_id,v_doc.id,v_doc.document_number,
    'cancel_receipt',v_doc.status,'cancelled','multi-warehouse reversal');
end;
$$;

create or replace function public.erp_cancel_cloud_sales_delivery(
  p_company_id uuid,p_delivery_id uuid
) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_stock public.erp_warehouse_stock%rowtype;
  v_allocations jsonb;
  a record;
  v_qty numeric;
  v_cost numeric;
  v_journal text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select * into v_doc from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_delivery_id and module='sales'
    and document_type='delivery' and not is_deleted for update;
  if not found then raise exception 'أمر التجهيز غير موجود'; end if;
  if v_doc.status='cancelled' then return; end if;
  if exists(select 1 from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=v_doc.parent_id and module='sales'
      and document_type='invoice' and not is_deleted and status<>'cancelled') then
    raise exception 'لا يمكن إلغاء التجهيز لوجود فاتورة فعالة';
  end if;

  if v_doc.payload ? 'inventoryPostedAt' and not (v_doc.payload ? 'inventoryReversedAt') then
    v_allocations:=v_doc.payload->'allocations';
    if coalesce(jsonb_typeof(v_allocations),'null')<>'array' then
      select coalesce(jsonb_agg(jsonb_build_object(
        'itemType',x.item_type,'itemId',x.item_id,'description',x.description,
        'warehouseId',v_doc.warehouse_id,'quantity',x.quantity
      ) order by x.id),'[]'::jsonb)
      into v_allocations
      from public.erp_sales_order_items_cloud x
      where x.company_id=p_company_id and x.order_id=v_doc.parent_id and not x.is_deleted;
    end if;
    for a in
      select * from jsonb_to_recordset(v_allocations) as x(
        "itemType" text,"itemId" text,"description" text,
        "warehouseId" text,quantity numeric
      )
    loop
      if a."itemType"='product' then
        v_stock:=public.erp_inventory_ensure_stock(
          p_company_id,a."warehouseId",a."itemId");
        v_qty:=public.erp_try_numeric(v_stock.data->>'quantity',0);
        v_cost:=public.erp_try_numeric(v_stock.data->>'averageUnitCost',0);
        update public.erp_warehouse_stock
        set data=data||jsonb_build_object('quantity',v_qty+a.quantity,'updatedAt',now()),
            updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=v_stock.id;
        perform public.erp_inventory_insert_movement(
          p_company_id,a."itemId",a."warehouseId",'sales_delivery_reversal',
          a.quantity,v_cost,'sales_delivery_cancel',v_doc.id::text,
          v_doc.document_number);
        perform public.erp_inventory_refresh_product(p_company_id,a."itemId");
      else
        perform 1 from public.erp_cars c
        where c.company_id=p_company_id and c.id=a."itemId" and not c.is_deleted
          and lower(btrim(coalesce(c.data->>'status',''))) in
            ('selling','pending_sale','قيد البيع')
          and c.data->>'salesDeliveryId'=v_doc.id::text
        for update;
        if not found then
          raise exception 'لا يمكن عكس تجهيز السيارة % لأن حالتها تغيرت أو تم تصديق فاتورتها',a."description";
        end if;
        update public.erp_cars
        set data=(data-'salesDeliveryId'-'deliveredAt'-'lastWarehouseId')
              ||jsonb_build_object(
                'status','قيد البيع','warehouseId',a."warehouseId",
                'salesOrderId',v_doc.parent_id::text,'updatedAt',now()),
            updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=a."itemId";
      end if;
    end loop;
    v_journal:=nullif(v_doc.payload->>'costJournalEntryId','');
    if v_journal is not null then
      update public.erp_journal_lines
      set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and not is_deleted and data->>'entryId'=v_journal;
      update public.erp_journal_entries
      set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=v_journal and not is_deleted;
    end if;
  end if;

  update public.erp_commercial_workflow_documents
  set status='cancelled',payload=payload||jsonb_build_object(
      'inventoryReversedAt',now(),'cancelledAt',now()),updated_at=now()
  where company_id=p_company_id and id=p_delivery_id;
  perform public.erp_commercial_audit(
    p_company_id,'sales',v_doc.parent_id,v_doc.id,v_doc.document_number,
    'cancel_delivery',v_doc.status,'cancelled','multi-warehouse reversal');
end;
$$;

-- Preserve the exact warehouse allocation when an order is edited and its
-- linked documents are reversed/rebuilt.
create or replace function public.erp_prepare_commercial_order_change(
  p_company_id uuid,p_order_id uuid,p_module text,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_order_status text;
  v_logistics public.erp_commercial_workflow_documents%rowtype;
  v_invoice public.erp_commercial_workflow_documents%rowtype;
  v_payments jsonb:='[]'::jsonb;
  v_result jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if p_module='sales' then
    select status into v_order_status from public.erp_sales_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  elsif p_module='purchases' then
    select status into v_order_status from public.erp_purchase_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  else
    raise exception 'invalid workflow module';
  end if;
  if not found then raise exception 'الأمر غير موجود'; end if;

  if (select count(*) from public.erp_commercial_workflow_documents
      where company_id=p_company_id and parent_id=p_order_id and module=p_module
        and document_type=case when p_module='sales' then 'delivery' else 'receipt' end
        and not is_deleted and status<>'cancelled')>1 then
    raise exception 'يوجد أكثر من مستند مخزني فعال مرتبط بالأمر؛ يجب معالجة التكرار قبل التعديل أو الحذف';
  end if;
  if (select count(*) from public.erp_commercial_workflow_documents
      where company_id=p_company_id and parent_id=p_order_id and module=p_module
        and document_type='invoice' and not is_deleted and status<>'cancelled')>1 then
    raise exception 'يوجد أكثر من فاتورة فعالة مرتبطة بالأمر؛ يجب معالجة التكرار قبل التعديل أو الحذف';
  end if;

  select * into v_logistics from public.erp_commercial_workflow_documents
  where company_id=p_company_id and parent_id=p_order_id and module=p_module
    and document_type=case when p_module='sales' then 'delivery' else 'receipt' end
    and not is_deleted and status<>'cancelled'
  order by created_at desc limit 1 for update;
  select * into v_invoice from public.erp_commercial_workflow_documents
  where company_id=p_company_id and parent_id=p_order_id and module=p_module
    and document_type='invoice' and not is_deleted and status<>'cancelled'
  order by created_at desc limit 1 for update;

  v_result:=jsonb_build_object(
    'orderStatus',v_order_status,
    'logistics',case when v_logistics.id is null then null else jsonb_build_object(
      'id',v_logistics.id,'status',v_logistics.status,
      'warehouseId',v_logistics.warehouse_id,
      'allocations',v_logistics.payload->'allocations',
      'warehouseIds',v_logistics.payload->'warehouseIds',
      'multiWarehouse',coalesce(v_logistics.payload->'multiWarehouse','false'::jsonb),
      'notes',v_logistics.payload->>'notes') end,
    'invoice',case when v_invoice.id is null then null else jsonb_build_object(
      'id',v_invoice.id,'status',v_invoice.status) end,
    'payments','[]'::jsonb
  );

  if v_invoice.id is not null then
    v_payments:=public.erp_reverse_cloud_workflow_invoice_payments(
      p_company_id,v_invoice.id,coalesce(p_reason,'تعديل الأمر المرتبط'));
    if p_module='sales' then
      perform public.erp_cancel_cloud_sales_workflow_invoice(p_company_id,v_invoice.id,p_reason);
    else
      perform public.erp_cancel_cloud_purchase_workflow_invoice(p_company_id,v_invoice.id,p_reason);
    end if;
    v_result:=jsonb_set(v_result,'{payments}',v_payments,true);
  end if;
  if v_logistics.id is not null then
    if p_module='sales' then
      perform public.erp_cancel_cloud_sales_delivery(p_company_id,v_logistics.id);
    else
      perform public.erp_cancel_cloud_purchase_receipt(p_company_id,v_logistics.id);
    end if;
  end if;
  if v_order_status='approved' then
    if p_module='sales' then
      perform public.erp_reopen_cloud_sales_order(p_company_id,p_order_id);
    else
      perform public.erp_reopen_cloud_purchase_order(p_company_id,p_order_id);
    end if;
  elsif v_order_status<>'draft' then
    raise exception 'حالة الأمر لا تسمح بالتعديل أو الحذف';
  end if;
  return v_result;
end;
$$;

create or replace function public.erp_restore_commercial_order_links(
  p_company_id uuid,p_order_id uuid,p_module text,p_snapshot jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_logistics jsonb:=p_snapshot->'logistics';
  v_invoice jsonb:=p_snapshot->'invoice';
  v_payments jsonb:=coalesce(p_snapshot->'payments','[]'::jsonb);
  v_allocations jsonb;
  v_normalized_payments jsonb:='[]'::jsonb;
  v_payment jsonb;
  v_mode text;
  v_logistics_id uuid;
  v_invoice_id uuid;
  v_order_status text:=p_snapshot->>'orderStatus';
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if p_module not in ('sales','purchases') then raise exception 'invalid workflow module'; end if;

  if v_order_status='approved' or v_logistics is not null or v_invoice is not null then
    if p_module='sales' then
      perform public.erp_approve_cloud_sales_order(p_company_id,p_order_id);
    else
      perform public.erp_approve_cloud_purchase_order(p_company_id,p_order_id);
    end if;
  end if;

  if v_logistics is not null then
    v_allocations:=v_logistics->'allocations';
    if coalesce(jsonb_typeof(v_allocations),'null')='array'
       and jsonb_array_length(v_allocations)>0 then
      if p_module='sales' then
        v_logistics_id:=public.erp_create_cloud_sales_delivery_multi(
          p_company_id,p_order_id,v_allocations,v_logistics->>'notes');
        if v_logistics->>'status'='approved' then
          perform public.erp_approve_cloud_sales_delivery(p_company_id,v_logistics_id);
        end if;
      else
        v_logistics_id:=public.erp_create_cloud_purchase_receipt_multi(
          p_company_id,p_order_id,v_allocations,v_logistics->>'notes');
        if v_logistics->>'status'='approved' then
          perform public.erp_approve_cloud_purchase_receipt(p_company_id,v_logistics_id);
        end if;
      end if;
    else
      if nullif(v_logistics->>'warehouseId','') is null then
        raise exception 'المستند المخزني السابق لا يحتوي على مخزن صالح';
      end if;
      if p_module='sales' then
        v_logistics_id:=public.erp_create_cloud_sales_delivery(
          p_company_id,p_order_id,v_logistics->>'warehouseId',v_logistics->>'notes');
        if v_logistics->>'status'='approved' then
          perform public.erp_approve_cloud_sales_delivery(p_company_id,v_logistics_id);
        end if;
      else
        v_logistics_id:=public.erp_create_cloud_purchase_receipt(
          p_company_id,p_order_id,v_logistics->>'warehouseId',v_logistics->>'notes');
        if v_logistics->>'status'='approved' then
          perform public.erp_approve_cloud_purchase_receipt(p_company_id,v_logistics_id);
        end if;
      end if;
    end if;
  end if;

  if v_invoice is not null then
    if p_module='sales' then
      v_invoice_id:=public.erp_create_cloud_sales_workflow_invoice(p_company_id,p_order_id);
      if v_invoice->>'status'='approved' then
        perform public.erp_approve_cloud_sales_workflow_invoice(p_company_id,v_invoice_id);
      end if;
    else
      v_invoice_id:=public.erp_create_cloud_purchase_workflow_invoice(p_company_id,p_order_id);
      if v_invoice->>'status'='approved' then
        perform public.erp_approve_cloud_purchase_workflow_invoice(p_company_id,v_invoice_id);
      end if;
    end if;

    if jsonb_array_length(v_payments)>0 and v_invoice->>'status'<>'approved' then
      raise exception 'لا يمكن إعادة الدفعات إلى فاتورة غير مصدقة';
    end if;
    for v_payment in select value from jsonb_array_elements(v_payments) loop
      v_mode:=lower(btrim(coalesce(v_payment->>'settlementMode','partial')));
      v_mode:=case
        when v_mode in ('full','fullwithexchangedifference') then 'full'
        when v_mode in ('settlement','full_fx')
             and nullif(v_payment->>'settlementAccountId','') is not null then 'settlement'
        when v_mode in ('full_fx','fullwithexchangedifference') then 'full'
        else 'partial'
      end;
      v_normalized_payments:=v_normalized_payments||jsonb_build_array(
        (v_payment
          - 'paymentId' - 'paymentKey' - 'journalEntryId' - 'cashTransactionId'
          - 'previousRemainingAmount' - 'remainingAmount' - 'createdAt' - 'createdBy')
        ||jsonb_build_object('settlementMode',v_mode)
      );
    end loop;
    if jsonb_array_length(v_normalized_payments)>0 then
      perform public.erp_apply_cloud_workflow_invoice_payment_batch(
        p_company_id,v_invoice_id,p_module,v_normalized_payments);
    end if;
  end if;

  return jsonb_build_object(
    'orderId',p_order_id,'logisticsId',v_logistics_id,'invoiceId',v_invoice_id);
end;
$$;

grant execute on function public.erp_get_commercial_order_allocation_context(uuid,uuid,text) to authenticated;
grant execute on function public.erp_validate_commercial_warehouse_allocations(uuid,uuid,text,jsonb,boolean) to authenticated;
grant execute on function public.erp_create_cloud_sales_delivery_multi(uuid,uuid,jsonb,text) to authenticated;
grant execute on function public.erp_create_cloud_purchase_receipt_multi(uuid,uuid,jsonb,text) to authenticated;

commit;
