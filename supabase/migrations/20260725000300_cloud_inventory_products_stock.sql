begin;

create table if not exists public.erp_inventory (like public.erp_cars including all);
create table if not exists public.erp_inventory_groups (like public.erp_cars including all);
create table if not exists public.erp_warehouse_stock (like public.erp_cars including all);
create table if not exists public.erp_product_images (like public.erp_cars including all);
create table if not exists public.erp_inventory_movements (like public.erp_cars including all);
create table if not exists public.erp_warehouse_transfers (like public.erp_cars including all);
create table if not exists public.erp_warehouse_transfer_items (like public.erp_cars including all);
create table if not exists public.erp_inventory_receipts (like public.erp_cars including all);
create table if not exists public.erp_inventory_product_sales (like public.erp_cars including all);

create unique index if not exists erp_inventory_code_uq
  on public.erp_inventory(company_id, lower(data->>'code')) where not is_deleted;
create unique index if not exists erp_warehouse_stock_pair_uq
  on public.erp_warehouse_stock(company_id, (data->>'warehouseId'), (data->>'productId')) where not is_deleted;
create index if not exists erp_inventory_group_idx on public.erp_inventory(company_id, (data->>'groupId')) where not is_deleted;
create index if not exists erp_inventory_movement_product_idx on public.erp_inventory_movements(company_id, (data->>'productId'), (data->>'movementDate')) where not is_deleted;
create index if not exists erp_product_images_product_idx on public.erp_product_images(company_id, (data->>'productId'), ((data->>'sortOrder')::int)) where not is_deleted;

alter table public.erp_inventory enable row level security;
alter table public.erp_inventory_groups enable row level security;
alter table public.erp_warehouse_stock enable row level security;
alter table public.erp_product_images enable row level security;
alter table public.erp_inventory_movements enable row level security;
alter table public.erp_warehouse_transfers enable row level security;
alter table public.erp_warehouse_transfer_items enable row level security;
alter table public.erp_inventory_receipts enable row level security;
alter table public.erp_inventory_product_sales enable row level security;

do $$ declare t text; begin
  foreach t in array array[
    'erp_inventory','erp_inventory_groups','erp_warehouse_stock',
    'erp_product_images','erp_inventory_movements','erp_warehouse_transfers',
    'erp_warehouse_transfer_items','erp_inventory_receipts','erp_inventory_product_sales'
  ] loop
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

grant select, insert, update on
  public.erp_inventory, public.erp_inventory_groups, public.erp_warehouse_stock,
  public.erp_product_images, public.erp_inventory_movements,
  public.erp_warehouse_transfers, public.erp_warehouse_transfer_items,
  public.erp_inventory_receipts, public.erp_inventory_product_sales
  to authenticated;

create or replace function public.erp_inventory_refresh_product(
  p_company_id uuid, p_product_id text
) returns void language plpgsql security definer set search_path=public as $$
declare v_qty numeric; v_value numeric; v_in numeric; v_out numeric;
begin
  select coalesce(sum((data->>'quantity')::numeric),0),
         coalesce(sum((data->>'quantity')::numeric * (data->>'averageUnitCost')::numeric),0),
         coalesce(sum((data->>'expectedIncoming')::numeric),0),
         coalesce(sum((data->>'expectedOutgoing')::numeric),0)
    into v_qty,v_value,v_in,v_out
  from public.erp_warehouse_stock
  where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id;
  update public.erp_inventory
  set data = data || jsonb_build_object(
    'quantity',v_qty::int,'expectedIncoming',v_in::int,'expectedOutgoing',v_out::int,
    'unitCost',case when v_qty>0 then v_value/v_qty else coalesce((data->>'unitCost')::numeric,0) end,
    'updatedAt',now()
  )
  where company_id=p_company_id and id=p_product_id and not is_deleted;
end $$;

create or replace function public.erp_inventory_insert_movement(
  p_company_id uuid,p_product_id text,p_warehouse_id text,p_type text,
  p_quantity integer,p_unit_cost numeric,p_reference_type text default null,
  p_reference_id text default null,p_notes text default null
) returns text language plpgsql security definer set search_path=public as $$
declare v_id text:=gen_random_uuid()::text; v_now timestamptz:=now();
begin
  insert into public.erp_inventory_movements(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_id,jsonb_build_object(
    'movementNumber','MV-'||(extract(epoch from v_now)*1000000)::bigint,
    'productId',p_product_id,'warehouseId',p_warehouse_id,'movementType',p_type,
    'quantity',p_quantity,'unitCost',p_unit_cost,'totalCost',abs(p_quantity)*p_unit_cost,
    'referenceType',p_reference_type,'referenceId',p_reference_id,
    'movementDate',v_now,'notes',p_notes,'createdAt',v_now
  ),auth.uid(),auth.uid());
  return v_id;
end $$;

create or replace function public.erp_inventory_ensure_stock(
  p_company_id uuid,p_warehouse_id text,p_product_id text
) returns public.erp_warehouse_stock language plpgsql security definer set search_path=public as $$
declare v_stock public.erp_warehouse_stock%rowtype; v_id text:=p_warehouse_id||'::'||p_product_id;
begin
  select * into v_stock from public.erp_warehouse_stock
  where company_id=p_company_id and not is_deleted
    and data->>'warehouseId'=p_warehouse_id and data->>'productId'=p_product_id
  for update;
  if not found then
    insert into public.erp_warehouse_stock(company_id,id,data,created_by,updated_by)
    values(p_company_id,v_id,jsonb_build_object(
      'warehouseId',p_warehouse_id,'productId',p_product_id,'quantity',0,
      'reservedQuantity',0,'expectedIncoming',0,'expectedOutgoing',0,
      'averageUnitCost',0,'updatedAt',now()
    ),auth.uid(),auth.uid()) returning * into v_stock;
  end if;
  return v_stock;
end $$;

create or replace function public.erp_create_inventory_product(
  p_company_id uuid,p_product_id text,p_product jsonb,p_warehouse_id text,
  p_opening_quantity integer,p_images jsonb,p_user_name text
) returns void language plpgsql security definer set search_path=public as $$
declare v_now timestamptz:=now(); v_image text; v_index int:=0;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if p_opening_quantity<0 then raise exception 'الرصيد الافتتاحي غير صحيح'; end if;
  if exists(select 1 from public.erp_inventory where company_id=p_company_id and not is_deleted and lower(data->>'code')=lower(p_product->>'code')) then
    raise exception 'رمز المنتج مستخدم مسبقاً';
  end if;
  insert into public.erp_inventory(company_id,id,data,created_by,updated_by)
  values(p_company_id,p_product_id,p_product||jsonb_build_object('quantity',p_opening_quantity,'createdAt',v_now,'updatedAt',v_now),auth.uid(),auth.uid());
  insert into public.erp_warehouse_stock(company_id,id,data,created_by,updated_by)
  values(p_company_id,p_warehouse_id||'::'||p_product_id,jsonb_build_object(
    'warehouseId',p_warehouse_id,'productId',p_product_id,'quantity',p_opening_quantity,
    'reservedQuantity',0,'expectedIncoming',0,'expectedOutgoing',0,
    'averageUnitCost',coalesce((p_product->>'unitCost')::numeric,0),'updatedAt',v_now
  ),auth.uid(),auth.uid());
  if jsonb_typeof(p_images)='array' then
    for v_image in select jsonb_array_elements_text(p_images) loop
      insert into public.erp_product_images(company_id,id,data,created_by,updated_by)
      values(p_company_id,gen_random_uuid()::text,jsonb_build_object('productId',p_product_id,'imageBase64',v_image,'sortOrder',v_index,'createdAt',v_now),auth.uid(),auth.uid());
      v_index:=v_index+1;
    end loop;
  end if;
  if p_opening_quantity>0 then
    perform public.erp_inventory_insert_movement(p_company_id,p_product_id,p_warehouse_id,'opening',p_opening_quantity,coalesce((p_product->>'unitCost')::numeric,0),'product_opening',p_product_id,'رصيد افتتاحي للمنتج');
  end if;
end $$;

create or replace function public.erp_delete_inventory_product(
  p_company_id uuid,p_product_id text
) returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if exists(select 1 from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id and coalesce((data->>'quantity')::numeric,0)<>0) then
    raise exception 'لا يمكن حذف منتج لديه رصيد مخزني';
  end if;
  if exists(select 1 from public.erp_inventory_movements where company_id=p_company_id and not is_deleted and data->>'productId'=p_product_id) then
    raise exception 'لا يمكن حذف منتج له سجل حركة مخزنية';
  end if;
  update public.erp_product_images set is_deleted=true,deleted_at=now(),updated_at=now() where company_id=p_company_id and data->>'productId'=p_product_id and not is_deleted;
  update public.erp_warehouse_stock set is_deleted=true,deleted_at=now(),updated_at=now() where company_id=p_company_id and data->>'productId'=p_product_id and not is_deleted;
  update public.erp_inventory set is_deleted=true,deleted_at=now(),updated_at=now() where company_id=p_company_id and id=p_product_id and not is_deleted;
  if not found then raise exception 'المنتج غير موجود'; end if;
end $$;

create or replace function public.erp_receive_inventory_stock(
  p_company_id uuid,p_product_id text,p_warehouse_id text,p_quantity integer,
  p_unit_purchase_price numeric,p_freight_cost numeric,p_customs_cost numeric,
  p_insurance_cost numeric,p_other_cost numeric,p_supplier_id text default null,
  p_supplier_name text default null,p_notes text default null
) returns text language plpgsql security definer set search_path=public as $$
declare v_product public.erp_inventory%rowtype; v_stock public.erp_warehouse_stock%rowtype; v_id text:=gen_random_uuid()::text;
 v_now timestamptz:=now(); v_extra numeric; v_unit numeric; v_total numeric; v_old_qty numeric; v_new_qty numeric; v_old_avg numeric; v_new_avg numeric; v_expected numeric;
begin
 if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
 if p_quantity<=0 then raise exception 'يجب أن تكون الكمية أكبر من صفر'; end if;
 if least(p_unit_purchase_price,p_freight_cost,p_customs_cost,p_insurance_cost,p_other_cost)<0 then raise exception 'التكاليف لا يمكن أن تكون سالبة'; end if;
 select * into v_product from public.erp_inventory where company_id=p_company_id and id=p_product_id and not is_deleted for update;
 if not found then raise exception 'المنتج غير موجود'; end if;
 v_stock:=public.erp_inventory_ensure_stock(p_company_id,p_warehouse_id,p_product_id);
 v_extra:=p_freight_cost+p_customs_cost+p_insurance_cost+p_other_cost; v_unit:=p_unit_purchase_price+(v_extra/p_quantity); v_total:=v_unit*p_quantity;
 v_old_qty:=coalesce((v_stock.data->>'quantity')::numeric,0); v_old_avg:=coalesce((v_stock.data->>'averageUnitCost')::numeric,0); v_new_qty:=v_old_qty+p_quantity;
 v_new_avg:=case when v_new_qty=0 then v_unit else ((v_old_qty*v_old_avg)+v_total)/v_new_qty end; v_expected:=coalesce((v_stock.data->>'expectedIncoming')::numeric,0);
 update public.erp_warehouse_stock set data=data||jsonb_build_object('quantity',v_new_qty::int,'expectedIncoming',greatest(v_expected-p_quantity,0)::int,'averageUnitCost',v_new_avg,'updatedAt',v_now) where company_id=p_company_id and id=v_stock.id;
 insert into public.erp_inventory_receipts(company_id,id,data,created_by,updated_by) values(p_company_id,v_id,jsonb_build_object('receiptNumber','IR-'||(extract(epoch from v_now)*1000000)::bigint,'productId',p_product_id,'warehouseId',p_warehouse_id,'supplierId',p_supplier_id,'supplierName',p_supplier_name,'quantity',p_quantity,'unitPurchasePrice',p_unit_purchase_price,'freightCost',p_freight_cost,'customsCost',p_customs_cost,'insuranceCost',p_insurance_cost,'otherCost',p_other_cost,'landedCostTotal',v_extra,'finalUnitCost',v_unit,'totalCost',v_total,'receiptDate',v_now,'notes',p_notes,'createdAt',v_now),auth.uid(),auth.uid());
 perform public.erp_inventory_insert_movement(p_company_id,p_product_id,p_warehouse_id,'purchase_in',p_quantity,v_unit,'inventory_receipt',v_id,p_notes);
 perform public.erp_inventory_refresh_product(p_company_id,p_product_id);
 update public.erp_inventory set data=data||jsonb_build_object('purchasePrice',p_unit_purchase_price,'landedCost',v_extra/p_quantity,'updatedAt',v_now) where company_id=p_company_id and id=p_product_id;
 return v_id;
end $$;

create or replace function public.erp_transfer_inventory_stock(
 p_company_id uuid,p_product_id text,p_from_warehouse_id text,p_to_warehouse_id text,p_quantity integer,p_notes text default null
) returns text language plpgsql security definer set search_path=public as $$
declare v_from public.erp_warehouse_stock%rowtype; v_to public.erp_warehouse_stock%rowtype; v_id text:=gen_random_uuid()::text; v_item text:=gen_random_uuid()::text; v_now timestamptz:=now(); v_available numeric; v_cost numeric; v_to_qty numeric; v_to_avg numeric; v_new_avg numeric;
begin
 if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
 if p_from_warehouse_id=p_to_warehouse_id then raise exception 'يجب اختيار مخزنين مختلفين'; end if; if p_quantity<=0 then raise exception 'يجب أن تكون الكمية أكبر من صفر'; end if;
 v_from:=public.erp_inventory_ensure_stock(p_company_id,p_from_warehouse_id,p_product_id); v_available:=coalesce((v_from.data->>'quantity')::numeric,0); if v_available<p_quantity then raise exception 'الرصيد المتوفر في مخزن المصدر غير كافٍ'; end if;
 v_cost:=coalesce((v_from.data->>'averageUnitCost')::numeric,0); v_to:=public.erp_inventory_ensure_stock(p_company_id,p_to_warehouse_id,p_product_id); v_to_qty:=coalesce((v_to.data->>'quantity')::numeric,0); v_to_avg:=coalesce((v_to.data->>'averageUnitCost')::numeric,0); v_new_avg:=((v_to_qty*v_to_avg)+(p_quantity*v_cost))/(v_to_qty+p_quantity);
 insert into public.erp_warehouse_transfers(company_id,id,data,created_by,updated_by) values(p_company_id,v_id,jsonb_build_object('transferNumber','TR-'||(extract(epoch from v_now)*1000000)::bigint,'fromWarehouseId',p_from_warehouse_id,'toWarehouseId',p_to_warehouse_id,'transferDate',v_now,'status','completed','notes',p_notes,'createdAt',v_now),auth.uid(),auth.uid());
 insert into public.erp_warehouse_transfer_items(company_id,id,data,created_by,updated_by) values(p_company_id,v_item,jsonb_build_object('transferId',v_id,'productId',p_product_id,'quantity',p_quantity,'unitCost',v_cost),auth.uid(),auth.uid());
 update public.erp_warehouse_stock set data=data||jsonb_build_object('quantity',(v_available-p_quantity)::int,'updatedAt',v_now) where company_id=p_company_id and id=v_from.id;
 update public.erp_warehouse_stock set data=data||jsonb_build_object('quantity',(v_to_qty+p_quantity)::int,'averageUnitCost',v_new_avg,'updatedAt',v_now) where company_id=p_company_id and id=v_to.id;
 perform public.erp_inventory_insert_movement(p_company_id,p_product_id,p_from_warehouse_id,'transfer_out',-p_quantity,v_cost,'warehouse_transfer',v_id,p_notes);
 perform public.erp_inventory_insert_movement(p_company_id,p_product_id,p_to_warehouse_id,'transfer_in',p_quantity,v_cost,'warehouse_transfer',v_id,p_notes);
 perform public.erp_inventory_refresh_product(p_company_id,p_product_id); return v_id;
end $$;

create or replace function public.erp_plan_inventory_movement(
 p_company_id uuid,p_product_id text,p_warehouse_id text,p_incoming boolean,p_quantity integer,p_notes text default null
) returns void language plpgsql security definer set search_path=public as $$
declare v_stock public.erp_warehouse_stock%rowtype; v_field text; v_current numeric; v_product public.erp_inventory%rowtype; v_cost numeric;
begin
 if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if; if p_quantity<=0 then raise exception 'يجب أن تكون الكمية المتوقعة أكبر من صفر'; end if;
 select * into v_product from public.erp_inventory where company_id=p_company_id and id=p_product_id and not is_deleted; if not found then raise exception 'المنتج غير موجود'; end if;
 v_stock:=public.erp_inventory_ensure_stock(p_company_id,p_warehouse_id,p_product_id); v_field:=case when p_incoming then 'expectedIncoming' else 'expectedOutgoing' end; v_current:=coalesce((v_stock.data->>v_field)::numeric,0); v_cost:=coalesce((v_product.data->>'unitCost')::numeric,0);
 update public.erp_warehouse_stock set data=jsonb_set(data,array[v_field],to_jsonb((v_current+p_quantity)::int),true)||jsonb_build_object('updatedAt',now()) where company_id=p_company_id and id=v_stock.id;
 perform public.erp_inventory_insert_movement(p_company_id,p_product_id,p_warehouse_id,case when p_incoming then 'expected_in' else 'expected_out' end,case when p_incoming then p_quantity else -p_quantity end,v_cost,'stock_forecast',null,p_notes);
 perform public.erp_inventory_refresh_product(p_company_id,p_product_id);
end $$;

create or replace function public.erp_sell_inventory_stock(
 p_company_id uuid,p_product_id text,p_warehouse_id text,p_quantity integer,p_unit_sale_price numeric,p_customer_name text default null,p_notes text default null
) returns text language plpgsql security definer set search_path=public as $$
declare v_product public.erp_inventory%rowtype; v_stock public.erp_warehouse_stock%rowtype; v_id text:=gen_random_uuid()::text; v_now timestamptz:=now(); v_available numeric; v_expected numeric; v_cost numeric; v_total_sale numeric; v_total_cost numeric;
begin
 if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if; if p_quantity<=0 then raise exception 'يجب أن تكون الكمية أكبر من صفر'; end if; if p_unit_sale_price<0 then raise exception 'سعر البيع غير صحيح'; end if;
 select * into v_product from public.erp_inventory where company_id=p_company_id and id=p_product_id and not is_deleted for update; if not found then raise exception 'المنتج غير موجود'; end if;
 v_stock:=public.erp_inventory_ensure_stock(p_company_id,p_warehouse_id,p_product_id); v_available:=coalesce((v_stock.data->>'quantity')::numeric,0); if v_available<p_quantity then raise exception 'الرصيد المتوفر غير كافٍ'; end if;
 v_expected:=coalesce((v_stock.data->>'expectedOutgoing')::numeric,0); v_cost:=coalesce(nullif((v_stock.data->>'averageUnitCost')::numeric,0),(v_product.data->>'unitCost')::numeric,0); v_total_sale:=p_quantity*p_unit_sale_price; v_total_cost:=p_quantity*v_cost;
 insert into public.erp_inventory_product_sales(company_id,id,data,created_by,updated_by) values(p_company_id,v_id,jsonb_build_object('invoiceNumber','PS-'||(extract(epoch from v_now)*1000000)::bigint,'productId',p_product_id,'productName',v_product.data->>'name','warehouseId',p_warehouse_id,'customerName',p_customer_name,'quantity',p_quantity,'unitSalePrice',p_unit_sale_price,'totalSale',v_total_sale,'unitCost',v_cost,'totalCost',v_total_cost,'profit',v_total_sale-v_total_cost,'saleDate',v_now,'notes',p_notes,'createdAt',v_now),auth.uid(),auth.uid());
 update public.erp_warehouse_stock set data=data||jsonb_build_object('quantity',(v_available-p_quantity)::int,'expectedOutgoing',greatest(v_expected-p_quantity,0)::int,'updatedAt',v_now) where company_id=p_company_id and id=v_stock.id;
 perform public.erp_inventory_insert_movement(p_company_id,p_product_id,p_warehouse_id,'sale_out',-p_quantity,v_cost,'inventory_product_sale',v_id,p_notes); perform public.erp_inventory_refresh_product(p_company_id,p_product_id); return v_id;
end $$;

grant execute on function public.erp_create_inventory_product(uuid,text,jsonb,text,integer,jsonb,text) to authenticated;
grant execute on function public.erp_delete_inventory_product(uuid,text) to authenticated;
grant execute on function public.erp_receive_inventory_stock(uuid,text,text,integer,numeric,numeric,numeric,numeric,numeric,text,text,text) to authenticated;
grant execute on function public.erp_transfer_inventory_stock(uuid,text,text,text,integer,text) to authenticated;
grant execute on function public.erp_plan_inventory_movement(uuid,text,text,boolean,integer,text) to authenticated;
grant execute on function public.erp_sell_inventory_stock(uuid,text,text,integer,numeric,text,text) to authenticated;

do $$ declare t text; begin
  foreach t in array array['erp_inventory','erp_inventory_groups','erp_warehouse_stock','erp_product_images','erp_inventory_movements','erp_warehouse_transfers','erp_warehouse_transfer_items','erp_inventory_receipts','erp_inventory_product_sales'] loop
    begin execute format('alter publication supabase_realtime add table public.%I',t); exception when duplicate_object then null; when undefined_object then null; end;
  end loop;
end $$;

commit;
