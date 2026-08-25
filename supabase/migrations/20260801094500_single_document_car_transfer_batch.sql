-- Atomic multi-vehicle transfer batch with one source, one destination and a
-- shared printable batch number. Individual vehicle movements remain stored
-- for traceability, while the UI prints one official order containing all cars.
create or replace function public.erp_create_car_warehouse_transfer_batch(
  p_company_id uuid,
  p_lines jsonb,
  p_to_warehouse_id uuid,
  p_user_name text,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line jsonb;
  v_ids jsonb := '[]'::jsonb;
  v_id text;
  v_car_id text;
  v_source_id text;
  v_current_source_id text;
  v_destination_id text := p_to_warehouse_id::text;
  v_batch_number text := 'CTB-' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSMS');
  v_now timestamptz := clock_timestamp();
begin
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'يجب إضافة سيارة واحدة على الأقل';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(p_lines) value
    group by value->>'carId'
    having count(*) > 1
  ) then
    raise exception 'لا يمكن تكرار السيارة نفسها في سند النقل';
  end if;

  -- Validate the complete batch before mutating any vehicle. This guarantees
  -- that one invalid line aborts the whole PostgreSQL transaction.
  for v_line in
    select value from jsonb_array_elements(p_lines) order by value->>'carId'
  loop
    v_car_id := nullif(v_line->>'carId', '');
    if v_car_id is null then
      raise exception 'بيانات السيارة في سند النقل غير صحيحة';
    end if;
    select nullif(btrim(coalesce(data->>'warehouseId', data->>'warehouse_id', '')), '')
    into v_current_source_id
    from public.erp_cars
    where company_id = p_company_id and id = v_car_id and not is_deleted
    for share;
    if not found then
      raise exception 'السيارة غير موجودة: %', v_car_id;
    end if;
    if v_current_source_id is null then
      raise exception 'السيارة غير مرتبطة بمخزن حالي: %', v_car_id;
    end if;
    if v_source_id is null then
      v_source_id := v_current_source_id;
    elsif v_source_id <> v_current_source_id then
      raise exception 'يجب أن تكون جميع السيارات من مخزن مصدر واحد';
    end if;
  end loop;

  if v_source_id = v_destination_id then
    raise exception 'يجب اختيار مخزنين مختلفين';
  end if;

  for v_line in
    select value from jsonb_array_elements(p_lines) order by value->>'carId'
  loop
    v_id := public.erp_create_car_warehouse_transfer(
      p_company_id,
      v_line->>'carId',
      v_destination_id,
      p_user_name,
      coalesce(nullif(v_line->>'notes', ''), p_notes)
    );
    update public.erp_car_warehouse_transfers
    set data = data || jsonb_build_object(
          'batchNumber', v_batch_number,
          'batchLineCount', jsonb_array_length(p_lines),
          'batchCreatedAt', v_now
        ),
        updated_at = v_now,
        updated_by = auth.uid()
    where company_id = p_company_id and id = v_id;
    v_ids := v_ids || jsonb_build_array(v_id);
  end loop;

  return jsonb_build_object(
    'batchNumber', v_batch_number,
    'transferIds', v_ids,
    'fromWarehouseId', v_source_id,
    'toWarehouseId', v_destination_id,
    'lineCount', jsonb_array_length(p_lines),
    'createdAt', v_now,
    'status', 'completed'
  );
end;
$$;

grant execute on function public.erp_create_car_warehouse_transfer_batch(uuid,jsonb,uuid,text,text) to authenticated;
