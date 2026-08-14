begin;

-- R59 permits successive, quantity-bound physical documents for an approved
-- order. Approved logistics are authoritative; cancelled documents contribute
-- nothing and at most one draft may be open for an order at a time.
create or replace function public.erp_r59_commercial_fulfilled_quantity(
  p_company_id uuid,p_order_id uuid,p_module text,p_item_type text,p_item_id text
) returns numeric language sql stable security definer set search_path=public as $$
  select coalesce(sum(x.quantity),0)
  from public.erp_commercial_workflow_documents d
  cross join lateral jsonb_to_recordset(coalesce(d.payload->'allocations','[]'::jsonb))
    as x("itemType" text,"itemId" text,"warehouseId" text,quantity numeric)
  where d.company_id=p_company_id and d.parent_id=p_order_id and d.module=p_module
    and d.document_type=case when p_module='sales' then 'delivery' else 'receipt' end
    and d.status='approved' and not d.is_deleted
    and x."itemType"=p_item_type and x."itemId"=p_item_id
$$;

create or replace function public.erp_get_commercial_order_allocation_context(
  p_company_id uuid,p_order_id uuid,p_module text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_items jsonb:='[]'; v_warehouses jsonb:='[]';
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if p_module not in ('sales','purchases') then raise exception 'invalid workflow module'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',w.id,'name',coalesce(w.data->>'name',w.data->>'code',w.id),
    'code',w.data->>'code','address',w.data->>'address') order by coalesce(w.data->>'name',w.data->>'code',w.id)),'[]')
  into v_warehouses from public.erp_warehouses w where w.company_id=p_company_id and not w.is_deleted
    and public.erp_try_boolean(w.data->>'isActive',true);
  if p_module='sales' then
    if not exists(select 1 from public.erp_sales_orders_cloud where company_id=p_company_id and id=p_order_id and not is_deleted)
      then raise exception 'sales_order_not_found'; end if;
    select coalesce(jsonb_agg(jsonb_build_object(
      'itemType',x.item_type,'itemId',x.item_id,'description',x.description,
      'orderedQuantity',x.quantity,'fulfilledQuantity',f.fulfilled,'remainingQuantity',x.quantity-f.fulfilled,
      'quantity',x.quantity-f.fulfilled,'unitPrice',x.unit_price,
      'suggestedWarehouseId',case when x.item_type='car' then coalesce(c.data->>'warehouseId',c.data->>'warehouse_id') end,
      'warehouseBalances',case when x.item_type='product' then coalesce((select jsonb_agg(jsonb_build_object(
        'warehouseId',ws.data->>'warehouseId','quantity',public.erp_try_numeric(ws.data->>'quantity',0),
        'reservedQuantity',public.erp_try_numeric(ws.data->>'reservedQuantity',0),'availableQuantity',greatest(
          public.erp_try_numeric(ws.data->>'quantity',0)-public.erp_try_numeric(ws.data->>'reservedQuantity',0),0))
        order by ws.data->>'warehouseId') from public.erp_warehouse_stock ws where ws.company_id=p_company_id
          and not ws.is_deleted and ws.data->>'productId'=x.item_id),'[]') else '[]' end) order by x.id),'[]')
    into v_items from public.erp_sales_order_items_cloud x
    cross join lateral (select public.erp_r59_commercial_fulfilled_quantity(p_company_id,p_order_id,p_module,x.item_type,x.item_id) fulfilled) f
    left join public.erp_cars c on c.company_id=x.company_id and c.id=x.item_id and not c.is_deleted
    where x.company_id=p_company_id and x.order_id=p_order_id and not x.is_deleted and f.fulfilled<x.quantity;
  else
    if not exists(select 1 from public.erp_purchase_orders_cloud where company_id=p_company_id and id=p_order_id and not is_deleted)
      then raise exception 'purchase_order_not_found'; end if;
    select coalesce(jsonb_agg(jsonb_build_object(
      'itemType',x.item_type,'itemId',x.item_id,'description',x.description,
      'orderedQuantity',x.quantity,'fulfilledQuantity',f.fulfilled,'remainingQuantity',x.quantity-f.fulfilled,
      'quantity',x.quantity-f.fulfilled,'unitCost',x.unit_cost,'suggestedWarehouseId',null,'warehouseBalances','[]'::jsonb)
      order by x.id),'[]') into v_items from public.erp_purchase_order_items_cloud x
    cross join lateral (select public.erp_r59_commercial_fulfilled_quantity(p_company_id,p_order_id,p_module,x.item_type,x.item_id) fulfilled) f
    where x.company_id=p_company_id and x.order_id=p_order_id and not x.is_deleted and f.fulfilled<x.quantity;
  end if;
  return jsonb_build_object('module',p_module,'orderId',p_order_id,'items',v_items,'warehouses',v_warehouses);
end $$;

create or replace function public.erp_validate_commercial_warehouse_allocations(
  p_company_id uuid,p_order_id uuid,p_module text,p_allocations jsonb,p_check_sales_stock boolean default true
) returns jsonb language plpgsql security definer set search_path=public as $$
declare a record; v_ordered numeric; v_fulfilled numeric; v_batch numeric; v_available numeric;
  v_expected_type text; v_description text; v_car_warehouse text; v_car_status text; v_normalized jsonb:='[]';
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  if p_module not in ('sales','purchases') then raise exception 'invalid workflow module'; end if;
  if jsonb_typeof(coalesce(p_allocations,'null'))<>'array' or jsonb_array_length(p_allocations)=0
    then raise exception 'warehouse_allocations_required'; end if;
  for a in select * from jsonb_to_recordset(p_allocations) as x(
    "itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
  loop
    a."itemType":=lower(btrim(coalesce(a."itemType",''))); a."itemId":=btrim(coalesce(a."itemId",''));
    a."warehouseId":=btrim(coalesce(a."warehouseId",''));
    if a."itemType" not in ('car','product') or a."itemId"='' or a."warehouseId"=''
      or coalesce(a.quantity,0)<=0 or a.quantity<>trunc(a.quantity) then raise exception 'invalid_warehouse_allocation'; end if;
    if not exists(select 1 from public.erp_warehouses w where w.company_id=p_company_id and w.id=a."warehouseId"
      and not w.is_deleted and public.erp_try_boolean(w.data->>'isActive',true)) then raise exception 'warehouse_not_found_or_inactive'; end if;
    if p_module='sales' then select item_type,quantity,description into v_expected_type,v_ordered,v_description
      from public.erp_sales_order_items_cloud where company_id=p_company_id and order_id=p_order_id and not is_deleted and item_id=a."itemId";
    else select item_type,quantity,description into v_expected_type,v_ordered,v_description
      from public.erp_purchase_order_items_cloud where company_id=p_company_id and order_id=p_order_id and not is_deleted and item_id=a."itemId"; end if;
    if not found or v_expected_type<>a."itemType" then raise exception 'commercial_order_item_mismatch:%',a."itemId"; end if;
    v_normalized:=v_normalized||jsonb_build_array(jsonb_build_object('itemType',a."itemType",'itemId',a."itemId",
      'description',v_description,'warehouseId',a."warehouseId",'quantity',trunc(a.quantity)::int));
  end loop;
  for a in select x."itemType",x."itemId",sum(x.quantity) quantity from jsonb_to_recordset(v_normalized)
    as x("itemType" text,"itemId" text,"warehouseId" text,quantity numeric) group by 1,2
  loop
    if p_module='sales' then select quantity into v_ordered from public.erp_sales_order_items_cloud
      where company_id=p_company_id and order_id=p_order_id and not is_deleted and item_type=a."itemType" and item_id=a."itemId";
    else select quantity into v_ordered from public.erp_purchase_order_items_cloud
      where company_id=p_company_id and order_id=p_order_id and not is_deleted and item_type=a."itemType" and item_id=a."itemId"; end if;
    v_fulfilled:=public.erp_r59_commercial_fulfilled_quantity(p_company_id,p_order_id,p_module,a."itemType",a."itemId");
    if v_fulfilled+a.quantity>v_ordered then raise exception 'commercial_over_fulfillment:%',a."itemId"; end if;
    if a."itemType"='car' and (a.quantity<>1 or v_ordered<>1 or v_fulfilled<>0) then raise exception 'car_allocation_must_be_unique'; end if;
  end loop;
  if p_module='sales' then
    for a in select x."itemType",x."itemId",x."warehouseId",sum(x.quantity) quantity from jsonb_to_recordset(v_normalized)
      as x("itemType" text,"itemId" text,"warehouseId" text,quantity numeric) group by 1,2,3
    loop
      if a."itemType"='product' then select coalesce(sum(greatest(public.erp_try_numeric(data->>'quantity',0)-
        public.erp_try_numeric(data->>'reservedQuantity',0),0)),0) into v_available from public.erp_warehouse_stock
        where company_id=p_company_id and not is_deleted and data->>'productId'=a."itemId" and data->>'warehouseId'=a."warehouseId";
        if p_check_sales_stock and v_available<a.quantity then raise exception 'insufficient_warehouse_stock:%',a."itemId"; end if;
      else select coalesce(data->>'warehouseId',data->>'warehouse_id'),lower(btrim(coalesce(data->>'status','')))
        into v_car_warehouse,v_car_status from public.erp_cars where company_id=p_company_id and id=a."itemId" and not is_deleted;
        if not found or v_car_warehouse is distinct from a."warehouseId" then raise exception 'car_warehouse_mismatch'; end if;
        if v_car_status not in ('available','selling','pending_sale','متوفرة','متوفر','متاح') then raise exception 'car_not_available'; end if;
      end if;
    end loop;
  end if;
  return v_normalized;
end $$;

create or replace function public.erp_create_cloud_sales_delivery_multi(p_company_id uuid,p_order_id uuid,p_allocations jsonb,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid(); v_number text; v_allocations jsonb; v_primary text; v_warehouses jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  perform 1 from public.erp_sales_orders_cloud where company_id=p_company_id and id=p_order_id and status='approved' and not is_deleted for update;
  if not found then raise exception 'approved_sales_order_required'; end if;
  if exists(select 1 from public.erp_commercial_workflow_documents where company_id=p_company_id and parent_id=p_order_id
    and module='sales' and document_type='delivery' and status='draft' and not is_deleted) then raise exception 'active_delivery_draft_exists'; end if;
  v_allocations:=public.erp_validate_commercial_warehouse_allocations(p_company_id,p_order_id,'sales',p_allocations,true);
  v_primary:=v_allocations->0->>'warehouseId'; select jsonb_agg(distinct x."warehouseId") into v_warehouses
    from jsonb_to_recordset(v_allocations) x("warehouseId" text);
  v_number:='SD-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  insert into public.erp_commercial_workflow_documents(id,company_id,module,document_type,parent_id,document_number,warehouse_id,payload)
    values(v_id,p_company_id,'sales','delivery',p_order_id,v_number,v_primary,jsonb_build_object('notes',p_notes,'createdBy',auth.uid(),
      'allocations',v_allocations,'warehouseIds',v_warehouses,'multiWarehouse',jsonb_array_length(v_warehouses)>1));
  perform public.erp_commercial_audit(p_company_id,'sales',p_order_id,v_id,v_number,'create_delivery',null,'draft','partial multi-warehouse allocation'); return v_id;
end $$;

create or replace function public.erp_create_cloud_purchase_receipt_multi(p_company_id uuid,p_order_id uuid,p_allocations jsonb,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid(); v_number text; v_allocations jsonb; v_primary text; v_warehouses jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  perform 1 from public.erp_purchase_orders_cloud where company_id=p_company_id and id=p_order_id and status='approved' and not is_deleted for update;
  if not found then raise exception 'approved_purchase_order_required'; end if;
  if exists(select 1 from public.erp_commercial_workflow_documents where company_id=p_company_id and parent_id=p_order_id
    and module='purchases' and document_type='receipt' and status='draft' and not is_deleted) then raise exception 'active_receipt_draft_exists'; end if;
  v_allocations:=public.erp_validate_commercial_warehouse_allocations(p_company_id,p_order_id,'purchases',p_allocations,false);
  v_primary:=v_allocations->0->>'warehouseId'; select jsonb_agg(distinct x."warehouseId") into v_warehouses
    from jsonb_to_recordset(v_allocations) x("warehouseId" text);
  v_number:='PR-'||to_char(clock_timestamp(),'YYYYMMDDHH24MISSMS');
  insert into public.erp_commercial_workflow_documents(id,company_id,module,document_type,parent_id,document_number,warehouse_id,payload)
    values(v_id,p_company_id,'purchases','receipt',p_order_id,v_number,v_primary,jsonb_build_object('notes',p_notes,'createdBy',auth.uid(),
      'allocations',v_allocations,'warehouseIds',v_warehouses,'multiWarehouse',jsonb_array_length(v_warehouses)>1));
  perform public.erp_commercial_audit(p_company_id,'purchases',p_order_id,v_id,v_number,'create_receipt',null,'draft','partial multi-warehouse allocation'); return v_id;
end $$;

revoke all on function public.erp_r59_commercial_fulfilled_quantity(uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.erp_r59_commercial_fulfilled_quantity(uuid,uuid,text,text,text) to service_role;
revoke execute on function public.erp_get_commercial_order_allocation_context(uuid,uuid,text) from public,anon;
grant execute on function public.erp_get_commercial_order_allocation_context(uuid,uuid,text) to authenticated,service_role;
revoke all on function public.erp_validate_commercial_warehouse_allocations(uuid,uuid,text,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.erp_validate_commercial_warehouse_allocations(uuid,uuid,text,jsonb,boolean) to service_role;
revoke all on function public.erp_create_cloud_sales_delivery_multi(uuid,uuid,jsonb,text) from public,anon,authenticated;
revoke all on function public.erp_create_cloud_purchase_receipt_multi(uuid,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.erp_create_cloud_sales_delivery_multi(uuid,uuid,jsonb,text) to service_role;
grant execute on function public.erp_create_cloud_purchase_receipt_multi(uuid,uuid,jsonb,text) to service_role;

commit;
