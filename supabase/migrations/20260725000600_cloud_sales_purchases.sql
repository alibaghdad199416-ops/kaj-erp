begin;

create table if not exists public.erp_sales (like public.erp_cars including all);
create table if not exists public.erp_installments (like public.erp_cars including all);
create table if not exists public.erp_purchases (like public.erp_cars including all);
create table if not exists public.erp_purchase_items (like public.erp_cars including all);

create unique index if not exists erp_sales_primary_car_uq
  on public.erp_sales(company_id, (data->>'carId'))
  where not is_deleted and coalesce(data->>'saleType','primary') = 'primary';
create unique index if not exists erp_purchases_invoice_uq
  on public.erp_purchases(company_id, lower(data->>'invoiceNumber'))
  where not is_deleted;
create index if not exists erp_sales_customer_idx
  on public.erp_sales(company_id, (data->>'customerId'), (data->>'saleDate'))
  where not is_deleted;
create index if not exists erp_installments_sale_idx
  on public.erp_installments(company_id, (data->>'saleId'), ((data->>'installmentNo')::int))
  where not is_deleted;
create index if not exists erp_purchase_supplier_idx
  on public.erp_purchases(company_id, (data->>'supplierId'), (data->>'purchaseDate'))
  where not is_deleted;
create index if not exists erp_purchase_items_purchase_idx
  on public.erp_purchase_items(company_id, (data->>'purchaseId'))
  where not is_deleted;
create index if not exists erp_purchase_items_car_idx
  on public.erp_purchase_items(company_id, (data->>'carId'))
  where not is_deleted;

do $$ declare t text; begin
  foreach t in array array['erp_sales','erp_installments','erp_purchases','erp_purchase_items'] loop
    execute format('alter table public.%I enable row level security', t);
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

grant select,insert,update on public.erp_sales,public.erp_installments,
  public.erp_purchases,public.erp_purchase_items to authenticated;

create or replace function public.erp_create_cloud_sale(
  p_company_id uuid,
  p_sale jsonb,
  p_installments jsonb default '[]'::jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_sale_id text:=p_sale->>'id';
  v_car_id text:=p_sale->>'carId';
  v_customer_id text:=p_sale->>'customerId';
  v_car public.erp_cars%rowtype;
  v_item jsonb;
  v_total numeric:=0;
  v_remaining numeric:=coalesce((p_sale->>'remainingAmount')::numeric,0);
  v_now timestamptz:=now();
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if coalesce(v_sale_id,'')='' or coalesce(v_car_id,'')='' or coalesce(v_customer_id,'')='' then
    raise exception 'بيانات فاتورة البيع غير مكتملة';
  end if;
  if coalesce((p_sale->>'salePrice')::numeric,-1)<0 or
     coalesce((p_sale->>'paidAmount')::numeric,-1)<0 or v_remaining<0 then
    raise exception 'قيم فاتورة البيع غير صحيحة';
  end if;
  if abs(coalesce((p_sale->>'paidAmount')::numeric,0)+v_remaining-
         coalesce((p_sale->>'salePrice')::numeric,0))>0.01 then
    raise exception 'مجموع المدفوع والمتبقي لا يطابق سعر البيع';
  end if;
  if not exists(select 1 from public.erp_customers where company_id=p_company_id and id=v_customer_id and not is_deleted) then
    raise exception 'العميل غير موجود';
  end if;
  select * into v_car from public.erp_cars
    where company_id=p_company_id and id=v_car_id and not is_deleted for update;
  if not found then raise exception 'السيارة غير موجودة'; end if;
  if coalesce(v_car.data->>'status','') not in ('متوفرة','قيد البيع') then
    raise exception 'لا يمكن بيع سيارة حالتها الحالية: %',coalesce(v_car.data->>'status','');
  end if;
  if exists(select 1 from public.erp_sales where company_id=p_company_id and not is_deleted
            and data->>'carId'=v_car_id and coalesce(data->>'saleType','primary')='primary') then
    raise exception 'هذه السيارة مرتبطة بفاتورة بيع مسبقاً';
  end if;
  if jsonb_typeof(p_installments)<>'array' then raise exception 'قائمة الأقساط غير صحيحة'; end if;
  for v_item in select value from jsonb_array_elements(p_installments) loop
    if v_item->>'saleId'<>v_sale_id then raise exception 'قسط غير مرتبط بالفاتورة'; end if;
    v_total:=v_total+coalesce((v_item->>'amount')::numeric,0);
  end loop;
  if jsonb_array_length(p_installments)>0 and abs(v_total-v_remaining)>0.01 then
    raise exception 'إجمالي الأقساط لا يطابق المبلغ المتبقي';
  end if;
  insert into public.erp_sales(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_sale_id,p_sale||jsonb_build_object('createdAt',coalesce(p_sale->'createdAt',to_jsonb(v_now)),'updatedAt',v_now),auth.uid(),auth.uid());
  for v_item in select value from jsonb_array_elements(p_installments) loop
    insert into public.erp_installments(company_id,id,data,created_by,updated_by)
    values(p_company_id,v_item->>'id',v_item||jsonb_build_object('updatedAt',v_now),auth.uid(),auth.uid());
  end loop;
  update public.erp_cars set data=data||jsonb_build_object('status','مباعة','updatedAt',v_now),updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and id=v_car_id and not is_deleted;
end $$;

create or replace function public.erp_create_cloud_resale(
  p_company_id uuid,
  p_sale jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_car_id text:=p_sale->>'carId';
  v_previous text:=p_sale->>'previousSaleId';
  v_seller text:=p_sale->>'sellerCustomerId';
  v_current_owner text;
  v_sequence integer;
  v_now timestamptz:=now();
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if coalesce(p_sale->>'saleType','')<>'resale' or coalesce(v_previous,'')='' or coalesce(v_seller,'')='' then
    raise exception 'بيانات إعادة البيع غير مكتملة';
  end if;
  perform 1 from public.erp_cars where company_id=p_company_id and id=v_car_id and not is_deleted for update;
  if not found then raise exception 'السيارة غير موجودة'; end if;
  if not exists(select 1 from public.erp_sales where company_id=p_company_id and id=v_previous and not is_deleted and data->>'carId'=v_car_id) then
    raise exception 'لم يتم العثور على فاتورة البيع السابقة';
  end if;
  select data->>'customerId',coalesce((data->>'saleSequence')::int,1)
    into v_current_owner,v_sequence from public.erp_sales
    where company_id=p_company_id and not is_deleted and data->>'carId'=v_car_id
    order by coalesce((data->>'saleSequence')::int,1) desc,data->>'saleDate' desc limit 1;
  if v_current_owner<>v_seller then raise exception 'البائع ليس المالك الحالي المسجل للسيارة'; end if;
  if p_sale->>'customerId'=v_seller then raise exception 'لا يمكن إعادة بيع السيارة للمالك نفسه'; end if;
  insert into public.erp_sales(company_id,id,data,created_by,updated_by)
  values(p_company_id,p_sale->>'id',p_sale||jsonb_build_object('saleSequence',v_sequence+1,'updatedAt',v_now),auth.uid(),auth.uid());
  update public.erp_cars set data=data||jsonb_build_object('status','مباعة','updatedAt',v_now),updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and id=v_car_id;
end $$;

create or replace function public.erp_update_cloud_sale(
  p_company_id uuid,p_sale jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare v_id text:=p_sale->>'id'; v_existing public.erp_sales%rowtype;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  select * into v_existing from public.erp_sales where company_id=p_company_id and id=v_id and not is_deleted for update;
  if not found then raise exception 'فاتورة البيع غير موجودة'; end if;
  if p_sale->>'carId'<>v_existing.data->>'carId' then raise exception 'لا يمكن تغيير سيارة فاتورة البيع'; end if;
  update public.erp_sales set data=p_sale||jsonb_build_object('updatedAt',now()),updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=v_id;
end $$;

create or replace function public.erp_delete_cloud_sale(
  p_company_id uuid,p_sale_id text
) returns void language plpgsql security definer set search_path=public as $$
declare v_sale public.erp_sales%rowtype; v_now timestamptz:=now();
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  select * into v_sale from public.erp_sales where company_id=p_company_id and id=p_sale_id and not is_deleted for update;
  if not found then return; end if;
  update public.erp_installments set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and not is_deleted and data->>'saleId'=p_sale_id;
  update public.erp_sales set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and id=p_sale_id;
  if not exists(select 1 from public.erp_sales where company_id=p_company_id and not is_deleted and data->>'carId'=v_sale.data->>'carId') then
    update public.erp_cars set data=data||jsonb_build_object('status','متوفرة','updatedAt',v_now),updated_at=v_now,updated_by=auth.uid()
      where company_id=p_company_id and id=v_sale.data->>'carId' and not is_deleted;
  end if;
end $$;

create or replace function public.erp_create_cloud_purchase(
  p_company_id uuid,p_purchase jsonb,p_items jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare v_id text:=p_purchase->>'id'; v_item jsonb; v_total numeric:=0; v_car public.erp_cars%rowtype; v_now timestamptz:=now();
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if coalesce(v_id,'')='' or coalesce(p_purchase->>'supplierId','')='' or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
    raise exception 'بيانات فاتورة الشراء غير مكتملة';
  end if;
  if not exists(select 1 from public.erp_suppliers where company_id=p_company_id and id=p_purchase->>'supplierId' and not is_deleted) then
    raise exception 'المجهز غير موجود';
  end if;
  if exists(select 1 from public.erp_purchases where company_id=p_company_id and not is_deleted and lower(data->>'invoiceNumber')=lower(p_purchase->>'invoiceNumber')) then
    raise exception 'رقم فاتورة الشراء مستخدم مسبقاً';
  end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    if v_item->>'purchaseId'<>v_id then raise exception 'عنصر غير مرتبط بالفاتورة'; end if;
    v_total:=v_total+coalesce((v_item->>'totalCost')::numeric,0);
    select * into v_car from public.erp_cars where company_id=p_company_id and id=v_item->>'carId' and not is_deleted for update;
    if not found then raise exception 'إحدى السيارات غير موجودة'; end if;
    if exists(select 1 from public.erp_purchase_items where company_id=p_company_id and not is_deleted and data->>'carId'=v_item->>'carId') then
      raise exception 'إحدى السيارات مرتبطة بفاتورة شراء مسبقاً';
    end if;
  end loop;
  if abs(v_total-coalesce((p_purchase->>'totalAmount')::numeric,0))>0.01 then raise exception 'إجمالي الفاتورة لا يطابق إجمالي السيارات'; end if;
  insert into public.erp_purchases(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_id,p_purchase||jsonb_build_object('updatedAt',v_now),auth.uid(),auth.uid());
  for v_item in select value from jsonb_array_elements(p_items) loop
    insert into public.erp_purchase_items(company_id,id,data,created_by,updated_by)
    values(p_company_id,v_item->>'id',v_item||jsonb_build_object('updatedAt',v_now),auth.uid(),auth.uid());
    update public.erp_cars set data=data||jsonb_build_object('status','متوفرة','purchasePrice',v_item->'purchasePrice','updatedAt',v_now),updated_at=v_now,updated_by=auth.uid()
      where company_id=p_company_id and id=v_item->>'carId';
  end loop;
end $$;

create or replace function public.erp_update_cloud_purchase(
  p_company_id uuid,p_purchase jsonb,p_items jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare v_id text:=p_purchase->>'id'; v_item jsonb; v_total numeric:=0; v_now timestamptz:=now();
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  perform 1 from public.erp_purchases where company_id=p_company_id and id=v_id and not is_deleted for update;
  if not found then raise exception 'فاتورة الشراء غير موجودة'; end if;
  if exists(select 1 from public.erp_purchases where company_id=p_company_id and id<>v_id and not is_deleted and lower(data->>'invoiceNumber')=lower(p_purchase->>'invoiceNumber')) then
    raise exception 'رقم فاتورة الشراء مستخدم مسبقاً';
  end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    if v_item->>'purchaseId'<>v_id then raise exception 'عنصر غير مرتبط بالفاتورة'; end if;
    v_total:=v_total+coalesce((v_item->>'totalCost')::numeric,0);
  end loop;
  if abs(v_total-coalesce((p_purchase->>'totalAmount')::numeric,0))>0.01 then raise exception 'إجمالي الفاتورة لا يطابق إجمالي السيارات'; end if;
  update public.erp_purchases set data=p_purchase||jsonb_build_object('updatedAt',v_now),updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and id=v_id;
  update public.erp_purchase_items set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and not is_deleted and data->>'purchaseId'=v_id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    insert into public.erp_purchase_items(company_id,id,data,created_by,updated_by,is_deleted,deleted_at)
    values(p_company_id,v_item->>'id',v_item||jsonb_build_object('updatedAt',v_now),auth.uid(),auth.uid(),false,null)
    on conflict(company_id,id) do update set data=excluded.data,is_deleted=false,deleted_at=null,updated_at=v_now,updated_by=auth.uid();
  end loop;
end $$;

create or replace function public.erp_delete_cloud_purchase(
  p_company_id uuid,p_purchase_id text
) returns void language plpgsql security definer set search_path=public as $$
declare v_item record; v_now timestamptz:=now();
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  perform 1 from public.erp_purchases where company_id=p_company_id and id=p_purchase_id and not is_deleted for update;
  if not found then raise exception 'فاتورة الشراء غير موجودة'; end if;
  for v_item in select data->>'carId' car_id from public.erp_purchase_items where company_id=p_company_id and not is_deleted and data->>'purchaseId'=p_purchase_id loop
    if exists(select 1 from public.erp_sales where company_id=p_company_id and not is_deleted and data->>'carId'=v_item.car_id) then
      raise exception 'لا يمكن إلغاء الشراء لأن إحدى السيارات تم بيعها لاحقاً';
    end if;
    if exists(select 1 from public.erp_records where company_id=p_company_id and entity_type='reservations' and deleted_at is null and payload->>'carId'=v_item.car_id and payload->>'status'='active') then
      raise exception 'لا يمكن إلغاء الشراء لأن إحدى السيارات قيد البيع حالياً';
    end if;
  end loop;
  for v_item in select data->>'carId' car_id from public.erp_purchase_items where company_id=p_company_id and not is_deleted and data->>'purchaseId'=p_purchase_id loop
    update public.erp_cars set data=data||jsonb_build_object('status','معرفة','warehouseId',null,'updatedAt',v_now),updated_at=v_now,updated_by=auth.uid()
      where company_id=p_company_id and id=v_item.car_id and not is_deleted;
  end loop;
  update public.erp_purchase_items set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and not is_deleted and data->>'purchaseId'=p_purchase_id;
  update public.erp_purchases set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
    where company_id=p_company_id and id=p_purchase_id;
end $$;

grant execute on function public.erp_create_cloud_sale(uuid,jsonb,jsonb) to authenticated;
grant execute on function public.erp_create_cloud_resale(uuid,jsonb) to authenticated;
grant execute on function public.erp_update_cloud_sale(uuid,jsonb) to authenticated;
grant execute on function public.erp_delete_cloud_sale(uuid,text) to authenticated;
grant execute on function public.erp_create_cloud_purchase(uuid,jsonb,jsonb) to authenticated;
grant execute on function public.erp_update_cloud_purchase(uuid,jsonb,jsonb) to authenticated;
grant execute on function public.erp_delete_cloud_purchase(uuid,text) to authenticated;

alter publication supabase_realtime add table public.erp_sales;
alter publication supabase_realtime add table public.erp_installments;
alter publication supabase_realtime add table public.erp_purchases;
alter publication supabase_realtime add table public.erp_purchase_items;

commit;
