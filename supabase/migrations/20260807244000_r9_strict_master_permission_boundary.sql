-- R9 final permission boundary: fail closed for unknown JSON business fields,
-- require the module permission before SECURITY DEFINER master reads/writes,
-- and make the guarded R9 master RPCs the only authenticated generic write path.
begin;

create or replace function public.erp_r9_master_required_permission(
  p_table text,
  p_action text
) returns text
language sql
immutable
as $$
  select case trim(coalesce(p_table,''))
    when 'erp_cars' then 'cars.'||trim(coalesce(p_action,''))
    when 'erp_car_images' then 'cars.'||trim(coalesce(p_action,''))
    when 'erp_customers' then 'customers.'||trim(coalesce(p_action,''))
    when 'erp_suppliers' then 'suppliers.'||trim(coalesce(p_action,''))
    when 'erp_warehouses' then 'warehouses.'||trim(coalesce(p_action,''))
    when 'erp_inventory' then 'inventory.'||trim(coalesce(p_action,''))
    when 'erp_inventory_groups' then 'inventory.'||trim(coalesce(p_action,''))
    when 'erp_product_images' then 'inventory.'||trim(coalesce(p_action,''))
    when 'erp_car_warehouse_transfers' then case trim(coalesce(p_action,''))
      when 'view' then 'inventory.view'
      when 'delete' then 'cars.transfer.delete'
      else 'inventory.transfer' end
    when 'erp_warehouse_transfers' then case trim(coalesce(p_action,''))
      when 'view' then 'inventory.view'
      when 'delete' then 'inventory.transfer.delete'
      else 'inventory.transfer' end
    when 'erp_warehouse_transfer_items' then case trim(coalesce(p_action,''))
      when 'view' then 'inventory.view'
      when 'delete' then 'inventory.transfer.delete'
      else 'inventory.transfer' end
    when 'erp_warehouse_stock' then 'inventory.view'
    when 'erp_inventory_movements' then 'inventory.view'
    when 'erp_cash_accounts' then 'accounting.view'
    when 'erp_cash_transactions' then 'accounting.view'
    when 'erp_expenses' then 'accounting.view'
    when 'erp_journal_entries' then 'accounting.view'
    when 'erp_installments' then 'installments.view'
    when 'erp_sales' then 'sales.view'
    when 'erp_purchases' then 'purchases.view'
    when 'erp_purchase_items' then 'purchases.view'
    else null
  end
$$;

-- Table-aware mapping resolves ambiguous JSON keys such as `type`, and maps
-- all business keys used by the current Flutter models. A NULL result is a
-- deliberate deny in restricted mode, not an implicit metadata allow.
create or replace function public.erp_r9_master_field_for_table_key(
  p_table text,
  p_key text
) returns text
language plpgsql
immutable
as $$
declare
  v_table text := trim(coalesce(p_table,''));
  v_key text := trim(coalesce(p_key,''));
  v_resource text;
  v_field text;
begin
  v_resource := public.erp_r9_master_resource_for_table(v_table);
  if v_resource is null then return null; end if;

  v_field := case v_table
    when 'erp_cars' then case v_key
      when 'maintenanceCost' then 'maintenanceCost'
      when 'maintenance_cost' then 'maintenanceCost'
      when 'updatedAt' then 'auditMetadata'
      when 'updated_at' then 'auditMetadata'
      when 'schemaVersion' then 'auditMetadata'
      when 'schema_version' then 'auditMetadata'
      else null end
    when 'erp_car_images' then case v_key
      when 'carId' then 'images'
      when 'car_id' then 'images'
      when 'imageBase64' then 'images'
      when 'image_base64' then 'images'
      when 'sortOrder' then 'images'
      when 'sort_order' then 'images'
      when 'createdAt' then 'images'
      when 'created_at' then 'images'
      else null end
    when 'erp_customers' then case v_key
      when 'createdAt' then 'createdAt'
      when 'created_at' then 'createdAt'
      when 'accountIdIqd' then 'accountIqd'
      when 'account_id_iqd' then 'accountIqd'
      when 'accountIdUsd' then 'accountUsd'
      when 'account_id_usd' then 'accountUsd'
      when 'ledgerAccountId' then 'accountUsd'
      when 'ledger_account_id' then 'accountUsd'
      when 'schemaVersion' then 'createdAt'
      when 'schema_version' then 'createdAt'
      else null end
    when 'erp_suppliers' then case v_key
      when 'createdAt' then 'createdAt'
      when 'created_at' then 'createdAt'
      when 'updatedAt' then 'updatedAt'
      when 'updated_at' then 'updatedAt'
      when 'accountIdIqd' then 'accountIqd'
      when 'account_id_iqd' then 'accountIqd'
      when 'accountIdUsd' then 'accountUsd'
      when 'account_id_usd' then 'accountUsd'
      when 'ledgerAccountId' then 'accountUsd'
      when 'ledger_account_id' then 'accountUsd'
      when 'schemaVersion' then 'updatedAt'
      when 'schema_version' then 'updatedAt'
      else null end
    when 'erp_warehouses' then case v_key
      when 'createdAt' then 'createdAt'
      when 'created_at' then 'createdAt'
      else null end
    when 'erp_inventory' then case v_key
      when 'createdAt' then 'date'
      when 'created_at' then 'date'
      when 'updatedAt' then 'auditMetadata'
      when 'updated_at' then 'auditMetadata'
      when 'schemaVersion' then 'auditMetadata'
      when 'schema_version' then 'auditMetadata'
      else null end
    when 'erp_inventory_groups' then case v_key
      when 'createdAt' then 'date'
      when 'created_at' then 'date'
      else null end
    when 'erp_product_images' then case v_key
      when 'productId' then 'image'
      when 'product_id' then 'image'
      when 'imageBase64' then 'image'
      when 'image_base64' then 'image'
      when 'sortOrder' then 'image'
      when 'sort_order' then 'image'
      when 'createdAt' then 'image'
      when 'created_at' then 'image'
      else null end
    when 'erp_warehouse_stock' then case v_key
      when 'productId' then 'transferItem'
      when 'product_id' then 'transferItem'
      when 'inventoryId' then 'transferItem'
      when 'inventory_id' then 'transferItem'
      when 'warehouseId' then 'warehouseId'
      when 'warehouse_id' then 'warehouseId'
      when 'quantity' then 'quantity'
      when 'reservedQuantity' then 'quantity'
      when 'reserved_quantity' then 'quantity'
      when 'expectedIncoming' then 'expectedIncoming'
      when 'expected_incoming' then 'expectedIncoming'
      when 'expectedOutgoing' then 'expectedOutgoing'
      when 'expected_outgoing' then 'expectedOutgoing'
      when 'averageUnitCost' then 'unitCost'
      when 'average_unit_cost' then 'unitCost'
      when 'unitCost' then 'unitCost'
      when 'unit_cost' then 'unitCost'
      when 'updatedAt' then 'auditMetadata'
      when 'updated_at' then 'auditMetadata'
      else null end
    when 'erp_inventory_movements' then case v_key
      when 'movementNumber' then 'movementNumber'
      when 'movement_number' then 'movementNumber'
      when 'productId' then 'transferItem'
      when 'product_id' then 'transferItem'
      when 'warehouseId' then 'warehouseId'
      when 'warehouse_id' then 'warehouseId'
      when 'movementType' then 'movementType'
      when 'movement_type' then 'movementType'
      when 'quantity' then 'quantity'
      when 'unitCost' then 'movementCost'
      when 'unit_cost' then 'movementCost'
      when 'totalCost' then 'movementCost'
      when 'total_cost' then 'movementCost'
      when 'movementDate' then 'operationalDate'
      when 'movement_date' then 'operationalDate'
      when 'referenceType' then 'movementReference'
      when 'reference_type' then 'movementReference'
      when 'referenceId' then 'movementReference'
      when 'reference_id' then 'movementReference'
      when 'notes' then 'notes'
      when 'createdAt' then 'auditMetadata'
      when 'created_at' then 'auditMetadata'
      else null end
    when 'erp_car_warehouse_transfers' then case v_key
      when 'transferNumber' then 'movementNumber'
      when 'transfer_number' then 'movementNumber'
      when 'carId' then 'transferItem'
      when 'car_id' then 'transferItem'
      when 'fromWarehouseId' then 'sourceWarehouseId'
      when 'from_warehouse_id' then 'sourceWarehouseId'
      when 'toWarehouseId' then 'destinationWarehouseId'
      when 'to_warehouse_id' then 'destinationWarehouseId'
      when 'transferDate' then 'operationalDate'
      when 'transfer_date' then 'operationalDate'
      when 'effectiveAt' then 'operationalDate'
      when 'effective_at' then 'operationalDate'
      when 'status' then 'movementType'
      when 'notes' then 'transferNotes'
      when 'createdAt' then 'auditMetadata'
      when 'created_at' then 'auditMetadata'
      when 'updatedAt' then 'auditMetadata'
      when 'updated_at' then 'auditMetadata'
      when 'createdByUserId' then 'auditMetadata'
      when 'createdByUserName' then 'auditMetadata'
      when 'updatedByUserId' then 'auditMetadata'
      when 'updatedByUserName' then 'auditMetadata'
      when 'reversedAt' then 'auditMetadata'
      when 'reversedByUserId' then 'auditMetadata'
      when 'reversedByUserName' then 'auditMetadata'
      else null end
    when 'erp_warehouse_transfers' then case v_key
      when 'transferNumber' then 'movementNumber'
      when 'transfer_number' then 'movementNumber'
      when 'fromWarehouseId' then 'sourceWarehouseId'
      when 'from_warehouse_id' then 'sourceWarehouseId'
      when 'toWarehouseId' then 'destinationWarehouseId'
      when 'to_warehouse_id' then 'destinationWarehouseId'
      when 'transferDate' then 'operationalDate'
      when 'transfer_date' then 'operationalDate'
      when 'effectiveAt' then 'operationalDate'
      when 'effective_at' then 'operationalDate'
      when 'notes' then 'transferNotes'
      when 'status' then 'movementType'
      when 'createdAt' then 'auditMetadata'
      when 'created_at' then 'auditMetadata'
      when 'updatedAt' then 'auditMetadata'
      when 'updated_at' then 'auditMetadata'
      else null end
    when 'erp_warehouse_transfer_items' then case v_key
      when 'transferId' then 'movementReference'
      when 'transfer_id' then 'movementReference'
      when 'productId' then 'transferItem'
      when 'product_id' then 'transferItem'
      when 'quantity' then 'transferQuantity'
      when 'notes' then 'transferNotes'
      else null end
    when 'erp_cash_accounts' then case v_key
      when 'type' then 'type'
      when 'createdAt' then 'auditMetadata'
      when 'created_at' then 'auditMetadata'
      when 'updatedAt' then 'auditMetadata'
      when 'updated_at' then 'auditMetadata'
      when 'schemaVersion' then 'auditMetadata'
      when 'schema_version' then 'auditMetadata'
      else null end
    when 'erp_cash_transactions' then case v_key
      when 'type' then 'transactionType'
      when 'partyId' then 'partyId'
      when 'party_id' then 'partyId'
      when 'paymentMethod' then 'paymentMethod'
      when 'payment_method' then 'paymentMethod'
      when 'referenceType' then 'reference'
      when 'reference_type' then 'reference'
      when 'referenceId' then 'reference'
      when 'reference_id' then 'reference'
      when 'journalEntryId' then 'journalEntryId'
      when 'journal_entry_id' then 'journalEntryId'
      when 'createdAt' then 'auditMetadata'
      when 'created_at' then 'auditMetadata'
      when 'updatedAt' then 'auditMetadata'
      when 'updated_at' then 'auditMetadata'
      else null end
    when 'erp_expenses' then case v_key
      when 'branchId' then 'branchId'
      when 'branch_id' then 'branchId'
      when 'exchangeRate' then 'exchangeRate'
      when 'exchange_rate' then 'exchangeRate'
      when 'amountUsd' then 'convertedAmounts'
      when 'amount_usd' then 'convertedAmounts'
      when 'amountIqd' then 'convertedAmounts'
      when 'amount_iqd' then 'convertedAmounts'
      when 'journalEntryId' then 'journalEntryId'
      when 'journal_entry_id' then 'journalEntryId'
      else null end
    when 'erp_sales' then case v_key
      when 'carId' then 'carId'
      when 'car_id' then 'carId'
      when 'sellerCustomerId' then 'customerId'
      when 'seller_customer_id' then 'customerId'
      when 'saleType' then 'saleType'
      when 'sale_type' then 'saleType'
      when 'previousSaleId' then 'previousSaleId'
      when 'previous_sale_id' then 'previousSaleId'
      when 'createdByUserId' then 'createdBy'
      when 'createdByUserName' then 'createdBy'
      when 'created_at' then 'createdAt'
      when 'createdAt' then 'createdAt'
      when 'updated_at' then 'updatedAt'
      when 'updatedAt' then 'updatedAt'
      when 'saleSequence' then 'orderNumber'
      when 'sale_sequence' then 'orderNumber'
      when 'amountUsd' then 'total'
      when 'amount_usd' then 'total'
      when 'amountIqd' then 'total'
      when 'amount_iqd' then 'total'
      else null end
    else null
  end;

  if v_field is not null then return v_field; end if;
  return public.erp_r9_logical_field_for_json_key(v_resource,v_key);
end;
$$;

-- Generic payload filtering is also fail-closed. This protects the users
-- snapshot, while table-aware reads below use the stricter table mapper.
create or replace function public.erp_r9_filter_readable_json(
  p_company_id uuid,
  p_resource text,
  p_payload jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_result jsonb := '{}'::jsonb;
  v_item record;
  v_field text;
begin
  if p_payload is null then return '{}'::jsonb; end if;
  if not public.erp_cloud_user_has_permission(p_company_id,trim(p_resource)||'.fields.restrict') then
    return p_payload;
  end if;
  for v_item in select key,value from jsonb_each(p_payload) loop
    if v_item.key='id' then
      v_result := v_result || jsonb_build_object(v_item.key,v_item.value);
      continue;
    end if;
    if trim(coalesce(p_resource,''))='users' and v_item.key in ('createdAt','created_at','updatedAt','updated_at') then
      v_field := 'auditMetadata';
    else
      v_field := public.erp_r9_logical_field_for_json_key(p_resource,v_item.key);
    end if;
    if v_field is not null
       and public.erp_cloud_user_can_view_field(p_company_id,p_resource,v_field,null) then
      v_result := v_result || jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r9_filter_readable_master_json(
  p_company_id uuid,
  p_table text,
  p_payload jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_resource text := public.erp_r9_master_resource_for_table(p_table);
  v_result jsonb := '{}'::jsonb;
  v_item record;
  v_field text;
begin
  if v_resource is null then raise exception 'unsupported_master_table:%',p_table; end if;
  if p_payload is null then return '{}'::jsonb; end if;
  if not public.erp_cloud_user_has_permission(p_company_id,v_resource||'.fields.restrict') then
    return p_payload;
  end if;
  for v_item in select key,value from jsonb_each(p_payload) loop
    v_field := public.erp_r9_master_field_for_table_key(p_table,v_item.key);
    if v_field is not null
       and public.erp_cloud_user_can_view_field(p_company_id,v_resource,v_field,null) then
      v_result := v_result || jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r9_guard_writable_master_json(
  p_company_id uuid,
  p_table text,
  p_existing jsonb,
  p_incoming jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_resource text := public.erp_r9_master_resource_for_table(p_table);
  v_result jsonb := coalesce(p_incoming,'{}'::jsonb);
  v_item record;
  v_field text;
begin
  if v_resource is null then raise exception 'unsupported_master_table:%',p_table; end if;
  if not public.erp_cloud_user_has_permission(p_company_id,v_resource||'.fields.restrict') then
    return v_result;
  end if;

  -- Unknown keys are default-deny. Existing unknown keys are immutable and
  -- retained for compatibility; new unknown keys are removed.
  for v_item in select key,value from jsonb_each(coalesce(p_incoming,'{}'::jsonb)) loop
    v_field := public.erp_r9_master_field_for_table_key(p_table,v_item.key);
    if v_field is null
       or not public.erp_cloud_user_can_edit_field(p_company_id,v_resource,v_field,null) then
      if coalesce(p_existing,'{}'::jsonb) ? v_item.key then
        v_result := jsonb_set(v_result,array[v_item.key],p_existing->v_item.key,true);
      else
        v_result := v_result - v_item.key;
      end if;
    end if;
  end loop;

  for v_item in select key,value from jsonb_each(coalesce(p_existing,'{}'::jsonb)) loop
    v_field := public.erp_r9_master_field_for_table_key(p_table,v_item.key);
    if (v_field is null
        or not public.erp_cloud_user_can_edit_field(p_company_id,v_resource,v_field,null))
       and not (v_result ? v_item.key) then
      v_result := v_result || jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r9_master_field_write_guard()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if public.erp_r9_master_resource_for_table(tg_table_name) is null then return new; end if;
  new.data := public.erp_r9_guard_writable_master_json(
    new.company_id,
    tg_table_name,
    case when tg_op='UPDATE' then old.data else '{}'::jsonb end,
    new.data
  );
  return new;
end;
$$;

-- Reattach the strict guard to every JSON table reachable through the generic
-- master reader and to generated inventory/cash compatibility tables.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses',
    'erp_inventory','erp_inventory_groups','erp_product_images',
    'erp_car_warehouse_transfers','erp_warehouse_transfers','erp_warehouse_transfer_items',
    'erp_warehouse_stock','erp_inventory_movements','erp_cash_accounts','erp_cash_transactions',
    'erp_expenses','erp_journal_entries','erp_installments','erp_sales','erp_purchases','erp_purchase_items'
  ] loop
    if to_regclass('public.'||v_table) is not null then
      execute format('drop trigger if exists aa_r9_field_write_guard on public.%I',v_table);
      execute format('create trigger aa_r9_field_write_guard before insert or update of data on public.%I for each row execute function public.erp_r9_master_field_write_guard()',v_table);
    end if;
  end loop;
end $$;

create or replace function public.erp_r9_list_cloud_master_records(
  p_company_id uuid,
  p_table text
) returns setof jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_permission text;
  v_row record;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if public.erp_r9_master_resource_for_table(p_table) is null then
    raise exception 'unsupported_master_table:%',p_table;
  end if;
  v_permission := public.erp_r9_master_required_permission(p_table,'view');
  if v_permission is null
     or (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
         and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.view') using errcode='42501';
  end if;

  for v_row in execute format(
    'select id,data,version,updated_at from public.%I where company_id=$1 and not is_deleted order by updated_at desc',
    p_table
  ) using p_company_id loop
    return next public.erp_r9_filter_readable_master_json(p_company_id,p_table,v_row.data)
      || jsonb_build_object('id',v_row.id,'_cloudVersion',v_row.version,'_cloudUpdatedAt',v_row.updated_at);
  end loop;
  return;
end;
$$;

create or replace function public.erp_r9_get_cloud_master_record(
  p_company_id uuid,
  p_table text,
  p_record_id text
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_permission text;
  v_row record;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if public.erp_r9_master_resource_for_table(p_table) is null then
    raise exception 'unsupported_master_table:%',p_table;
  end if;
  v_permission := public.erp_r9_master_required_permission(p_table,'view');
  if v_permission is null
     or (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
         and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.view') using errcode='42501';
  end if;

  execute format(
    'select id,data,version,updated_at from public.%I where company_id=$1 and id=$2 and not is_deleted limit 1',
    p_table
  ) into v_row using p_company_id,p_record_id;
  if not found then return null; end if;
  return public.erp_r9_filter_readable_master_json(p_company_id,p_table,v_row.data)
    || jsonb_build_object('id',v_row.id,'_cloudVersion',v_row.version,'_cloudUpdatedAt',v_row.updated_at);
end;
$$;

-- Guarded generic writes. This intentionally excludes transfer/history tables;
-- those may only be mutated through their atomic workflow RPCs.
create or replace function public.erp_r9_upsert_cloud_master_record(
  p_company_id uuid,
  p_table text,
  p_record_id text,
  p_data jsonb,
  p_expected_version bigint default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_existing_version bigint;
  v_existing_data jsonb := '{}'::jsonb;
  v_action text;
  v_permission text;
  v_guarded jsonb;
  v_branch_id text;
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if p_table not in (
    'erp_cars','erp_customers','erp_suppliers','erp_car_images',
    'erp_warehouses','erp_inventory','erp_inventory_groups'
  ) then
    raise exception 'unsupported_master_write_table:%',p_table;
  end if;
  if coalesce(btrim(p_record_id),'')='' or p_data is null then
    raise exception 'invalid_master_record';
  end if;

  execute format(
    'select version,data from public.%I where company_id=$1 and id=$2 for update',p_table
  ) into v_existing_version,v_existing_data using p_company_id,p_record_id;
  v_action := case when v_existing_version is null then 'create' else 'update' end;
  v_permission := public.erp_r9_master_required_permission(p_table,v_action);
  if v_permission is null
     or (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
         and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.'||v_action) using errcode='42501';
  end if;
  if p_expected_version is not null and v_existing_version is not null
     and v_existing_version<>p_expected_version then
    raise exception 'stale_master_record' using errcode='40001';
  end if;

  v_guarded := public.erp_r9_guard_writable_master_json(
    p_company_id,p_table,coalesce(v_existing_data,'{}'::jsonb),
    p_data - '_cloudVersion' - '_cloudUpdatedAt'
  );

  if p_table in ('erp_customers','erp_suppliers') then
    if coalesce(btrim(v_guarded->>'name'),'')='' then raise exception 'partner_name_required'; end if;
  elsif p_table='erp_warehouses' then
    if coalesce(btrim(v_guarded->>'code'),'')='' or coalesce(btrim(v_guarded->>'name'),'')='' then
      raise exception 'warehouse_code_and_name_required';
    end if;
    v_branch_id := nullif(btrim(v_guarded->>'branchId'),'');
    if v_branch_id is not null and not exists(
      select 1 from public.branches where company_id=p_company_id and id=v_branch_id::uuid and is_active
    ) then raise exception 'warehouse_branch_not_found'; end if;
    if exists(
      select 1 from public.erp_warehouses
      where company_id=p_company_id and id<>p_record_id and not is_deleted
        and lower(btrim(data->>'code'))=lower(btrim(v_guarded->>'code'))
    ) then raise exception 'warehouse_code_already_exists'; end if;
  elsif p_table='erp_inventory_groups' then
    if coalesce(btrim(v_guarded->>'code'),'')='' or coalesce(btrim(v_guarded->>'name'),'')='' then
      raise exception 'inventory_group_code_and_name_required';
    end if;
  end if;

  execute format(
    'insert into public.%I(company_id,id,data,created_by,updated_by,is_deleted,deleted_at) '
    ||'values($1,$2,$3,$4,$4,false,null) '
    ||'on conflict(company_id,id) do update set data=excluded.data,updated_by=$4,is_deleted=false,deleted_at=null '
    ||'returning jsonb_build_object(''id'',id,''version'',version,''updatedAt'',updated_at)',p_table
  ) into v_result using
    p_company_id,p_record_id,v_guarded||jsonb_build_object('id',p_record_id),auth.uid();
  return v_result;
end;
$$;

create or replace function public.erp_r9_soft_delete_cloud_master_record(
  p_company_id uuid,
  p_table text,
  p_record_id text,
  p_expected_version bigint default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_version bigint;
  v_permission text;
  v_now timestamptz := now();
  v_result jsonb;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if p_table not in (
    'erp_cars','erp_customers','erp_suppliers','erp_car_images',
    'erp_warehouses','erp_inventory','erp_inventory_groups'
  ) then raise exception 'unsupported_master_write_table:%',p_table; end if;
  v_permission := public.erp_r9_master_required_permission(p_table,'delete');
  if v_permission is null
     or (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
         and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.delete') using errcode='42501';
  end if;

  execute format(
    'select version from public.%I where company_id=$1 and id=$2 and not is_deleted for update',p_table
  ) into v_version using p_company_id,p_record_id;
  if v_version is null then raise exception 'master_record_not_found'; end if;
  if p_expected_version is not null and v_version<>p_expected_version then
    raise exception 'stale_master_record' using errcode='40001';
  end if;

  if p_table='erp_warehouses' then
    if exists(select 1 from public.erp_cars where company_id=p_company_id and not is_deleted and coalesce(data->>'warehouse_id',data->>'warehouseId')=p_record_id)
       or exists(select 1 from public.erp_warehouse_stock where company_id=p_company_id and not is_deleted and coalesce(data->>'warehouseId',data->>'warehouse_id')=p_record_id and coalesce(nullif(data->>'quantity','')::numeric,0)<>0) then
      raise exception 'warehouse_has_active_inventory';
    end if;
  elsif p_table='erp_inventory_groups' then
    if exists(select 1 from public.erp_inventory where company_id=p_company_id and not is_deleted and coalesce(data->>'groupId',data->>'group_id')=p_record_id) then
      raise exception 'inventory_group_has_products';
    end if;
  end if;

  execute format(
    'update public.%I set is_deleted=true,deleted_at=$3,updated_by=$4 where company_id=$1 and id=$2 '
    ||'returning jsonb_build_object(''id'',id,''version'',version,''deletedAt'',deleted_at)',p_table
  ) into v_result using p_company_id,p_record_id,v_now,auth.uid();
  return v_result;
end;
$$;

-- Only the R9 masked/guarded generic boundary is callable by authenticated
-- clients. Atomic specialized workflow RPCs continue to own their tables.
revoke all on function public.erp_upsert_cloud_master_record(uuid,text,text,jsonb,bigint) from public,anon,authenticated;
revoke all on function public.erp_soft_delete_cloud_master_record(uuid,text,text,bigint) from public,anon,authenticated;
revoke all on function public.erp_r9_upsert_cloud_master_record(uuid,text,text,jsonb,bigint) from public,anon;
revoke all on function public.erp_r9_soft_delete_cloud_master_record(uuid,text,text,bigint) from public,anon;
grant execute on function public.erp_r9_upsert_cloud_master_record(uuid,text,text,jsonb,bigint) to authenticated,service_role;
grant execute on function public.erp_r9_soft_delete_cloud_master_record(uuid,text,text,bigint) to authenticated,service_role;
revoke all on function public.erp_r9_list_cloud_master_records(uuid,text) from public,anon;
revoke all on function public.erp_r9_get_cloud_master_record(uuid,text,text) from public,anon;
grant execute on function public.erp_r9_list_cloud_master_records(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r9_get_cloud_master_record(uuid,text,text) to authenticated,service_role;

-- Enforce a single fail-closed SELECT boundary per protected JSON table.
-- Any historical permissive SELECT/ALL policy is removed first so an older
-- policy cannot OR-combine with R9 and bypass module/field permissions.
do $$
declare
  v_table text;
  v_resource text;
  v_view_permission text;
  v_policy record;
begin
  foreach v_table in array array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses',
    'erp_inventory','erp_inventory_groups','erp_product_images',
    'erp_car_warehouse_transfers','erp_warehouse_transfers','erp_warehouse_transfer_items',
    'erp_warehouse_stock','erp_inventory_movements','erp_cash_accounts','erp_cash_transactions',
    'erp_expenses','erp_journal_entries','erp_installments','erp_sales','erp_purchases','erp_purchase_items'
  ] loop
    if to_regclass('public.'||v_table) is null then continue; end if;
    v_resource := public.erp_r9_master_resource_for_table(v_table);
    v_view_permission := public.erp_r9_master_required_permission(v_table,'view');
    if v_resource is null or v_view_permission is null then
      raise exception 'r9_permission_mapping_missing:%',v_table;
    end if;

    execute format('alter table public.%I enable row level security',v_table);
    for v_policy in
      select policyname from pg_policies
      where schemaname='public' and tablename=v_table and cmd in ('SELECT','ALL')
    loop
      execute format('drop policy if exists %I on public.%I',v_policy.policyname,v_table);
    end loop;

    execute format(
      'create policy %I on public.%I for select to authenticated using ('||
      'public.is_active_company_member(company_id) and '||
      '(public.erp_cloud_user_has_permission(company_id,%L) or public.is_company_admin(company_id)) and '||
      'not public.erp_cloud_user_has_permission(company_id,%L))',
      v_table||'_r9_strict_select',v_table,v_view_permission,v_resource||'.fields.restrict'
    );
  end loop;
end $$;

-- Direct authenticated DML is revoked to prevent bypass attempts against the
-- generic JSON tables. Writes must use guarded generic RPCs or atomic workflow
-- RPCs, whose SECURITY DEFINER bodies own the accounting/inventory mutation.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers','erp_warehouses',
    'erp_inventory','erp_inventory_groups','erp_product_images',
    'erp_car_warehouse_transfers','erp_warehouse_transfers','erp_warehouse_transfer_items',
    'erp_warehouse_stock','erp_inventory_movements','erp_cash_accounts','erp_cash_transactions',
    'erp_expenses','erp_journal_entries','erp_installments','erp_sales','erp_purchases','erp_purchase_items'
  ] loop
    if to_regclass('public.'||v_table) is not null then
      execute format('revoke insert,update,delete on public.%I from authenticated',v_table);
    end if;
  end loop;
end $$;

notify pgrst,'reload schema';
commit;
