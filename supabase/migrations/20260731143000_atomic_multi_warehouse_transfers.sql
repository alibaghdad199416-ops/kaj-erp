-- Atomic multi-line warehouse transfers for vehicles and products.
-- Any failing line aborts the whole PostgreSQL transaction.
create or replace function public.erp_create_car_warehouse_transfer_batch(
  p_company_id uuid,
  p_lines jsonb,
  p_to_warehouse_id uuid,
  p_user_name text,
  p_notes text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_line jsonb;
  v_ids jsonb := '[]'::jsonb;
  v_id uuid;
begin
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'يجب إضافة سيارة واحدة على الأقل';
  end if;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    v_id := public.erp_create_car_warehouse_transfer(
      p_company_id,
      v_line->>'carId',
      p_to_warehouse_id,
      p_user_name,
      coalesce(nullif(v_line->>'notes',''), p_notes)
    );
    v_ids := v_ids || jsonb_build_array(v_id);
  end loop;
  return jsonb_build_object('transferIds', v_ids, 'lineCount', jsonb_array_length(p_lines));
end $$;

create or replace function public.erp_transfer_inventory_stock_batch(
  p_company_id uuid,
  p_lines jsonb,
  p_notes text default null
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_line jsonb;
  v_count integer := 0;
begin
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'يجب إضافة مادة واحدة على الأقل';
  end if;
  for v_line in select value from jsonb_array_elements(p_lines) loop
    perform public.erp_transfer_inventory_stock(
      p_company_id,
      v_line->>'productId',
      v_line->>'fromWarehouseId',
      v_line->>'toWarehouseId',
      (v_line->>'quantity')::integer,
      coalesce(nullif(v_line->>'notes',''), p_notes)
    );
    v_count := v_count + 1;
  end loop;
  return jsonb_build_object('lineCount', v_count, 'status', 'approved');
end $$;

grant execute on function public.erp_create_car_warehouse_transfer_batch(uuid,jsonb,uuid,text,text) to authenticated;
grant execute on function public.erp_transfer_inventory_stock_batch(uuid,jsonb,text) to authenticated;
