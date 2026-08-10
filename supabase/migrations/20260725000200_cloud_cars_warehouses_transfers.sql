begin;

create table if not exists public.erp_car_images (like public.erp_cars including all);
create table if not exists public.erp_warehouses (like public.erp_cars including all);
create table if not exists public.erp_car_warehouse_transfers (like public.erp_cars including all);

create index if not exists erp_car_images_car_idx on public.erp_car_images(company_id, (data->>'carId')) where not is_deleted;
create index if not exists erp_warehouses_active_idx on public.erp_warehouses(company_id, (data->>'isActive')) where not is_deleted;
create index if not exists erp_car_transfers_date_idx on public.erp_car_warehouse_transfers(company_id, (data->>'transferDate')) where not is_deleted;

alter table public.erp_car_images enable row level security;
alter table public.erp_warehouses enable row level security;
alter table public.erp_car_warehouse_transfers enable row level security;

do $$ declare t text; begin
  foreach t in array array['erp_car_images','erp_warehouses','erp_car_warehouse_transfers'] loop
    execute format('drop policy if exists %I_select on public.%I', t, t);
    execute format('drop policy if exists %I_insert on public.%I', t, t);
    execute format('drop policy if exists %I_update on public.%I', t, t);
    execute format('create policy %I_select on public.%I for select to authenticated using (public.is_active_company_member(company_id))', t, t);
    execute format('create policy %I_insert on public.%I for insert to authenticated with check (public.can_manage_master_data(company_id))', t, t);
    execute format('create policy %I_update on public.%I for update to authenticated using (public.can_manage_master_data(company_id)) with check (public.can_manage_master_data(company_id))', t, t);
    execute format('drop trigger if exists %I_before_write on public.%I', t, t);
    execute format('create trigger %I_before_write before insert or update on public.%I for each row execute function public.erp_master_before_write()', t, t);
  end loop;
end $$;

grant select, insert, update on public.erp_car_images, public.erp_warehouses, public.erp_car_warehouse_transfers to authenticated;

create or replace function public.erp_create_car_warehouse_transfer(
  p_company_id uuid, p_car_id text, p_to_warehouse_id text,
  p_user_name text, p_notes text default null
) returns text language plpgsql security definer set search_path=public as $$
declare v_car public.erp_cars%rowtype; v_wh public.erp_warehouses%rowtype; v_id text; v_now timestamptz:=now(); v_from text;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  select * into v_car from public.erp_cars where company_id=p_company_id and id=p_car_id and not is_deleted for update;
  if not found then raise exception 'السيارة غير موجودة'; end if;
  if coalesce(v_car.data->>'status','') not in ('available','متوفرة') then raise exception 'لا يمكن نقل السيارة إلا عندما تكون متوفرة'; end if;
  v_from:=coalesce(v_car.data->>'warehouse_id',v_car.data->>'warehouseId');
  if coalesce(v_from,'')='' then raise exception 'السيارة غير مرتبطة بمخزن حالي'; end if;
  if v_from=p_to_warehouse_id then raise exception 'يجب اختيار مخزن مختلف'; end if;
  select * into v_wh from public.erp_warehouses where company_id=p_company_id and id=p_to_warehouse_id and not is_deleted for share;
  if not found or coalesce(v_wh.data->>'isActive','false') not in ('true','1') then raise exception 'المخزن الهدف غير موجود أو غير فعال'; end if;
  v_id:=gen_random_uuid()::text;
  insert into public.erp_car_warehouse_transfers(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_id,jsonb_build_object('transferNumber','CT-'||(extract(epoch from v_now)*1000000)::bigint,'carId',p_car_id,'fromWarehouseId',v_from,'toWarehouseId',p_to_warehouse_id,'transferDate',v_now,'status','completed','notes',p_notes,'createdAt',v_now,'createdByUserId',auth.uid()::text,'createdByUserName',p_user_name),auth.uid(),auth.uid());
  update public.erp_cars set data=jsonb_set(jsonb_set(data,'{warehouse_id}',to_jsonb(p_to_warehouse_id),true),'{updated_at}',to_jsonb(v_now::text),true) where company_id=p_company_id and id=p_car_id;
  return v_id;
end $$;

create or replace function public.erp_update_car_warehouse_transfer(
 p_company_id uuid,p_transfer_id text,p_to_warehouse_id text,p_user_name text,p_notes text default null
) returns void language plpgsql security definer set search_path=public as $$
declare v_t public.erp_car_warehouse_transfers%rowtype; v_car public.erp_cars%rowtype; v_wh public.erp_warehouses%rowtype; v_now timestamptz:=now();
begin
 if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
 select * into v_t from public.erp_car_warehouse_transfers where company_id=p_company_id and id=p_transfer_id and not is_deleted for update;
 if not found then raise exception 'سند النقل غير موجود'; end if;
 if v_t.data->>'status'<>'completed' then raise exception 'لا يمكن تعديل سند مُرجع'; end if;
 select * into v_car from public.erp_cars where company_id=p_company_id and id=v_t.data->>'carId' and not is_deleted for update;
 if coalesce(v_car.data->>'warehouse_id',v_car.data->>'warehouseId')<>v_t.data->>'toWarehouseId' then raise exception 'تعذر التعديل لأن السيارة نُقلت بحركة لاحقة'; end if;
 select * into v_wh from public.erp_warehouses where company_id=p_company_id and id=p_to_warehouse_id and not is_deleted;
 if not found or coalesce(v_wh.data->>'isActive','false') not in ('true','1') then raise exception 'المخزن الهدف غير موجود أو غير فعال'; end if;
 update public.erp_car_warehouse_transfers set data=data||jsonb_build_object('toWarehouseId',p_to_warehouse_id,'notes',p_notes,'updatedAt',v_now,'updatedByUserId',auth.uid()::text,'updatedByUserName',p_user_name) where company_id=p_company_id and id=p_transfer_id;
 update public.erp_cars set data=jsonb_set(data,'{warehouse_id}',to_jsonb(p_to_warehouse_id),true) where company_id=p_company_id and id=v_t.data->>'carId';
end $$;

create or replace function public.erp_reverse_car_warehouse_transfer(p_company_id uuid,p_transfer_id text,p_user_name text)
returns void language plpgsql security definer set search_path=public as $$
declare v_t public.erp_car_warehouse_transfers%rowtype; v_car public.erp_cars%rowtype; v_now timestamptz:=now();
begin
 if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
 select * into v_t from public.erp_car_warehouse_transfers where company_id=p_company_id and id=p_transfer_id and not is_deleted for update;
 if not found then raise exception 'سند النقل غير موجود'; end if;
 if v_t.data->>'status'<>'completed' then raise exception 'تم إرجاع هذا النقل مسبقاً'; end if;
 select * into v_car from public.erp_cars where company_id=p_company_id and id=v_t.data->>'carId' and not is_deleted for update;
 if coalesce(v_car.data->>'warehouse_id',v_car.data->>'warehouseId')<>v_t.data->>'toWarehouseId' then raise exception 'لا يمكن الإرجاع لوجود حركة مخزنية لاحقة'; end if;
 update public.erp_cars set data=jsonb_set(data,'{warehouse_id}',to_jsonb(v_t.data->>'fromWarehouseId'),true) where company_id=p_company_id and id=v_t.data->>'carId';
 update public.erp_car_warehouse_transfers set data=data||jsonb_build_object('status','reversed','reversedAt',v_now,'reversedByUserId',auth.uid()::text,'reversedByUserName',p_user_name) where company_id=p_company_id and id=p_transfer_id;
end $$;

grant execute on function public.erp_create_car_warehouse_transfer(uuid,text,text,text,text) to authenticated;
grant execute on function public.erp_update_car_warehouse_transfer(uuid,text,text,text,text) to authenticated;
grant execute on function public.erp_reverse_car_warehouse_transfer(uuid,text,text) to authenticated;

do $$ begin alter publication supabase_realtime add table public.erp_car_images; exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.erp_warehouses; exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.erp_car_warehouse_transfers; exception when duplicate_object then null; when undefined_object then null; end $$;
commit;
