-- R24 sales invoice closure: validate invoice against the approved logistics snapshot, not post-delivery current stock.
begin;

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
      if p_check_sales_stock then
        if v_car_warehouse is distinct from g.warehouse_id then
          raise exception 'السيارة % ليست في مخزن التجهيز المحدد',g.item_id;
        end if;
        if v_car_status not in ('available','متوفرة','متوفر','متاحة','selling','pending_sale','قيد البيع') then
          raise exception 'حالة السيارة % لا تسمح بالتجهيز',g.item_id;
        end if;
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

create or replace function public.erp_v736_assert_invoice_logistics(
  p_company_id uuid,
  p_order_id uuid,
  p_module text,
  p_logistics_id uuid,
  p_invoice_allocations jsonb
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_active jsonb;
  v_invoice jsonb;
  v_logistics jsonb;
begin
  v_active:=public.erp_v736_active_logistics(p_company_id,p_order_id,p_module);
  if nullif(v_active->>'id','')::uuid is distinct from p_logistics_id then
    raise exception 'invoice_logistics_reference_mismatch';
  end if;

  -- The logistics document was already stock/vehicle validated when it was created/approved.
  -- Invoice approval must compare the immutable approved allocations, not current stock/state
  -- after delivery/receipt has already moved the inventory.
  v_invoice:=public.erp_validate_commercial_warehouse_allocations(
    p_company_id,p_order_id,p_module,p_invoice_allocations,false);
  v_logistics:=public.erp_validate_commercial_warehouse_allocations(
    p_company_id,p_order_id,p_module,v_active->'allocations',false);

  if exists(
    with invoice_rows as (
      select lower(x."itemType") item_type,x."itemId" item_id,x."warehouseId" warehouse_id,
             sum(x.quantity) quantity
      from jsonb_to_recordset(v_invoice) as x(
        "itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
      group by 1,2,3
    ), logistics_rows as (
      select lower(x."itemType") item_type,x."itemId" item_id,x."warehouseId" warehouse_id,
             sum(x.quantity) quantity
      from jsonb_to_recordset(v_logistics) as x(
        "itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
      group by 1,2,3
    ), differences as (
      (select * from invoice_rows except select * from logistics_rows)
      union all
      (select * from logistics_rows except select * from invoice_rows)
    )
    select 1 from differences
  ) then
    raise exception 'invoice_quantities_must_equal_approved_logistics';
  end if;

  return v_active||jsonb_build_object('invoiceAllocations',v_invoice,'r24ImmutableLogisticsValidation',true);
end;
$$;

notify pgrst,'reload schema';
commit;
