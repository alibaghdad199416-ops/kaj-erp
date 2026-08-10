-- Stage 1 completion + Stage 2 accounting rules.
-- Adds per-item inventory asset/COGS assignments and service-item enforcement.

create or replace function public.erp_assert_account_type_currency(
  p_company_id uuid,
  p_account_id text,
  p_required_type text,
  p_currency text
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_account public.erp_accounts%rowtype;
begin
  if nullif(btrim(coalesce(p_account_id, '')), '') is null then
    raise exception 'يجب اختيار الحساب المحاسبي المطلوب';
  end if;

  select * into v_account
  from public.erp_accounts
  where organization_id = p_company_id
    and account_id = p_account_id
    and is_active
  limit 1;

  if not found then
    raise exception 'الحساب المحدد غير موجود أو غير فعال';
  end if;
  if lower(v_account.account_type) <> lower(p_required_type) then
    raise exception 'نوع الحساب غير صحيح. النوع المطلوب: %', p_required_type;
  end if;
  if upper(coalesce(v_account.currency, '')) <> upper(coalesce(p_currency, '')) then
    raise exception 'عملة الحساب يجب أن تطابق عملة المادة أو السيارة';
  end if;
end;
$$;

create or replace function public.erp_validate_inventory_master_accounts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type text := lower(coalesce(new.data->>'itemType', new.data->>'item_type', new.data->>'productType', 'stock'));
  v_currency text := upper(coalesce(new.data->>'currency', 'IQD'));
  v_asset text := nullif(coalesce(new.data->>'inventoryAssetAccountId', new.data->>'inventory_asset_account_id'), '');
  v_expense text := nullif(coalesce(new.data->>'salesCostExpenseAccountId', new.data->>'sales_cost_expense_account_id'), '');
begin
  if tg_table_name = 'erp_inventory' and v_type = 'service' then
    new.data := new.data || jsonb_build_object(
      'itemType', 'service',
      'item_type', 'service',
      'productType', 'service',
      'quantity', 0,
      'minQuantity', 0,
      'minimumQuantity', 0,
      'purchasePrice', 0,
      'unitCost', 0,
      'isPurchasable', false,
      'trackInventory', false
    );
    return new;
  end if;

  perform public.erp_assert_account_type_currency(new.company_id, v_asset, 'asset', v_currency);
  perform public.erp_assert_account_type_currency(new.company_id, v_expense, 'expense', v_currency);
  new.data := new.data || jsonb_build_object(
    'inventoryAssetAccountId', v_asset,
    'inventory_asset_account_id', v_asset,
    'salesCostExpenseAccountId', v_expense,
    'sales_cost_expense_account_id', v_expense
  );
  return new;
end;
$$;

drop trigger if exists erp_inventory_master_accounts_guard on public.erp_inventory;
create trigger erp_inventory_master_accounts_guard
before insert or update of data on public.erp_inventory
for each row execute function public.erp_validate_inventory_master_accounts();

drop trigger if exists erp_car_master_accounts_guard on public.erp_cars;
create trigger erp_car_master_accounts_guard
before insert or update of data on public.erp_cars
for each row execute function public.erp_validate_inventory_master_accounts();

-- Service items must never create stock rows or purchase receipt movements.
create or replace function public.erp_reject_service_stock_movement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type text;
begin
  select lower(coalesce(data->>'itemType', data->>'item_type', data->>'productType', 'stock'))
    into v_type
  from public.erp_inventory
  where company_id = new.company_id and id = coalesce(new.data->>'productId', new.data->>'product_id')
    and not is_deleted
  limit 1;

  if v_type = 'service' then
    raise exception 'الخدمة غير مخزنية ولا يمكن إنشاء حركة أو رصيد مخزني لها';
  end if;
  return new;
end;
$$;

drop trigger if exists erp_service_stock_guard on public.erp_warehouse_stock;
create trigger erp_service_stock_guard
before insert or update of data on public.erp_warehouse_stock
for each row execute function public.erp_reject_service_stock_movement();

drop trigger if exists erp_service_movement_guard on public.erp_inventory_movements;
create trigger erp_service_movement_guard
before insert or update of data on public.erp_inventory_movements
for each row execute function public.erp_reject_service_stock_movement();

-- Returns the exact accounts to use for inventory purchase/sale/scrap postings.
create or replace function public.erp_inventory_posting_accounts(
  p_company_id uuid,
  p_item_kind text,
  p_item_id text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_data jsonb;
  v_currency text;
  v_asset text;
  v_expense text;
begin
  if lower(p_item_kind) in ('car','vehicle') then
    select data into v_data from public.erp_cars
    where company_id=p_company_id and id=p_item_id and not is_deleted limit 1;
  else
    select data into v_data from public.erp_inventory
    where company_id=p_company_id and id=p_item_id and not is_deleted limit 1;
  end if;

  if v_data is null then raise exception 'المادة أو السيارة غير موجودة'; end if;
  v_currency := upper(coalesce(v_data->>'currency','IQD'));
  v_asset := nullif(coalesce(v_data->>'inventoryAssetAccountId',v_data->>'inventory_asset_account_id'),'');
  v_expense := nullif(coalesce(v_data->>'salesCostExpenseAccountId',v_data->>'sales_cost_expense_account_id'),'');
  perform public.erp_assert_account_type_currency(p_company_id,v_asset,'asset',v_currency);
  perform public.erp_assert_account_type_currency(p_company_id,v_expense,'expense',v_currency);

  return jsonb_build_object(
    'currency',v_currency,
    'purchaseDebitAccountId',v_asset,
    'saleCreditAccountId',v_asset,
    'saleDebitExpenseAccountId',v_expense,
    'scrapCreditAccountId',v_asset
  );
end;
$$;

grant execute on function public.erp_assert_account_type_currency(uuid,text,text,text) to authenticated;
grant execute on function public.erp_inventory_posting_accounts(uuid,text,text) to authenticated;

-- Service-aware creation: no warehouse stock row and no opening movement.
create or replace function public.erp_create_inventory_product(
  p_company_id uuid,p_product_id text,p_product jsonb,p_warehouse_id text,
  p_opening_quantity integer,p_images jsonb,p_user_name text
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_now timestamptz:=now(); v_image text; v_index int:=0;
  v_type text:=lower(coalesce(p_product->>'itemType',p_product->>'item_type',p_product->>'productType','stock'));
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if v_type not in ('stock','service') then raise exception 'نوع المادة غير صالح'; end if;
  if v_type='service' then
    p_opening_quantity:=0;
    p_product:=p_product||jsonb_build_object(
      'itemType','service','item_type','service','productType','service',
      'quantity',0,'minQuantity',0,'purchasePrice',0,'unitCost',0,
      'isPurchasable',false,'trackInventory',false
    );
  elsif p_warehouse_id is null or btrim(p_warehouse_id)='' then
    raise exception 'يجب اختيار مخزن للمادة المخزنية';
  end if;
  if p_opening_quantity<0 then raise exception 'الرصيد الافتتاحي غير صحيح'; end if;
  if exists(select 1 from public.erp_inventory where company_id=p_company_id and not is_deleted and lower(data->>'code')=lower(p_product->>'code') and coalesce(data->>'code','')<>'') then
    raise exception 'رمز المنتج مستخدم مسبقاً';
  end if;
  insert into public.erp_inventory(company_id,id,data,created_by,updated_by)
  values(p_company_id,p_product_id,p_product||jsonb_build_object('quantity',p_opening_quantity,'createdAt',v_now,'updatedAt',v_now),auth.uid(),auth.uid());
  if v_type='stock' then
    insert into public.erp_warehouse_stock(company_id,id,data,created_by,updated_by)
    values(p_company_id,p_warehouse_id||'::'||p_product_id,jsonb_build_object(
      'warehouseId',p_warehouse_id,'productId',p_product_id,'quantity',p_opening_quantity,
      'reservedQuantity',0,'expectedIncoming',0,'expectedOutgoing',0,
      'averageUnitCost',coalesce((p_product->>'unitCost')::numeric,0),'updatedAt',v_now
    ),auth.uid(),auth.uid());
    if p_opening_quantity>0 then
      perform public.erp_inventory_insert_movement(p_company_id,p_product_id,p_warehouse_id,'opening',p_opening_quantity,coalesce((p_product->>'unitCost')::numeric,0),'product_opening',p_product_id,'رصيد افتتاحي للمنتج');
    end if;
  end if;
  if jsonb_typeof(p_images)='array' then
    for v_image in select jsonb_array_elements_text(p_images) loop
      insert into public.erp_product_images(company_id,id,data,created_by,updated_by)
      values(p_company_id,gen_random_uuid()::text,jsonb_build_object('productId',p_product_id,'imageBase64',v_image,'sortOrder',v_index,'createdAt',v_now),auth.uid(),auth.uid());
      v_index:=v_index+1;
    end loop;
  end if;
end $$;

grant execute on function public.erp_create_inventory_product(uuid,text,jsonb,text,integer,jsonb,text) to authenticated;
