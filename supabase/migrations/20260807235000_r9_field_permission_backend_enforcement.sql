-- R9 complete closure: enforce granular field permissions at the database
-- boundary for normalized JSON master data and access-user snapshots.
-- UI FieldPermissionControl remains the UX layer; these functions/triggers are
-- the authoritative read/write safety net.
begin;

create or replace function public.erp_r9_master_resource_for_table(p_table text)
returns text
language sql
immutable
as $$
  select case trim(coalesce(p_table,''))
    when 'erp_cars' then 'cars'
    when 'erp_car_images' then 'cars'
    when 'erp_customers' then 'customers'
    when 'erp_suppliers' then 'suppliers'
    when 'erp_warehouses' then 'warehouses'
    when 'erp_inventory' then 'inventory'
    when 'erp_inventory_groups' then 'inventory'
    when 'erp_product_images' then 'inventory'
    when 'erp_car_warehouse_transfers' then 'inventory'
    when 'erp_warehouse_transfers' then 'inventory'
    when 'erp_warehouse_transfer_items' then 'inventory'
    when 'erp_warehouse_stock' then 'inventory'
    when 'erp_inventory_movements' then 'inventory'
    when 'erp_cash_accounts' then 'cashbox'
    when 'erp_cash_transactions' then 'cashbox'
    when 'erp_expenses' then 'expenses'
    when 'erp_journal_entries' then 'accounting'
    when 'erp_installments' then 'installments'
    when 'erp_sales' then 'sales'
    when 'erp_purchases' then 'purchases'
    when 'erp_purchase_items' then 'purchases'
    else null
  end
$$;

create or replace function public.erp_r9_logical_field_for_json_key(
  p_resource text,
  p_key text
) returns text
language sql
immutable
as $$
  select case trim(coalesce(p_resource,''))
    when 'users' then case trim(coalesce(p_key,''))
      when 'fullName' then 'fullName'
      when 'username' then 'username'
      when 'email' then 'email'
      when 'phone' then 'phone'
      when 'jobTitle' then 'jobTitle'
      when 'roleId' then 'roleId'
      when 'roleName' then 'roleId'
      when 'isActive' then 'isActive'
      when 'avatarBase64' then 'avatar'
      when 'passwordHash' then 'password'
      when 'cloudAuthUid' then 'auditMetadata'
      when 'authProvider' then 'auditMetadata'
      when 'cloudEmailVerified' then 'auditMetadata'
      when 'lastLoginAt' then 'auditMetadata'
      else null end
    when 'customers' then case trim(coalesce(p_key,''))
      when 'name' then 'name'
      when 'phone' then 'phone'
      when 'address' then 'address'
      when 'nationalId' then 'nationalId'
      when 'national_id' then 'nationalId'
      when 'notes' then 'notes'
      when 'photoBase64' then 'photo'
      when 'photo_base64' then 'photo'
      when 'accountIqd' then 'accountIqd'
      when 'account_iqd' then 'accountIqd'
      when 'accountUsd' then 'accountUsd'
      when 'account_usd' then 'accountUsd'
      else null end
    when 'suppliers' then case trim(coalesce(p_key,''))
      when 'name' then 'name'
      when 'phone' then 'phone'
      when 'alternativePhone' then 'alternativePhone'
      when 'alternative_phone' then 'alternativePhone'
      when 'address' then 'address'
      when 'companyName' then 'companyName'
      when 'company_name' then 'companyName'
      when 'taxNumber' then 'taxNumber'
      when 'tax_number' then 'taxNumber'
      when 'notes' then 'notes'
      when 'openingBalance' then 'openingBalance'
      when 'opening_balance' then 'openingBalance'
      when 'currency' then 'currency'
      when 'isActive' then 'isActive'
      when 'is_active' then 'isActive'
      when 'photoBase64' then 'photo'
      when 'photo_base64' then 'photo'
      when 'accountIqd' then 'accountIqd'
      when 'account_iqd' then 'accountIqd'
      when 'accountUsd' then 'accountUsd'
      when 'account_usd' then 'accountUsd'
      else null end
    when 'cars' then case trim(coalesce(p_key,''))
      when 'vehicleType' then 'vehicleType' when 'vehicle_type' then 'vehicleType' when 'type' then 'vehicleType'
      when 'brand' then 'brand' when 'make' then 'brand'
      when 'model' then 'model'
      when 'year' then 'year'
      when 'color' then 'color'
      when 'chassis' then 'chassis' when 'vin' then 'chassis' when 'chassisNumber' then 'chassis' when 'chassis_number' then 'chassis'
      when 'engineNumber' then 'engineNumber' when 'engine_number' then 'engineNumber' when 'engine_no' then 'engineNumber' when 'motor_number' then 'engineNumber'
      when 'plateNumber' then 'plateNumber' when 'plate_number' then 'plateNumber' when 'plate' then 'plateNumber'
      when 'carNumber' then 'carNumber' when 'car_number' then 'carNumber'
      when 'purchasePrice' then 'purchasePrice' when 'purchase_price' then 'purchasePrice' when 'costPrice' then 'purchasePrice'
      when 'salePrice' then 'salePrice' when 'sale_price' then 'salePrice'
      when 'currency' then 'currency' when 'costCurrency' then 'currency' when 'cost_currency' then 'currency' when 'saleCurrency' then 'currency' when 'sale_currency' then 'currency'
      when 'status' then 'status'
      when 'warehouseId' then 'warehouseId' when 'warehouse_id' then 'warehouseId' when 'currentWarehouseId' then 'warehouseId' when 'current_warehouse_id' then 'warehouseId' when 'lastWarehouseId' then 'warehouseId' when 'last_warehouse_id' then 'warehouseId'
      when 'supplierId' then 'supplierId' when 'supplier_id' then 'supplierId' when 'supplierName' then 'supplierId' when 'supplier_name' then 'supplierId'
      when 'purchaseDate' then 'purchaseDate' when 'purchase_date' then 'purchaseDate'
      when 'notes' then 'notes'
      when 'imagePath' then 'images' when 'image_path' then 'images' when 'image' then 'images' when 'photoBase64' then 'images' when 'photo_base64' then 'images'
      when 'inventoryAssetAccountId' then 'inventoryAssetAccountId' when 'inventory_asset_account_id' then 'inventoryAssetAccountId'
      when 'salesCostExpenseAccountId' then 'salesCostExpenseAccountId' when 'sales_cost_expense_account_id' then 'salesCostExpenseAccountId'
      when 'salesRevenueIqdAccountId' then 'salesRevenueIqdAccountId' when 'sales_revenue_iqd_account_id' then 'salesRevenueIqdAccountId'
      when 'salesRevenueUsdAccountId' then 'salesRevenueUsdAccountId' when 'sales_revenue_usd_account_id' then 'salesRevenueUsdAccountId'
      else null end
    when 'inventory' then case trim(coalesce(p_key,''))
      when 'name' then 'name' when 'nameAr' then 'name' when 'name_ar' then 'name'
      when 'nameEn' then 'nameEn' when 'name_en' then 'nameEn'
      when 'description' then 'description' when 'descriptionAr' then 'description' when 'description_ar' then 'description'
      when 'code' then 'code'
      when 'sku' then 'sku'
      when 'barcode' then 'barcode'
      when 'serialNumber' then 'serialNumber' when 'serial_number' then 'serialNumber'
      when 'category' then 'category'
      when 'groupId' then 'groupId' when 'group_id' then 'groupId'
      when 'warehouseId' then 'warehouseId' when 'warehouse_id' then 'warehouseId'
      when 'unit' then 'unit'
      when 'quantity' then 'quantity'
      when 'purchasePrice' then 'purchasePrice' when 'purchase_price' then 'purchasePrice'
      when 'landedCost' then 'landedCost' when 'landed_cost' then 'landedCost'
      when 'unitCost' then 'unitCost' when 'unit_cost' then 'unitCost'
      when 'salePrice' then 'salePrice' when 'sale_price' then 'salePrice'
      when 'currency' then 'currency' when 'costCurrency' then 'currency' when 'cost_currency' then 'currency' when 'saleCurrency' then 'currency' when 'sale_currency' then 'currency'
      when 'taxRate' then 'taxRate' when 'tax_rate' then 'taxRate' when 'taxPercent' then 'taxRate'
      when 'minQuantity' then 'minQuantity' when 'min_quantity' then 'minQuantity' when 'minimumQuantity' then 'minQuantity'
      when 'expectedIncoming' then 'expectedIncoming' when 'expected_incoming' then 'expectedIncoming'
      when 'expectedOutgoing' then 'expectedOutgoing' when 'expected_outgoing' then 'expectedOutgoing'
      when 'date' then 'date'
      when 'imageBase64' then 'image' when 'image_base64' then 'image'
      when 'notes' then 'notes'
      when 'isActive' then 'isActive' when 'is_active' then 'isActive'
      when 'itemType' then 'itemType' when 'item_type' then 'itemType' when 'productType' then 'itemType' when 'product_type' then 'itemType'
      when 'itemId' then 'transferItem' when 'item_id' then 'transferItem' when 'carId' then 'transferItem' when 'car_id' then 'transferItem' when 'productId' then 'transferItem' when 'product_id' then 'transferItem'
      when 'fromWarehouseId' then 'sourceWarehouseId' when 'from_warehouse_id' then 'sourceWarehouseId' when 'sourceWarehouseId' then 'sourceWarehouseId' when 'source_warehouse_id' then 'sourceWarehouseId'
      when 'toWarehouseId' then 'destinationWarehouseId' when 'to_warehouse_id' then 'destinationWarehouseId' when 'destinationWarehouseId' then 'destinationWarehouseId' when 'destination_warehouse_id' then 'destinationWarehouseId'
      when 'transferQuantity' then 'transferQuantity' when 'transfer_quantity' then 'transferQuantity'
      when 'operationalDate' then 'operationalDate' when 'operational_date' then 'operationalDate' when 'effectiveAt' then 'operationalDate' when 'effective_at' then 'operationalDate'
      when 'transferNotes' then 'transferNotes' when 'transfer_notes' then 'transferNotes'
      when 'inventoryAssetAccountId' then 'inventoryAssetAccountId' when 'inventory_asset_account_id' then 'inventoryAssetAccountId'
      when 'salesCostExpenseAccountId' then 'salesCostExpenseAccountId' when 'sales_cost_expense_account_id' then 'salesCostExpenseAccountId'
      when 'salesRevenueIqdAccountId' then 'salesRevenueIqdAccountId' when 'sales_revenue_iqd_account_id' then 'salesRevenueIqdAccountId'
      when 'salesRevenueUsdAccountId' then 'salesRevenueUsdAccountId' when 'sales_revenue_usd_account_id' then 'salesRevenueUsdAccountId'
      else null end
    when 'cashbox' then case trim(coalesce(p_key,''))
      when 'name' then 'name'
      when 'currency' then 'currency'
      when 'openingBalance' then 'openingBalance' when 'opening_balance' then 'openingBalance'
      when 'isActive' then 'isActive' when 'is_active' then 'isActive'
      when 'accountId' then 'ledgerAccount' when 'account_id' then 'ledgerAccount'
      when 'linkedCashAccountId' then 'linkedCashAccount' when 'linked_cash_account_id' then 'linkedCashAccount'
      when 'voucherNumber' then 'documentNumber'
      when 'category' then 'purpose'
      when 'amount' then 'amount'
      when 'transactionDate' then 'operationalDate' when 'transaction_date' then 'operationalDate'
      when 'partyType' then 'partyType'
      when 'partyName' then 'partyName'
      when 'cashAccountId' then 'cashAccount' when 'cash_account_id' then 'cashAccount'
      when 'counterAccountId' then 'counterAccount' when 'counter_account_id' then 'counterAccount'
      when 'exchangeRate' then 'exchangeRate' when 'exchange_rate' then 'exchangeRate'
      when 'fromCashAccountId' then 'transferFrom' when 'from_cash_account_id' then 'transferFrom'
      when 'toCashAccountId' then 'transferTo' when 'to_cash_account_id' then 'transferTo'
      when 'sourceAmount' then 'amount' when 'source_amount' then 'amount'
      when 'targetAmount' then 'amount' when 'target_amount' then 'amount'
      when 'notes' then 'notes'
      else null end
    when 'expenses' then case trim(coalesce(p_key,''))
      when 'title' then 'name'
      when 'category' then 'category'
      when 'amount' then 'amount'
      when 'currency' then 'currency'
      when 'date' then 'operationalDate'
      when 'notes' then 'notes'
      when 'accountId' then 'cashAccount'
      when 'expenseAccountId' then 'expenseAccount'
      when 'postingStatus' then 'postingStatus'
      when 'approvalStatus' then 'approvalStatus'
      else null end
    when 'installments' then case trim(coalesce(p_key,''))
      when 'saleId' then 'saleId' when 'sale_id' then 'saleId'
      when 'installmentNo' then 'installmentNo' when 'installment_no' then 'installmentNo' when 'installmentNumber' then 'installmentNo'
      when 'dueDate' then 'dueDate' when 'due_date' then 'dueDate'
      when 'amount' then 'amount'
      when 'paidAmount' then 'paidAmount' when 'paid_amount' then 'paidAmount'
      when 'remainingAmount' then 'remainingAmount' when 'remaining_amount' then 'remainingAmount'
      when 'status' then 'status'
      when 'paymentDate' then 'paymentDate' when 'payment_date' then 'paymentDate'
      when 'notes' then 'notes'
      else null end
    when 'opportunities' then case trim(coalesce(p_key,''))
      when 'opportunityNumber' then 'opportunityNumber' when 'opportunity_number' then 'opportunityNumber'
      when 'customerId' then 'customerId' when 'customer_id' then 'customerId'
      when 'customerName' then 'customerName' when 'customer_name' then 'customerName'
      when 'customerPhone' then 'customerPhone' when 'customer_phone' then 'customerPhone'
      when 'assignedUserId' then 'assignedUserId' when 'assigned_user_id' then 'assignedUserId'
      when 'assignedUserName' then 'assignedUserName' when 'assigned_user_name' then 'assignedUserName'
      when 'createdByUserId' then 'createdBy' when 'created_by_user_id' then 'createdBy'
      when 'createdByUserName' then 'createdBy' when 'created_by_user_name' then 'createdBy'
      when 'title' then 'title'
      when 'expectedValue' then 'value' when 'expected_value' then 'value' when 'value' then 'value'
      when 'status' then 'status'
      when 'carId' then 'car' when 'car_id' then 'car'
      when 'carName' then 'car' when 'car_name' then 'car'
      when 'source' then 'source'
      when 'followUpDate' then 'followUpDate' when 'follow_up_date' then 'followUpDate'
      when 'notes' then 'notes'
      when 'saleId' then 'linkedSale' when 'sale_id' then 'linkedSale' when 'salesOrderId' then 'linkedSale' when 'sales_order_id' then 'linkedSale'
      when 'invoiceNumber' then 'linkedSale' when 'invoice_number' then 'linkedSale'
      when 'salesOrderStatus' then 'linkedSale' when 'sales_order_status' then 'linkedSale'
      when 'deliveryNumber' then 'linkedSale' when 'delivery_number' then 'linkedSale'
      when 'deliveryStatus' then 'linkedSale' when 'delivery_status' then 'linkedSale'
      when 'invoiceStatus' then 'linkedSale' when 'invoice_status' then 'linkedSale'
      when 'paymentStatus' then 'linkedSale' when 'payment_status' then 'linkedSale'
      when 'paidAmount' then 'linkedSale' when 'paid_amount' then 'linkedSale'
      when 'remainingAmount' then 'linkedSale' when 'remaining_amount' then 'linkedSale'
      when 'createdAt' then 'createdAt' when 'created_at' then 'createdAt'
      when 'closedAt' then 'closedAt' when 'closed_at' then 'closedAt'
      when 'updatedAt' then 'updatedAt' when 'updated_at' then 'updatedAt'
      else null end
    when 'accounting' then case trim(coalesce(p_key,''))
      when 'entryNumber' then 'entryNumber'
      when 'entryDate' then 'entryDate'
      when 'description' then 'description'
      when 'currency' then 'currency'
      when 'totalDebit' then 'debit'
      when 'totalCredit' then 'credit'
      when 'referenceType' then 'reference'
      when 'referenceId' then 'reference'
      when 'status' then 'journalLines'
      else null end
    when 'sales' then case trim(coalesce(p_key,''))
      when 'customerId' then 'customerId'
      when 'opportunityId' then 'opportunityId'
      when 'currencyCode' then 'currencyCode'
      when 'exchangeRate' then 'exchangeRate'
      when 'saleDate' then 'operationalDate'
      when 'effectiveAt' then 'operationalDate'
      when 'notes' then 'notes'
      when 'salePrice' then 'itemPrice'
      when 'paidAmount' then 'payments'
      when 'remainingAmount' then 'payments'
      when 'paymentMethod' then 'payments'
      when 'invoiceNumber' then 'invoice'
      when 'installmentNo' then 'payments'
      when 'dueDate' then 'payments'
      when 'amount' then 'payments'
      when 'paymentDate' then 'payments'
      when 'status' then 'status'
      else null end
    when 'purchases' then case trim(coalesce(p_key,''))
      when 'invoiceNumber' then 'invoice' when 'invoice_number' then 'invoice'
      when 'supplierId' then 'supplierId' when 'supplier_id' then 'supplierId'
      when 'supplierName' then 'supplierName' when 'supplier_name' then 'supplierName'
      when 'purchaseDate' then 'operationalDate' when 'purchase_date' then 'operationalDate'
      when 'paymentMethod' then 'payments' when 'payment_method' then 'payments'
      when 'totalAmount' then 'total' when 'total_amount' then 'total'
      when 'paidAmount' then 'payments' when 'paid_amount' then 'payments'
      when 'remainingAmount' then 'payments' when 'remaining_amount' then 'payments'
      when 'notes' then 'notes'
      when 'createdAt' then 'createdAt' when 'created_at' then 'createdAt'
      when 'updatedAt' then 'updatedAt' when 'updated_at' then 'updatedAt'
      when 'currencyCode' then 'currencyCode' when 'currency_code' then 'currencyCode'
      when 'exchangeRate' then 'exchangeRate' when 'exchange_rate' then 'exchangeRate'
      when 'purchaseId' then 'items' when 'purchase_id' then 'items'
      when 'carId' then 'items' when 'car_id' then 'items'
      when 'carName' then 'items' when 'car_name' then 'items'
      when 'chassisNumber' then 'items' when 'chassis_number' then 'items'
      when 'purchasePrice' then 'itemCost' when 'purchase_price' then 'itemCost'
      when 'additionalCosts' then 'itemCost' when 'additional_costs' then 'itemCost'
      when 'totalCost' then 'itemCost' when 'total_cost' then 'itemCost'
      else null end
    when 'warehouses' then case trim(coalesce(p_key,''))
      when 'code' then 'code' when 'warehouseCode' then 'code' when 'warehouse_code' then 'code'
      when 'name' then 'name' when 'warehouseName' then 'name' when 'warehouse_name' then 'name'
      when 'branchId' then 'branchId' when 'branch_id' then 'branchId'
      when 'address' then 'address'
      when 'notes' then 'notes'
      when 'isActive' then 'isActive' when 'is_active' then 'isActive'
      when 'warehouseType' then 'warehouseType' when 'warehouse_type' then 'warehouseType'
      when 'inventoryAccountId' then 'inventoryAccountId' when 'inventory_account_id' then 'inventoryAccountId'
      when 'scrapExpenseAccountId' then 'scrapExpenseAccountId' when 'scrap_expense_account_id' then 'scrapExpenseAccountId'
      when 'scrapExpenseIqdAccountId' then 'scrapExpenseIqdAccountId' when 'scrap_expense_iqd_account_id' then 'scrapExpenseIqdAccountId'
      when 'scrapExpenseUsdAccountId' then 'scrapExpenseUsdAccountId' when 'scrap_expense_usd_account_id' then 'scrapExpenseUsdAccountId'
      else null end
    else null
  end
$$;

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
  if not public.erp_cloud_user_has_permission(p_company_id, trim(p_resource)||'.fields.restrict') then
    return p_payload;
  end if;
  for v_item in select key,value from jsonb_each(p_payload) loop
    v_field := public.erp_r9_logical_field_for_json_key(p_resource,v_item.key);
    -- In restricted mode business properties are default-deny. Only stable
    -- technical identity/version metadata may pass without a field mapping.
    if (v_field is null and v_item.key in (
          'id','recordId','record_id','_cloudVersion','_cloudUpdatedAt',
          'version','createdAt','created_at','updatedAt','updated_at'
        ))
       or (v_field is not null and public.erp_cloud_user_can_view_field(
             p_company_id,p_resource,v_field,null
           )) then
      v_result := v_result || jsonb_build_object(v_item.key,v_item.value);
    end if;
  end loop;
  return v_result;
end;
$$;

create or replace function public.erp_r9_guard_writable_json(
  p_company_id uuid,
  p_resource text,
  p_existing jsonb,
  p_incoming jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_result jsonb := coalesce(p_incoming,'{}'::jsonb);
  v_item record;
  v_field text;
begin
  if not public.erp_cloud_user_has_permission(p_company_id, trim(p_resource)||'.fields.restrict') then
    return v_result;
  end if;
  -- Iterate all known incoming business fields. If edit is not granted, restore
  -- the old value (or remove it for a new record).
  for v_item in select key,value from jsonb_each(coalesce(p_incoming,'{}'::jsonb)) loop
    v_field := public.erp_r9_logical_field_for_json_key(p_resource,v_item.key);
    if (v_field is null and v_item.key not in (
          'id','recordId','record_id','_cloudVersion','_cloudUpdatedAt',
          'version','createdAt','created_at','updatedAt','updated_at'
        ))
       or (v_field is not null and not public.erp_cloud_user_can_edit_field(
             p_company_id,p_resource,v_field,null
           )) then
      if coalesce(p_existing,'{}'::jsonb) ? v_item.key then
        v_result := jsonb_set(v_result,array[v_item.key],p_existing->v_item.key,true);
      else
        v_result := v_result - v_item.key;
      end if;
    end if;
  end loop;
  -- Prevent unauthorized deletion of an existing protected field by omission.
  for v_item in select key,value from jsonb_each(coalesce(p_existing,'{}'::jsonb)) loop
    v_field := public.erp_r9_logical_field_for_json_key(p_resource,v_item.key);
    if v_field is not null
       and not public.erp_cloud_user_can_edit_field(p_company_id,p_resource,v_field,null)
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
declare
  v_resource text;
begin
  v_resource := public.erp_r9_master_resource_for_table(tg_table_name);
  if v_resource is null then return new; end if;
  new.data := public.erp_r9_guard_writable_json(
    new.company_id,
    v_resource,
    case when tg_op='UPDATE' then old.data else '{}'::jsonb end,
    new.data
  );
  return new;
end;
$$;

-- Every table consumed through CloudMasterDataService receives the same guard.
do $$
declare
  v_table text;
begin
  foreach v_table in array array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers',
    'erp_warehouses','erp_inventory','erp_inventory_groups','erp_product_images',
    'erp_car_warehouse_transfers','erp_warehouse_transfers','erp_warehouse_transfer_items',
    'erp_installments'
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
  v_resource text;
  v_row record;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  v_resource := public.erp_r9_master_resource_for_table(p_table);
  if v_resource is null then raise exception 'unsupported_master_table:%',p_table; end if;
  for v_row in execute format(
    'select id,data,version,updated_at from public.%I where company_id=$1 and not is_deleted order by updated_at desc',
    p_table
  ) using p_company_id loop
    return next public.erp_r9_filter_readable_json(p_company_id,v_resource,v_row.data)
      || jsonb_build_object(
        'id',v_row.id,
        '_cloudVersion',v_row.version,
        '_cloudUpdatedAt',v_row.updated_at
      );
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
  v_resource text;
  v_row record;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  v_resource := public.erp_r9_master_resource_for_table(p_table);
  if v_resource is null then raise exception 'unsupported_master_table:%',p_table; end if;
  execute format(
    'select id,data,version,updated_at from public.%I where company_id=$1 and id=$2 and not is_deleted limit 1',
    p_table
  ) into v_row using p_company_id,p_record_id;
  if not found then return null; end if;
  return public.erp_r9_filter_readable_json(p_company_id,v_resource,v_row.data)
    || jsonb_build_object(
      'id',v_row.id,
      '_cloudVersion',v_row.version,
      '_cloudUpdatedAt',v_row.updated_at
    );
end;
$$;

revoke all on function public.erp_r9_list_cloud_master_records(uuid,text) from public,anon;
revoke all on function public.erp_r9_get_cloud_master_record(uuid,text,text) from public,anon;
grant execute on function public.erp_r9_list_cloud_master_records(uuid,text) to authenticated;
grant execute on function public.erp_r9_get_cloud_master_record(uuid,text,text) to authenticated;

-- For restricted master resources, direct table SELECT is denied by RLS so a
-- client cannot bypass the masked RPC. Unrestricted legacy roles keep the old
-- direct-select behavior (including Realtime).
do $$
declare
  v_table text;
  v_resource text;
begin
  for v_table,v_resource in values
    ('erp_cars','cars'),('erp_car_images','cars'),
    ('erp_customers','customers'),('erp_suppliers','suppliers'),
    ('erp_warehouses','warehouses'),('erp_inventory','inventory'),
    ('erp_inventory_groups','inventory'),('erp_product_images','inventory'),
    ('erp_car_warehouse_transfers','inventory'),('erp_warehouse_transfers','inventory'),
    ('erp_warehouse_transfer_items','inventory'),('erp_warehouse_stock','inventory'),
    ('erp_inventory_movements','inventory'),
    ('erp_cash_accounts','cashbox'),('erp_cash_transactions','cashbox'),
    ('erp_expenses','expenses'),('erp_journal_entries','accounting'),
    ('erp_installments','installments'),('erp_sales','sales'),
    ('erp_purchases','purchases'),('erp_purchase_items','purchases')
  loop
    if to_regclass('public.'||v_table) is not null then
      execute format('drop policy if exists %I_select on public.%I',v_table,v_table);
      execute format('drop policy if exists %I_r9_masked_select on public.%I',v_table,v_table);
      execute format(
        'create policy %I_r9_masked_select on public.%I for select to authenticated using ('
        || 'public.is_active_company_member(company_id) and not public.erp_cloud_user_has_permission(company_id,%L))',
        v_table,v_table,v_resource||'.fields.restrict'
      );
    end if;
  end loop;
end $$;

-- The legacy commercial archives are view/print/delete history only in R9.
-- Prevent authenticated clients from reintroducing direct create/update paths;
-- the retained security-definer lifecycle RPCs remain authoritative.
revoke insert,update on public.erp_sales from authenticated;
revoke insert,update on public.erp_purchases,public.erp_purchase_items from authenticated;

-- Filter user records in the access snapshot. Password hashes are never
-- returned to ordinary restricted viewers unless explicitly granted.
create or replace function public.erp_access_cloud_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_slug text;
  v_company uuid;
  v_users jsonb := '[]'::jsonb;
begin
  select company_uuid,company_slug into v_company,v_slug
  from public.erp_active_company_context();
  if v_slug is null or v_company is null then raise exception 'membership_not_found'; end if;

  if public.erp_cloud_user_has_permission(v_company,'users.view')
     or public.is_company_admin(v_company) then
    select coalesce(jsonb_agg(public.erp_r9_filter_readable_json(v_company,'users',r.payload) order by r.updated_at desc),'[]'::jsonb)
      into v_users
    from public.erp_records r
    where r.company_id=v_slug and r.entity_type='users'
      and r.deleted_at is null and not r.is_deleted;
  end if;

  return jsonb_build_object(
    'users',v_users,
    'roles',case when public.erp_cloud_user_has_permission(v_company,'permissions.view') or public.is_company_admin(v_company)
      then coalesce((select jsonb_agg(payload order by record_id) from public.erp_records where company_id=v_slug and entity_type='roles' and deleted_at is null and not is_deleted),'[]'::jsonb)
      else '[]'::jsonb end,
    'permissions',case when public.erp_cloud_user_has_permission(v_company,'permissions.view') or public.erp_cloud_user_has_permission(v_company,'permission_scopes.manage') or public.is_company_admin(v_company)
      then coalesce((select jsonb_agg(payload order by record_id) from public.erp_records where company_id=v_slug and entity_type='permissions' and deleted_at is null and not is_deleted),'[]'::jsonb)
      else '[]'::jsonb end,
    'role_permissions',case when public.erp_cloud_user_has_permission(v_company,'permissions.view') or public.erp_cloud_user_has_permission(v_company,'permission_scopes.manage') or public.is_company_admin(v_company)
      then coalesce((select jsonb_agg(payload order by record_id) from public.erp_records where company_id=v_slug and entity_type='role_permissions' and deleted_at is null and not is_deleted),'[]'::jsonb)
      else '[]'::jsonb end,
    'audit_logs','[]'::jsonb
  );
end;
$$;
revoke all on function public.erp_access_cloud_snapshot() from public,anon;
grant execute on function public.erp_access_cloud_snapshot() to authenticated;

commit;
