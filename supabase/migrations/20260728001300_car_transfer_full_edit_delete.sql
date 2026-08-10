begin;

create or replace function public.erp_edit_car_warehouse_transfer(
  p_company_id uuid,p_transfer_id text,p_car_id text,p_to_warehouse_id text,
  p_user_name text,p_notes text default null
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_t public.erp_car_warehouse_transfers%rowtype;
  v_old public.erp_cars%rowtype;
  v_new public.erp_cars%rowtype;
  v_now timestamptz:=clock_timestamp();
  v_old_current text;
  v_new_from text;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  select * into v_t from public.erp_car_warehouse_transfers
   where company_id=p_company_id and id=p_transfer_id and not is_deleted for update;
  if not found then raise exception 'سند النقل غير موجود'; end if;
  if v_t.data->>'status'<>'completed' then raise exception 'لا يمكن تعديل سند مُرجع'; end if;

  select * into v_old from public.erp_cars where company_id=p_company_id
    and id=v_t.data->>'carId' and not is_deleted for update;
  if not found then raise exception 'السيارة الأصلية غير موجودة'; end if;
  v_old_current:=coalesce(v_old.data->>'warehouseId',v_old.data->>'warehouse_id');
  if v_old_current<>v_t.data->>'toWarehouseId' then raise exception 'تعذر التعديل لوجود حركة لاحقة على السيارة'; end if;

  if p_car_id=v_t.data->>'carId' then
    v_new:=v_old;
    v_new_from:=v_t.data->>'fromWarehouseId';
  else
    update public.erp_cars set data=(data-'warehouseId'-'warehouse_id')||jsonb_build_object(
      'warehouseId',v_t.data->>'fromWarehouseId','warehouse_id',v_t.data->>'fromWarehouseId','updatedAt',v_now),
      updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and id=v_t.data->>'carId';
    select * into v_new from public.erp_cars where company_id=p_company_id and id=p_car_id and not is_deleted for update;
    if not found then raise exception 'السيارة الجديدة غير موجودة'; end if;
    if lower(trim(coalesce(v_new.data->>'status',''))) not in ('available','متوفرة','متوفر','متاحة')
      or nullif(trim(coalesce(v_new.data->>'salesOrderId','')),'') is not null then
      raise exception 'السيارة الجديدة غير متاحة للنقل';
    end if;
    v_new_from:=nullif(trim(coalesce(v_new.data->>'warehouseId',v_new.data->>'warehouse_id','')),'');
  end if;
  if v_new_from is null or v_new_from=p_to_warehouse_id then raise exception 'يجب اختيار مخزن هدف مختلف'; end if;
  perform 1 from public.erp_warehouses where company_id=p_company_id and id=p_to_warehouse_id
    and not is_deleted and public.erp_try_boolean(data->>'isActive',true);
  if not found then raise exception 'المخزن الهدف غير موجود أو غير فعال'; end if;

  update public.erp_cars set data=(data-'warehouseId'-'warehouse_id')||jsonb_build_object(
    'warehouseId',p_to_warehouse_id,'warehouse_id',p_to_warehouse_id,'updatedAt',v_now),
    updated_at=v_now,updated_by=auth.uid()
  where company_id=p_company_id and id=p_car_id;

  update public.erp_car_warehouse_transfers set data=data||jsonb_build_object(
    'carId',p_car_id,'fromWarehouseId',v_new_from,'toWarehouseId',p_to_warehouse_id,
    'notes',p_notes,'updatedAt',v_now,'updatedByUserName',p_user_name),
    updated_at=v_now,updated_by=auth.uid()
  where company_id=p_company_id and id=p_transfer_id;
end; $$;

create or replace function public.erp_delete_car_warehouse_transfer(
  p_company_id uuid,p_transfer_id text,p_user_name text
) returns void language plpgsql security definer set search_path=public as $$
declare v_t public.erp_car_warehouse_transfers%rowtype; v_current text; v_now timestamptz:=clock_timestamp();
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  select * into v_t from public.erp_car_warehouse_transfers where company_id=p_company_id and id=p_transfer_id and not is_deleted for update;
  if not found then return; end if;
  if v_t.data->>'status'='completed' then
    select coalesce(data->>'warehouseId',data->>'warehouse_id') into v_current from public.erp_cars
      where company_id=p_company_id and id=v_t.data->>'carId' and not is_deleted for update;
    if v_current<>v_t.data->>'toWarehouseId' then raise exception 'تعذر الحذف لوجود حركة لاحقة على السيارة'; end if;
    update public.erp_cars set data=(data-'warehouseId'-'warehouse_id')||jsonb_build_object(
      'warehouseId',v_t.data->>'fromWarehouseId','warehouse_id',v_t.data->>'fromWarehouseId','updatedAt',v_now),
      updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and id=v_t.data->>'carId';
  end if;
  update public.erp_car_warehouse_transfers set is_deleted=true,deleted_at=v_now,updated_at=v_now,
    data=data||jsonb_build_object('deletedByUserName',p_user_name,'deletedAt',v_now)
  where company_id=p_company_id and id=p_transfer_id;
end; $$;

grant execute on function public.erp_edit_car_warehouse_transfer(uuid,text,text,text,text,text) to authenticated;
grant execute on function public.erp_delete_car_warehouse_transfer(uuid,text,text) to authenticated;
commit;
