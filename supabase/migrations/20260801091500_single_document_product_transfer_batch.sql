-- One atomic multi-line product warehouse transfer document.
-- All lines share one source and one destination so the printed order has a
-- single warehouse pair and any failing line rolls the whole transaction back.
create or replace function public.erp_transfer_inventory_stock_batch(
  p_company_id uuid,
  p_lines jsonb,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line jsonb;
  v_transfer_id text := gen_random_uuid()::text;
  v_transfer_number text := 'TR-' || (extract(epoch from clock_timestamp()) * 1000000)::bigint;
  v_item_id text;
  v_now timestamptz := now();
  v_from_id text;
  v_to_id text;
  v_product_id text;
  v_quantity integer;
  v_from public.erp_warehouse_stock%rowtype;
  v_to public.erp_warehouse_stock%rowtype;
  v_available numeric;
  v_cost numeric;
  v_to_qty numeric;
  v_to_avg numeric;
  v_new_avg numeric;
  v_items jsonb := '[]'::jsonb;
begin
  if not public.can_manage_master_data(p_company_id) then
    raise exception 'access denied';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'يجب إضافة مادة واحدة على الأقل';
  end if;

  v_from_id := nullif(p_lines->0->>'fromWarehouseId', '');
  v_to_id := nullif(p_lines->0->>'toWarehouseId', '');
  if v_from_id is null or v_to_id is null or v_from_id = v_to_id then
    raise exception 'يجب اختيار مخزنين مختلفين';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_lines) value
    where value->>'fromWarehouseId' is distinct from v_from_id
       or value->>'toWarehouseId' is distinct from v_to_id
  ) then
    raise exception 'يجب أن تستخدم جميع مواد السند مخزن مصدر ومستلم واحدين';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_lines) value
    group by value->>'productId'
    having count(*) > 1
  ) then
    raise exception 'لا يمكن تكرار المادة نفسها في سند النقل';
  end if;

  insert into public.erp_warehouse_transfers(
    company_id, id, data, created_by, updated_by
  ) values (
    p_company_id,
    v_transfer_id,
    jsonb_build_object(
      'transferNumber', v_transfer_number,
      'fromWarehouseId', v_from_id,
      'toWarehouseId', v_to_id,
      'transferDate', v_now,
      'status', 'completed',
      'lineCount', jsonb_array_length(p_lines),
      'notes', p_notes,
      'createdAt', v_now
    ),
    auth.uid(),
    auth.uid()
  );

  -- Stable product ordering reduces deadlock risk when users transfer at once.
  for v_line in
    select value from jsonb_array_elements(p_lines) order by value->>'productId'
  loop
    v_product_id := nullif(v_line->>'productId', '');
    v_quantity := public.erp_try_integer(v_line->>'quantity', 0);
    if v_product_id is null or v_quantity <= 0 then
      raise exception 'بيانات مادة النقل غير صحيحة';
    end if;
    if not exists (
      select 1 from public.erp_inventory
      where company_id = p_company_id and id = v_product_id and not is_deleted
    ) then
      raise exception 'المنتج غير موجود: %', v_product_id;
    end if;

    v_from := public.erp_inventory_ensure_stock(p_company_id, v_from_id, v_product_id);
    v_available := public.erp_try_numeric(v_from.data->>'quantity', 0) -
      public.erp_try_numeric(v_from.data->>'reservedQuantity', 0);
    if v_available < v_quantity then
      raise exception 'الرصيد المتوفر في مخزن المصدر غير كافٍ للمادة %', v_product_id;
    end if;

    v_cost := public.erp_try_numeric(v_from.data->>'averageUnitCost', 0);
    v_to := public.erp_inventory_ensure_stock(p_company_id, v_to_id, v_product_id);
    v_to_qty := public.erp_try_numeric(v_to.data->>'quantity', 0);
    v_to_avg := public.erp_try_numeric(v_to.data->>'averageUnitCost', 0);
    v_new_avg := ((v_to_qty * v_to_avg) + (v_quantity * v_cost)) /
      (v_to_qty + v_quantity);

    v_item_id := gen_random_uuid()::text;
    insert into public.erp_warehouse_transfer_items(
      company_id, id, data, created_by, updated_by
    ) values (
      p_company_id,
      v_item_id,
      jsonb_build_object(
        'transferId', v_transfer_id,
        'productId', v_product_id,
        'quantity', v_quantity,
        'unitCost', v_cost,
        'totalCost', v_quantity * v_cost,
        'notes', coalesce(nullif(v_line->>'notes', ''), p_notes)
      ),
      auth.uid(),
      auth.uid()
    );

    update public.erp_warehouse_stock
    set data = data || jsonb_build_object(
      'quantity', (public.erp_try_numeric(v_from.data->>'quantity', 0) - v_quantity)::int,
      'updatedAt', v_now
    )
    where company_id = p_company_id and id = v_from.id;

    update public.erp_warehouse_stock
    set data = data || jsonb_build_object(
      'quantity', (v_to_qty + v_quantity)::int,
      'averageUnitCost', v_new_avg,
      'updatedAt', v_now
    )
    where company_id = p_company_id and id = v_to.id;

    perform public.erp_inventory_insert_movement(
      p_company_id, v_product_id, v_from_id, 'transfer_out', -v_quantity,
      v_cost, 'warehouse_transfer', v_transfer_id,
      coalesce(nullif(v_line->>'notes', ''), p_notes)
    );
    perform public.erp_inventory_insert_movement(
      p_company_id, v_product_id, v_to_id, 'transfer_in', v_quantity,
      v_cost, 'warehouse_transfer', v_transfer_id,
      coalesce(nullif(v_line->>'notes', ''), p_notes)
    );
    perform public.erp_inventory_refresh_product(p_company_id, v_product_id);

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'productId', v_product_id,
      'quantity', v_quantity,
      'unitCost', v_cost
    ));
  end loop;

  return jsonb_build_object(
    'transferId', v_transfer_id,
    'transferNumber', v_transfer_number,
    'fromWarehouseId', v_from_id,
    'toWarehouseId', v_to_id,
    'transferDate', v_now,
    'lineCount', jsonb_array_length(p_lines),
    'items', v_items,
    'status', 'completed'
  );
end;
$$;

grant execute on function public.erp_transfer_inventory_stock_batch(uuid, jsonb, text) to authenticated;
