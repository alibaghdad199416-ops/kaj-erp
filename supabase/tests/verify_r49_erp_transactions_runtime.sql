\set ON_ERROR_STOP on
\pset pager off

-- Canonical R49 ERP transaction proof. This test runs only inside the
-- repository-owned disposable local database and rolls every fixture back.
begin;
set local session_replication_role=replica;

insert into auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values
(
  '00000000-0000-0000-0000-000000000000','49000000-0000-4000-8000-000000000001',
  'authenticated','authenticated','r49-runtime@local.invalid','',now(),'{}','{}',now(),now()
),(
  '00000000-0000-0000-0000-000000000000','49000000-0000-4000-8000-000000000002',
  'authenticated','authenticated','r49-denied@local.invalid','',now(),'{}','{}',now(),now()
),(
  '00000000-0000-0000-0000-000000000000','49000000-0000-4000-8000-000000000003',
  'authenticated','authenticated','r49-other-company@local.invalid','',now(),'{}','{}',now(),now()
);

insert into public.companies(id,slug,name_ar,name_en,is_active) values
  ('49000000-0000-4000-8000-000000000010','r49-runtime','R49 محلي','R49 local',true),
  ('49000000-0000-4000-8000-000000000011','r49-other','R49 أخرى','R49 other',true);
insert into public.company_memberships(
  company_id,user_id,user_uid,user_email,role_code,is_system_admin,is_active
) values
(
  '49000000-0000-4000-8000-000000000010','49000000-0000-4000-8000-000000000001',
  '49000000-0000-4000-8000-000000000001','r49-runtime@local.invalid','admin',true,true
),(
  '49000000-0000-4000-8000-000000000010','49000000-0000-4000-8000-000000000002',
  '49000000-0000-4000-8000-000000000002','r49-denied@local.invalid','user',false,true
),(
  '49000000-0000-4000-8000-000000000011','49000000-0000-4000-8000-000000000003',
  '49000000-0000-4000-8000-000000000003','r49-other-company@local.invalid','admin',true,true
);

insert into public.erp_accounts(
  organization_id,account_id,code,name,account_type,currency,opening_balance,is_active,
  source_updated_at,synced_at,synced_by
) values
  ('49000000-0000-4000-8000-000000000010','r49-inventory-usd','11001','R49 inventory USD','asset','USD',0,true,now(),now(),'49000000-0000-4000-8000-000000000001'),
  ('49000000-0000-4000-8000-000000000010','r49-cogs-usd','51001','R49 COGS USD','expense','USD',0,true,now(),now(),'49000000-0000-4000-8000-000000000001'),
  ('49000000-0000-4000-8000-000000000010','r49-revenue-usd','41001','R49 revenue USD','revenue','USD',0,true,now(),now(),'49000000-0000-4000-8000-000000000001'),
  ('49000000-0000-4000-8000-000000000010','r49-customer-usd','12001','R49 customer USD','asset','USD',0,true,now(),now(),'49000000-0000-4000-8000-000000000001'),
  ('49000000-0000-4000-8000-000000000010','r49-customer-iqd','12002','R49 customer IQD','asset','IQD',0,true,now(),now(),'49000000-0000-4000-8000-000000000001'),
  ('49000000-0000-4000-8000-000000000010','r49-supplier-usd','21001','R49 supplier USD','liability','USD',0,true,now(),now(),'49000000-0000-4000-8000-000000000001'),
  ('49000000-0000-4000-8000-000000000010','r49-supplier-iqd','21002','R49 supplier IQD','liability','IQD',0,true,now(),now(),'49000000-0000-4000-8000-000000000001'),
  ('49000000-0000-4000-8000-000000000010','r49-cash-usd-ledger','11101','R49 cash USD','asset','USD',0,true,now(),now(),'49000000-0000-4000-8000-000000000001'),
  ('49000000-0000-4000-8000-000000000010','r49-cash-iqd-ledger','11102','R49 cash IQD','asset','IQD',0,true,now(),now(),'49000000-0000-4000-8000-000000000001'),
  ('49000000-0000-4000-8000-000000000010','r49-maintenance-expense','52001','R49 maintenance expense','expense','USD',0,true,now(),now(),'49000000-0000-4000-8000-000000000001'),
  ('49000000-0000-4000-8000-000000000010','r49-account-edit','001.02','R49 Account Before','expense','USD',0,true,now(),now(),'49000000-0000-4000-8000-000000000001'),
  ('49000000-0000-4000-8000-000000000010','r49-account-inactive','001.03','R49 Inactive','asset','USD',0,false,now(),now(),'49000000-0000-4000-8000-000000000001'),
  ('49000000-0000-4000-8000-000000000010','r49-account-wrong-currency','001.04','R49 Wrong Currency','asset','IQD',0,true,now(),now(),'49000000-0000-4000-8000-000000000001');

insert into public.erp_customers(company_id,id,data) values (
  '49000000-0000-4000-8000-000000000010','49000000-0000-4000-8000-000000000020',
  '{"name":"R49 Customer","isActive":true,"currency":"USD"}'
);
insert into public.erp_suppliers(company_id,id,data) values (
  '49000000-0000-4000-8000-000000000010','r49-supplier',
  '{"name":"R49 Supplier","isActive":true,"currency":"USD"}'
);
insert into public.erp_partner_accounts(
  organization_id,partner_type,partner_id,partner_name,usd_account_id,iqd_account_id,
  is_active,source_updated_at,synced_at,synced_by
) values
  ('49000000-0000-4000-8000-000000000010','customer','49000000-0000-4000-8000-000000000020','R49 Customer',
   'r49-customer-usd','r49-customer-iqd',true,now(),now(),'49000000-0000-4000-8000-000000000001'),
  ('49000000-0000-4000-8000-000000000010','supplier','r49-supplier','R49 Supplier',
   'r49-supplier-usd','r49-supplier-iqd',true,now(),now(),'49000000-0000-4000-8000-000000000001');

insert into public.erp_warehouses(company_id,id,data) values (
  '49000000-0000-4000-8000-000000000010','r49-warehouse',
  '{"name":"R49 Warehouse","code":"R49-WH","isActive":true}'
);
insert into public.erp_warehouses(company_id,id,data) values (
  '49000000-0000-4000-8000-000000000010','r49-destination-warehouse',
  '{"name":"R49 Destination Warehouse","code":"R49-DST","isActive":true}'
);
insert into public.erp_warehouses(company_id,id,data) values (
  '49000000-0000-4000-8000-000000000011','r49-other-warehouse',
  '{"name":"R49 Other Warehouse","code":"R49-OTHER","isActive":true}'
);
insert into public.erp_inventory(company_id,id,data) values (
  '49000000-0000-4000-8000-000000000010','r49-product',
  '{"name":"R49 Product","code":"R49-PRODUCT","itemType":"stock","isActive":true,
    "currency":"USD","costCurrency":"USD","unitCost":0,"purchasePrice":0,"salePrice":20,
    "inventoryAssetAccountId":"r49-inventory-usd",
    "salesCostExpenseAccountId":"r49-cogs-usd",
    "salesRevenueUsdAccountId":"r49-revenue-usd"}'
);
insert into public.erp_cars(company_id,id,data) values (
  '49000000-0000-4000-8000-000000000010','r49-sold-car',
  '{"brand":"R49","model":"Sold Car","status":"sold","currency":"USD","costCurrency":"USD",
    "inventoryAssetAccountId":"r49-inventory-usd","salesCostExpenseAccountId":"r49-cogs-usd",
    "salesRevenueUsdAccountId":"r49-revenue-usd","purchasePrice":1000}'
);
insert into public.erp_cash_accounts(company_id,id,data) values
  ('49000000-0000-4000-8000-000000000010','r49-cash-usd',
   '{"name":"R49 Cash USD","currency":"USD","accountId":"r49-cash-usd-ledger","isActive":true,"openingBalance":10000}'),
  ('49000000-0000-4000-8000-000000000010','r49-cash-iqd',
   '{"name":"R49 Cash IQD","currency":"IQD","accountId":"r49-cash-iqd-ledger","isActive":true,"openingBalance":10000000}');

set local session_replication_role=origin;
select set_config(
  'request.jwt.claims',
  '{"sub":"49000000-0000-4000-8000-000000000001","role":"authenticated"}',true
);

do $runtime$
declare
  c constant uuid := '49000000-0000-4000-8000-000000000010';
  po uuid; receipt uuid; pi uuid; po2 uuid; receipt2 uuid; pi2 uuid; result jsonb;
  so uuid; delivery uuid; si uuid; mo uuid; maintenance_result jsonb;
  cancel_order uuid; cancel_opportunity jsonb;
  opportunity jsonb; opportunities jsonb;
  qty numeric; movements integer; layers integer; journals integer;
  movement_rows jsonb;
  purchase_journal text; sales_journal text;
  error_detail text;
  linked_order uuid; opportunity_state jsonb; cost_journal text;
  payment_journal text;
  warehouse_state jsonb; account_state jsonb;
  car_reference text; product_reference text; opportunity_reference text; search_rows jsonb;
  transfer_id text; inventory_value numeric; fifo_quantity numeric; fifo_cost numeric;
  layer_count_before integer;
  movement_count_before integer; journal_count_before integer;
  payment_count_before integer;
begin
  if has_function_privilege(
       'anon','public.erp_r9_logical_field_for_json_key_pre_r49_roundtrip(text,text)','EXECUTE'
     ) or not has_function_privilege(
       'authenticated','public.erp_r9_logical_field_for_json_key_pre_r49_roundtrip(text,text)','EXECUTE'
     ) then
    raise exception 'opportunity_mapping_helper_acl_incorrect';
  end if;
  insert into public.erp_cars(company_id,id,data) values(
    c,'r49-reference-car',
    '{"brand":"R49","model":"Reference Car","status":"known","currency":"USD","costCurrency":"USD",
      "purchasePrice":100,"salePrice":120,"inventoryAssetAccountId":"r49-inventory-usd",
      "salesCostExpenseAccountId":"r49-cogs-usd","salesRevenueUsdAccountId":"r49-revenue-usd"}'
  );
  insert into public.erp_inventory(company_id,id,data) values(
    c,'r49-reference-product',
    '{"name":"R49 Reference Product","itemType":"stock","isActive":true,"currency":"USD",
      "costCurrency":"USD","purchasePrice":5,"unitCost":5,"salePrice":8,
      "inventoryAssetAccountId":"r49-inventory-usd","salesCostExpenseAccountId":"r49-cogs-usd",
      "salesRevenueUsdAccountId":"r49-revenue-usd"}'
  );
  select data->>'carNumber' into car_reference from public.erp_cars
    where company_id=c and id='r49-reference-car';
  select data->>'code' into product_reference from public.erp_inventory
    where company_id=c and id='r49-reference-product';
  if car_reference!~'^CAR[0-9]{4}$' or product_reference!~'^PRD[0-9]{4}$' then
    raise exception 'master_business_reference_generation_failed:car=% product=%',car_reference,product_reference;
  end if;
  insert into public.erp_cars(company_id,id,data) values(
    c,'r49-reference-car-duplicate',jsonb_build_object(
      'brand','Duplicate','model','Reference','status','known','carNumber',car_reference,
      'currency','USD','costCurrency','USD','purchasePrice',100,'salePrice',120,
      'inventoryAssetAccountId','r49-inventory-usd','salesCostExpenseAccountId','r49-cogs-usd',
      'salesRevenueUsdAccountId','r49-revenue-usd'
    )
  );
  insert into public.erp_inventory(company_id,id,data) values(
    c,'r49-reference-product-duplicate',jsonb_build_object(
      'name','Duplicate product','itemType','stock','isActive',true,'code',product_reference,
      'currency','USD','costCurrency','USD','purchasePrice',5,'unitCost',5,'salePrice',8,
      'inventoryAssetAccountId','r49-inventory-usd','salesCostExpenseAccountId','r49-cogs-usd',
      'salesRevenueUsdAccountId','r49-revenue-usd'
    )
  );
  if (select data->>'carNumber' from public.erp_cars where company_id=c and id='r49-reference-car-duplicate')
       !~'^CAR[0-9]{4}$'
     or (select data->>'carNumber' from public.erp_cars where company_id=c and id='r49-reference-car-duplicate')=car_reference
     or (select data->>'code' from public.erp_inventory where company_id=c and id='r49-reference-product-duplicate')
       !~'^PRD[0-9]{4}$'
     or (select data->>'code' from public.erp_inventory where company_id=c and id='r49-reference-product-duplicate')=product_reference then
    raise exception 'duplicate_business_reference_was_not_reassigned_uniquely';
  end if;

  warehouse_state := public.erp_r15_get_cloud_master_record(c,'erp_warehouses','r49-warehouse');
  perform public.erp_r15_upsert_cloud_master_record(
    c,'erp_warehouses','r49-warehouse',
    (warehouse_state-'_cloudVersion'-'_cloudUpdatedAt')||jsonb_build_object(
      'name','R49 Warehouse Updated','code','R49-WH-UPDATED','address','Long runtime address بغداد',
      'notes','authoritative mutation read-back','isActive',true
    ),(warehouse_state->>'_cloudVersion')::bigint
  );
  warehouse_state := public.erp_r15_get_cloud_master_record(c,'erp_warehouses','r49-warehouse');
  if warehouse_state->>'name'<>'R49 Warehouse Updated'
     or warehouse_state->>'code'<>'R49-WH-UPDATED'
     or warehouse_state->>'address'<>'Long runtime address بغداد'
     or warehouse_state->>'notes'<>'authoritative mutation read-back' then
    raise exception 'warehouse_update_readback_failed:%',warehouse_state;
  end if;
  perform set_config('request.jwt.claims','{"sub":"49000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
  begin
    perform public.erp_r15_upsert_cloud_master_record(
      c,'erp_warehouses','r49-warehouse',warehouse_state||jsonb_build_object('name','Denied'),
      (warehouse_state->>'_cloudVersion')::bigint
    );
    raise exception 'warehouse_unauthorized_update_unexpected_success';
  exception when sqlstate '42501' then null; end;
  perform set_config('request.jwt.claims','{"sub":"49000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
  begin
    perform public.erp_r15_upsert_cloud_master_record(
      c,'erp_warehouses','r49-warehouse',warehouse_state||jsonb_build_object('name','Cross tenant'),
      (warehouse_state->>'_cloudVersion')::bigint
    );
    raise exception 'warehouse_cross_company_update_unexpected_success';
  exception when sqlstate '42501' then null; end;
  perform set_config('request.jwt.claims','{"sub":"49000000-0000-4000-8000-000000000001","role":"authenticated"}',true);

  perform public.erp_r49_save_cloud_ledger_account(c,jsonb_build_object(
    'id','r49-account-edit','code','001.02-A','name','R49 Account Updated',
    'type','expense','currency','USD','openingBalance',0,'isActive',true
  ),true);
  account_state := (select x from public.erp_r22_list_cloud_ledger_accounts(c) x
    where x->>'id'='r49-account-edit' limit 1);
  if account_state->>'code'<>'001.02-A'
     or account_state->>'name'<>'R49 Account Updated'
     or account_state->>'type'<>'expense'
     or account_state->>'currency'<>'USD' then
    raise exception 'ledger_account_string_update_readback_failed:%',account_state;
  end if;
  begin
    perform public.erp_phase2_account_guard(c,'r49-account-inactive','asset','USD');
    raise exception 'inactive_account_guard_unexpected_success';
  exception when sqlstate 'P0001' then null;
  end;
  begin
    perform public.erp_phase2_account_guard(c,'r49-account-wrong-currency','asset','USD');
    raise exception 'wrong_currency_account_guard_unexpected_success';
  exception when sqlstate 'P0001' then null;
  end;

  opportunity := public.erp_r49_opportunity_command('save',jsonb_build_object(
    'create_only',true,'record',jsonb_build_object(
      'id','r49-runtime-opportunity','customerId','49000000-0000-4000-8000-000000000020',
      'customerName','R49 Customer','customerPhone','07700000000','title','R49 Runtime Value',
      'source','runtime','expectedValue',1234.56,'currency','USD','stage','proposal',
      'probability',50,'assignedUserId','49000000-0000-4000-8000-000000000001',
      'assignedUserName','R49 Admin','createdByUserId','49000000-0000-4000-8000-000000000001',
      'createdByUserName','R49 Admin'
    )
  ));
  opportunity_reference := (select payload->>'opportunityNumber' from public.erp_records
    where company_id='r49-runtime' and entity_type='opportunities'
      and record_id='r49-runtime-opportunity' and deleted_at is null);
  if opportunity_reference!~'^OPP[0-9]{4}$'
     or (select record_id from public.erp_records
        where company_id='r49-runtime' and entity_type='opportunities'
          and payload->>'opportunityNumber'=opportunity_reference and deleted_at is null)<>'r49-runtime-opportunity' then
    raise exception 'opportunity_business_reference_generation_or_internal_key_failed:%',opportunity;
  end if;
  if (opportunity->>'expectedValue')::numeric<>1234.56 or opportunity->>'currency'<>'USD' then
    raise exception 'opportunity_expected_value_create_round_trip_failed:%',opportunity;
  end if;
  opportunity := public.erp_r49_opportunity_command('save',jsonb_build_object(
    'create_only',false,'expected_updated_at',opportunity->>'updatedAt',
    'record',opportunity||jsonb_build_object('expectedValue',0,'currency','IQD')
  ));
  opportunities := public.erp_r49_opportunity_command('list','{}'::jsonb);
  if (select count(*) from jsonb_array_elements(opportunities) x
      where x->>'id'='r49-runtime-opportunity' and (x->>'expectedValue')::numeric=0 and x->>'currency'='IQD')<>1 then
    raise exception 'opportunity_expected_value_zero_update_readback_failed:%',opportunities;
  end if;

  po := public.erp_r49_create_purchase_order(c,jsonb_build_object(
    'supplierId','r49-supplier','currency','USD','exchangeRate',1,'discount',0,
    'effectiveAt','2026-08-10T08:00:00Z','items',jsonb_build_array(jsonb_build_object(
      'itemType','product','itemId','r49-product','description','R49 Product',
      'quantity',10,'unitCost',10
    ))
  ));
  perform public.erp_r49_approve_purchase_order(c,po);
  select coalesce(sum(public.erp_try_numeric(data->>'quantity',0)),0) into qty
    from public.erp_warehouse_stock where company_id=c and data->>'productId'='r49-product' and not is_deleted;
  if qty<>0 then raise exception 'purchase_order_approval_changed_stock:%',qty; end if;
  select count(*) into movements from public.erp_inventory_movements where company_id=c and not is_deleted;
  if movements<>0 then raise exception 'purchase_order_approval_created_movement:%',movements; end if;

  receipt := public.erp_r49_create_purchase_receipt(c,po,'r49-warehouse','runtime receipt');
  perform public.erp_phase2_approve_purchase_receipt(c,receipt);
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>10 then raise exception 'purchase_receipt_stock_expected_10_actual_%',qty; end if;
  select count(*) into movements from public.erp_inventory_movements
    where company_id=c and data->>'movementType'='purchase_in'
      and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if movements<>1 then
    select coalesce(jsonb_agg(data),'[]'::jsonb) into movement_rows
      from public.erp_inventory_movements where company_id=c and not is_deleted;
    raise exception 'purchase_receipt_movement_expected_1_actual_% rows=%',movements,movement_rows;
  end if;
  select coalesce(sum(remaining_quantity),0),coalesce(sum(remaining_quantity*unit_cost),0),count(*)
    into fifo_quantity,inventory_value,layers
  from public.erp_inventory_cost_layers where company_id=c and receipt_id=receipt;
  if fifo_quantity<>10 or inventory_value<>100 or layers<>1
     or (select public.erp_try_numeric(data->>'averageUnitCost',0) from public.erp_warehouse_stock
         where company_id=c and data->>'productId'='r49-product'
           and data->>'warehouseId'='r49-warehouse' and not is_deleted)<>10
     or exists(select 1 from public.erp_journal_entries
       where company_id=c and data->>'referenceType'='purchase_invoice' and not is_deleted) then
    raise exception 'purchase_receipt_operational_valuation_expected_qty_10_value_100_layer_1_no_gl';
  end if;
  perform public.erp_phase2_approve_purchase_receipt(c,receipt);
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  select count(*) into movements from public.erp_inventory_movements
    where company_id=c and data->>'movementType'='purchase_in'
      and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>10 or movements<>1
     or (select count(*) from public.erp_inventory_cost_layers where company_id=c and receipt_id=receipt)<>1
     or (select coalesce(sum(remaining_quantity*unit_cost),0) from public.erp_inventory_cost_layers
         where company_id=c and receipt_id=receipt)<>100 then
    raise exception 'purchase_receipt_retry_not_idempotent:qty=% movements=%',qty,movements;
  end if;

  pi := public.erp_create_cloud_purchase_workflow_invoice(c,po);
  result := public.erp_r22_approve_purchase_invoice(c,pi);
  if coalesce((result->>'ok')::boolean,false) is not true then raise exception 'purchase_invoice_failed:%',result; end if;
  purchase_journal := result->>'journalEntryId';
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>10 then raise exception 'purchase_invoice_changed_stock:%',qty; end if;
  select count(*) into layers from public.erp_inventory_cost_layers where company_id=c and receipt_id=receipt;
  if layers<>1
     or (select coalesce(sum(remaining_quantity),0) from public.erp_inventory_cost_layers
         where company_id=c and receipt_id=receipt)<>10
     or (select coalesce(sum(remaining_quantity*unit_cost),0) from public.erp_inventory_cost_layers
         where company_id=c and receipt_id=receipt)<>100 then
    raise exception 'purchase_invoice_mutated_operational_valuation:layers=%',layers;
  end if;
  perform public.erp_v762_assert_posted_journal_balanced(c,purchase_journal,'r49_runtime_purchase');
  if (select public.erp_try_numeric(data->>'totalDebit',0) from public.erp_journal_entries
      where company_id=c and id=purchase_journal and not is_deleted)<>100
     or (select public.erp_try_numeric(data->>'totalCredit',0) from public.erp_journal_entries
      where company_id=c and id=purchase_journal and not is_deleted)<>100
     or (select coalesce(sum(public.erp_try_numeric(data->>'debit',0)),0) from public.erp_journal_lines
      where company_id=c and data->>'entryId'=purchase_journal and data->>'accountId'='r49-inventory-usd'
        and data->>'currency'='USD' and not is_deleted)<>100
     or (select coalesce(sum(public.erp_try_numeric(data->>'credit',0)),0) from public.erp_journal_lines
      where company_id=c and data->>'entryId'=purchase_journal and data->>'accountId'='r49-supplier-usd'
        and data->>'currency'='USD' and not is_deleted)<>100
     or exists(select 1 from public.erp_journal_lines l left join public.erp_accounts a
        on a.organization_id=c and a.account_id=l.data->>'accountId'
        where l.company_id=c and l.data->>'entryId'=purchase_journal and not l.is_deleted
          and (a.account_id is null or not a.is_active or upper(a.currency)<>'USD')) then
    raise exception 'purchase_invoice_exact_accounting_lines_incorrect';
  end if;
  result := public.erp_r22_approve_purchase_invoice(c,pi);
  if coalesce((result->>'idempotent')::boolean,false) is not true then raise exception 'purchase_invoice_retry_not_idempotent:%',result; end if;
  select count(*) into journals from public.erp_journal_entries
    where company_id=c and data->>'referenceType'='purchase_invoice'
      and data->>'referenceId'=pi::text and not is_deleted;
  if journals<>1 then raise exception 'purchase_invoice_retry_journal_count:%',journals; end if;
  perform public.erp_pay_cloud_purchase_workflow_invoice(c,pi,jsonb_build_object(
    'paymentKey','r49-purchase-payment','cashAccountId','r49-cash-usd',
    'paymentCurrency','USD','invoiceAmount',100,'cashAmount',100,'exchangeRate',1,
    'paymentDate','2026-08-10T08:30:00Z','settlementMode','full'
  ));
  if (select payload->>'paymentStatus' from public.erp_commercial_workflow_documents where id=pi)<>'paid'
     or (select count(*) from public.erp_cash_transactions where company_id=c and data->>'paymentKey'='r49-purchase-payment' and not is_deleted)<>1 then
    raise exception 'purchase_same_currency_payment_state_incorrect';
  end if;
  payment_journal := (select data->>'journalEntryId' from public.erp_cash_transactions
    where company_id=c and data->>'paymentKey'='r49-purchase-payment' and not is_deleted limit 1);
  if payment_journal is null
     or (select data->>'amount' from public.erp_cash_transactions
      where company_id=c and data->>'paymentKey'='r49-purchase-payment' and not is_deleted limit 1)::numeric<>100
     or (select data->>'currency' from public.erp_cash_transactions
      where company_id=c and data->>'paymentKey'='r49-purchase-payment' and not is_deleted limit 1)<>'USD'
     or (select data->>'cashAccountId' from public.erp_cash_transactions
      where company_id=c and data->>'paymentKey'='r49-purchase-payment' and not is_deleted limit 1)<>'r49-cash-usd'
     or (select coalesce(sum(public.erp_try_numeric(data->>'debit',0)),0) from public.erp_journal_lines
      where company_id=c and data->>'entryId'=payment_journal and data->>'accountId'='r49-supplier-usd' and not is_deleted)<>100
     or (select coalesce(sum(public.erp_try_numeric(data->>'credit',0)),0) from public.erp_journal_lines
      where company_id=c and data->>'entryId'=payment_journal and data->>'accountId'='r49-cash-usd-ledger' and not is_deleted)<>100 then
    raise exception 'purchase_payment_exact_cash_or_journal_lines_incorrect:%',payment_journal;
  end if;
  perform public.erp_pay_cloud_purchase_workflow_invoice(c,pi,jsonb_build_object(
    'paymentKey','r49-purchase-payment','cashAccountId','r49-cash-usd',
    'paymentCurrency','USD','invoiceAmount',100,'cashAmount',100,'exchangeRate',1,
    'paymentDate','2026-08-10T08:30:00Z','settlementMode','full'
  ));
  if (select count(*) from public.erp_cash_transactions where company_id=c and data->>'paymentKey'='r49-purchase-payment' and not is_deleted)<>1 then
    raise exception 'purchase_payment_retry_duplicated_cash_transaction';
  end if;
  if (select count(*) from public.erp_journal_entries
      where company_id=c and id=payment_journal and not is_deleted)<>1 then
    raise exception 'purchase_payment_retry_duplicated_journal';
  end if;

  -- A second acquisition at a different cost makes the following sale cross
  -- an actual FIFO boundary.
  po2 := public.erp_r49_create_purchase_order(c,jsonb_build_object(
    'supplierId','r49-supplier','currency','USD','exchangeRate',1,'discount',0,
    'effectiveAt','2026-08-10T09:00:00Z','items',jsonb_build_array(jsonb_build_object(
      'itemType','product','itemId','r49-product','description','R49 Product',
      'quantity',10,'unitCost',15
    ))
  ));
  perform public.erp_r49_approve_purchase_order(c,po2);
  receipt2 := public.erp_r49_create_purchase_receipt(c,po2,'r49-warehouse','second FIFO layer');
  perform public.erp_phase2_approve_purchase_receipt(c,receipt2);
  select coalesce(sum(remaining_quantity),0),coalesce(sum(remaining_quantity*unit_cost),0),count(*)
    into fifo_quantity,inventory_value,layers
  from public.erp_inventory_cost_layers
  where company_id=c and item_type='product' and item_id='r49-product'
    and status in ('active','consumed');
  if fifo_quantity<>20 or inventory_value<>250 or layers<>2
     or (select count(*) from public.erp_journal_entries
       where company_id=c and data->>'referenceType'='purchase_invoice' and not is_deleted)<>1 then
    raise exception 'second_receipt_operational_valuation_expected_qty_20_value_250_layers_2_no_gl';
  end if;
  pi2 := public.erp_create_cloud_purchase_workflow_invoice(c,po2);
  result := public.erp_r22_approve_purchase_invoice(c,pi2);
  if coalesce((result->>'ok')::boolean,false) is not true then raise exception 'second_purchase_invoice_failed:%',result; end if;
  if (select public.erp_try_numeric(data->>'totalDebit',0) from public.erp_journal_entries
      where company_id=c and id=result->>'journalEntryId' and not is_deleted)<>150
     or (select public.erp_try_numeric(data->>'totalCredit',0) from public.erp_journal_entries
      where company_id=c and id=result->>'journalEntryId' and not is_deleted)<>150 then
    raise exception 'second_purchase_invoice_expected_150_each_side:%',result;
  end if;
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>20 then raise exception 'two_purchase_receipts_stock_expected_20_actual_%',qty; end if;

  so := public.erp_r49_create_sales_order(c,jsonb_build_object(
    'customerId','49000000-0000-4000-8000-000000000020','opportunityId','r49-runtime-opportunity',
    'currency','USD','exchangeRate',1,'discount',0,
    'effectiveAt','2026-08-10T10:00:00Z','items',jsonb_build_array(jsonb_build_object(
      'itemType','product','itemId','r49-product','description','R49 Product',
      'quantity',15,'unitPrice',20
    ))
  ));
  linked_order := public.erp_r49_create_sales_order(c,jsonb_build_object(
    'customerId','49000000-0000-4000-8000-000000000020','opportunityId','r49-runtime-opportunity',
    'currency','USD','exchangeRate',1,'discount',0,'effectiveAt','2026-08-10T10:00:00Z',
    'items',jsonb_build_array(jsonb_build_object(
      'itemType','product','itemId','r49-product','description','R49 Product','quantity',15,'unitPrice',20
    ))
  ));
  if linked_order<>so or (select count(*) from public.erp_sales_orders_cloud
      where company_id=c and opportunity_id='r49-runtime-opportunity' and not is_deleted)<>1 then
    raise exception 'opportunity_sales_order_retry_created_duplicate';
  end if;
  if (select order_number from public.erp_sales_orders_cloud where id=so) is null
     or (select order_number from public.erp_sales_orders_cloud where id=so)=so::text
     or (select order_number from public.erp_purchase_orders_cloud where id=po) is null
     or (select order_number from public.erp_purchase_orders_cloud where id=po)=po::text then
    raise exception 'commercial_document_business_reference_missing_or_uuid_substituted';
  end if;
  select coalesce(jsonb_agg(x),'[]'::jsonb) into search_rows
    from public.erp_r49_cloud_global_search(c,car_reference,20) x;
  if not exists(select 1 from jsonb_array_elements(search_rows) x
      where x->>'id'='r49-reference-car') then
    raise exception 'car_business_reference_search_failed:%',search_rows;
  end if;
  select coalesce(jsonb_agg(x),'[]'::jsonb) into search_rows
    from public.erp_r49_cloud_global_search(c,product_reference,20) x;
  if not exists(select 1 from jsonb_array_elements(search_rows) x
      where x->>'id'='r49-reference-product') then
    raise exception 'product_business_reference_search_failed:%',search_rows;
  end if;
  select coalesce(jsonb_agg(x),'[]'::jsonb) into search_rows
    from public.erp_r49_cloud_global_search(c,opportunity_reference,20) x;
  if not exists(select 1 from jsonb_array_elements(search_rows) x
      where x->>'id'='r49-runtime-opportunity') then
    raise exception 'opportunity_business_reference_search_failed:%',search_rows;
  end if;
  if (select opportunity_id from public.erp_sales_orders_cloud where id=so)<>'r49-runtime-opportunity'
     or (select x->>'id' from public.erp_r9_find_sales_order_by_opportunity(c,'r49-runtime-opportunity') x limit 1)<>so::text then
    raise exception 'opportunity_sales_order_bidirectional_link_failed';
  end if;
  opportunity_state := (select x from jsonb_array_elements(public.erp_r49_opportunity_command('list','{}')) x
    where x->>'id'='r49-runtime-opportunity');
  if opportunity_state->>'status'<>'pending'
     or opportunity_state->>'stage'<>'proposal'
     or opportunity_state->>'salesOrderStatus'<>'draft'
     or opportunity_state->>'deliveryId' is not null
     or opportunity_state->>'invoiceId' is not null
     or opportunity_state->>'paymentStatus'<>'not_invoiced' then
    raise exception 'r55_1_sales_order_draft_must_remain_pending:%',opportunity_state;
  end if;
  select count(*) into movement_count_before from public.erp_inventory_movements
    where company_id=c and not is_deleted;
  select count(*) into journal_count_before from public.erp_journal_entries
    where company_id=c and not is_deleted;
  select count(*) into payment_count_before from public.erp_cash_transactions
    where company_id=c and not is_deleted;
  perform public.erp_r49_approve_sales_order(c,so);
  opportunity_state := (select x from jsonb_array_elements(public.erp_r49_opportunity_command('list','{}')) x
    where x->>'id'='r49-runtime-opportunity');
  if opportunity_state->>'salesOrderStatus'<>'approved'
     or opportunity_state->>'salesOrderId'<>so::text
     or opportunity_state->>'status'<>'won'
     or opportunity_state->>'stage'<>'won'
     or (opportunity_state->>'probability')::numeric<>100 then
    raise exception 'r55_1_sales_order_approval_must_immediately_win:%',opportunity_state;
  end if;
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>20
     or (select count(*) from public.erp_commercial_workflow_documents
         where company_id=c and parent_id=so and document_type='delivery' and not is_deleted)<>0
     or (select count(*) from public.erp_commercial_workflow_documents
         where company_id=c and parent_id=so and document_type='invoice' and not is_deleted)<>0
     or (select count(*) from public.erp_inventory_movements
         where company_id=c and not is_deleted)<>movement_count_before
     or (select count(*) from public.erp_journal_entries
         where company_id=c and not is_deleted)<>journal_count_before
     or (select count(*) from public.erp_cash_transactions
         where company_id=c and not is_deleted)<>payment_count_before then
    raise exception 'r55_1_sales_order_approval_crossed_commercial_boundary';
  end if;
  if (select count(*) from public.erp_enterprise_notifications
      where company_id=c and data->>'type'='opportunity_follow_up'
        and data->>'referenceId'='r49-runtime-opportunity'
        and data->>'userId'='49000000-0000-4000-8000-000000000001')<>1 then
    raise exception 'r55_1_won_notification_not_exactly_once';
  end if;
  -- Reconciliation retries the canonical projection but must upsert the same
  -- deterministic assigned-user follow-up notification.
  perform public.erp_r43_reconcile_opportunity_sales_links(c);
  perform public.erp_r43_reconcile_opportunity_sales_links(c);
  if (select count(*) from public.erp_enterprise_notifications
      where company_id=c and data->>'type'='opportunity_follow_up'
        and data->>'referenceId'='r49-runtime-opportunity'
        and data->>'userId'='49000000-0000-4000-8000-000000000001')<>1 then
    raise exception 'r55_1_won_notification_retry_duplicated';
  end if;
  delivery := public.erp_r49_create_sales_delivery(c,so,'r49-warehouse','runtime delivery');
  perform public.erp_phase2_approve_sales_delivery(c,delivery);
  perform public.erp_r43_reconcile_opportunity_sales_links(c);
  opportunity_state := (select x from jsonb_array_elements(public.erp_r49_opportunity_command('list','{}')) x
    where x->>'id'='r49-runtime-opportunity');
  if opportunity_state->>'deliveryStatus'<>'approved'
     or opportunity_state->>'status'<>'won'
     or opportunity_state->>'stage'<>'won' then
    raise exception 'r55_1_delivery_reverted_won_opportunity:%',opportunity_state;
  end if;
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>5 then raise exception 'sales_delivery_stock_expected_5_actual_%',qty; end if;
  select count(*) into movements from public.erp_inventory_movements
    where company_id=c and data->>'movementType'='sale_out'
      and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if movements<>1 then raise exception 'sales_delivery_movement_expected_1_actual_%',movements; end if;
  select coalesce(sum(quantity),0),coalesce(sum(total_cost),0),count(*)
    into fifo_quantity,fifo_cost,layers
  from public.erp_inventory_fifo_consumptions
  where company_id=c and delivery_id=delivery and status='active';
  select coalesce(sum(remaining_quantity*unit_cost),0) into inventory_value
  from public.erp_inventory_cost_layers
  where company_id=c and item_type='product' and item_id='r49-product'
    and status in ('active','consumed');
  if fifo_quantity<>15 or fifo_cost<>175 or layers<>2 or inventory_value<>75
     or exists(select 1 from public.erp_journal_entries
       where company_id=c and data->>'referenceId'=delivery::text and not is_deleted)
     or exists(select 1 from public.erp_inventory_fifo_consumptions
       where company_id=c and delivery_id=delivery and journal_entry_id is not null) then
    raise exception 'sales_delivery_operational_valuation_expected_qty_15_cost_175_value_75_no_gl';
  end if;
  layer_count_before:=layers;
  perform public.erp_phase2_approve_sales_delivery(c,delivery);
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  select count(*) into movements from public.erp_inventory_movements
    where company_id=c and data->>'movementType'='sale_out'
      and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>5 or movements<>1
     or (select coalesce(sum(quantity),0) from public.erp_inventory_fifo_consumptions
         where company_id=c and delivery_id=delivery and status='active')<>15
     or (select coalesce(sum(total_cost),0) from public.erp_inventory_fifo_consumptions
         where company_id=c and delivery_id=delivery and status='active')<>175
     or (select coalesce(sum(remaining_quantity*unit_cost),0) from public.erp_inventory_cost_layers
         where company_id=c and item_type='product' and item_id='r49-product'
           and status in ('active','consumed'))<>75 then
    raise exception 'sales_delivery_retry_not_idempotent:qty=% movements=%',qty,movements;
  end if;

  si := public.erp_create_cloud_sales_workflow_invoice(c,so);
  result := public.erp_r22_approve_sales_invoice(c,si);
  if coalesce((result->>'ok')::boolean,false) is not true then raise exception 'sales_invoice_failed:%',result; end if;
  sales_journal := result->>'journalEntryId';
  perform public.erp_v762_assert_posted_journal_balanced(c,sales_journal,'r49_runtime_sales');
  if (select coalesce(sum(public.erp_try_numeric(data->>'debit',0)),0) from public.erp_journal_lines
      where company_id=c and data->>'entryId'=sales_journal and data->>'accountId'='r49-customer-usd' and not is_deleted)<>300
     or (select coalesce(sum(public.erp_try_numeric(data->>'credit',0)),0) from public.erp_journal_lines
      where company_id=c and data->>'entryId'=sales_journal and data->>'accountId'='r49-revenue-usd' and not is_deleted)<>300 then
    raise exception 'sales_revenue_or_customer_account_lines_incorrect';
  end if;
  cost_journal := (select value->>'journalEntryId' from jsonb_array_elements(
    (select payload->'costJournalEntries' from public.erp_commercial_workflow_documents where id=si)) limit 1);
  if cost_journal is null
     or (select coalesce(sum(public.erp_try_numeric(data->>'debit',0)),0) from public.erp_journal_lines
      where company_id=c and data->>'entryId'=cost_journal and data->>'accountId'='r49-cogs-usd' and not is_deleted)<>175
     or (select coalesce(sum(public.erp_try_numeric(data->>'credit',0)),0) from public.erp_journal_lines
      where company_id=c and data->>'entryId'=cost_journal and data->>'accountId'='r49-inventory-usd' and not is_deleted)<>175
     or (select count(*) from public.erp_inventory_fifo_consumptions
         where company_id=c and delivery_id=delivery and status='active'
           and journal_entry_id=cost_journal)<>2 then
    raise exception 'sales_cogs_or_inventory_account_lines_incorrect:%',cost_journal;
  end if;
  perform public.erp_r43_reconcile_opportunity_sales_links(c);
  opportunity_state := (select x from jsonb_array_elements(public.erp_r49_opportunity_command('list','{}')) x
    where x->>'id'='r49-runtime-opportunity');
  if opportunity_state->>'invoiceStatus'<>'approved'
     or opportunity_state->>'status'<>'won'
     or opportunity_state->>'stage'<>'won' then
    raise exception 'r55_1_invoice_reverted_or_first_won_event:%',opportunity_state;
  end if;
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>5 then raise exception 'sales_invoice_changed_stock:%',qty; end if;
  select count(*) into layers from public.erp_inventory_fifo_consumptions
    where company_id=c and delivery_id=delivery and status='active';
  if layers<>2 then raise exception 'sales_invoice_fifo_consumption_expected_2_actual_%',layers; end if;
  if (select coalesce(sum(total_cost),0) from public.erp_inventory_fifo_consumptions
      where company_id=c and delivery_id=delivery and status='active')<>175 then
    raise exception 'sales_invoice_fifo_cogs_expected_175';
  end if;
  if not exists(
    select 1 from public.erp_inventory_cost_layers
    where company_id=c and receipt_id=receipt and remaining_quantity=0 and status='consumed'
  ) or not exists(
    select 1 from public.erp_inventory_cost_layers
    where company_id=c and receipt_id=receipt2 and remaining_quantity=5 and status='active'
  ) then raise exception 'sales_invoice_fifo_remaining_layers_incorrect'; end if;
  select coalesce(sum(remaining_quantity*unit_cost),0) into inventory_value
    from public.erp_inventory_cost_layers
    where company_id=c and item_type='product' and item_id='r49-product'
      and remaining_quantity>0 and status in ('active','consumed');
  if inventory_value<>75 or layers<>layer_count_before or qty<>5 then
    raise exception 'sales_remaining_inventory_value_expected_75_actual_%',inventory_value;
  end if;
  begin
    perform public.erp_pay_cloud_sales_workflow_invoice(c,si,jsonb_build_object(
      'paymentKey','r49-sales-fx-invalid','cashAccountId','r49-cash-iqd',
      'paymentCurrency','IQD','invoiceAmount',300,'cashAmount',450000,'exchangeRate',1500,
      'paymentDate','2026-08-10T10:30:00Z','settlementMode','full'
    ));
    raise exception 'invalid_cross_currency_payment_unexpected_success';
  exception when sqlstate 'P0001' then
    get stacked diagnostics error_detail = pg_exception_detail;
    if sqlerrm<>'workflow_payment_failed'
       or error_detail not like '%linked_invoice_currency_cashbox_required%' then raise; end if;
  end;
  insert into public.erp_cash_account_links(company_id,source_cash_account_id,target_cash_account_id)
    values(c,'r49-cash-iqd','r49-cash-usd');
  perform public.erp_pay_cloud_sales_workflow_invoice(c,si,jsonb_build_object(
    'paymentKey','r49-sales-fx','cashAccountId','r49-cash-iqd','linkedCashAccountId','r49-cash-usd',
    'paymentCurrency','IQD','invoiceAmount',300,'cashAmount',450000,'exchangeRate',1500,
    'paymentDate','2026-08-10T10:30:00Z','settlementMode','full'
  ));
  if (select payload->>'paymentStatus' from public.erp_commercial_workflow_documents where id=si)<>'paid'
     or (select count(*) from public.erp_cash_transactions where company_id=c and data->>'paymentKey'='r49-sales-fx' and not is_deleted)<>1 then
    raise exception 'sales_cross_currency_payment_state_incorrect';
  end if;
  payment_journal := (select data->>'journalEntryId' from public.erp_cash_transactions
    where company_id=c and data->>'paymentKey'='r49-sales-fx' and not is_deleted limit 1);
  if payment_journal is null
     or (select data->>'amount' from public.erp_cash_transactions
      where company_id=c and data->>'paymentKey'='r49-sales-fx' and not is_deleted limit 1)::numeric<>300
     or (select data->>'currency' from public.erp_cash_transactions
      where company_id=c and data->>'paymentKey'='r49-sales-fx' and not is_deleted limit 1)<>'USD'
     or (select data->>'cashAccountId' from public.erp_cash_transactions
      where company_id=c and data->>'paymentKey'='r49-sales-fx' and not is_deleted limit 1)<>'r49-cash-usd'
     or (select coalesce(sum(public.erp_try_numeric(data->>'debit',0)),0) from public.erp_journal_lines
      where company_id=c and data->>'entryId'=payment_journal and data->>'accountId'='r49-cash-usd-ledger' and not is_deleted)<>300
     or (select coalesce(sum(public.erp_try_numeric(data->>'credit',0)),0) from public.erp_journal_lines
      where company_id=c and data->>'entryId'=payment_journal and data->>'accountId'='r49-customer-usd' and not is_deleted)<>300
     or not exists(select 1 from jsonb_array_elements(
        (select payload->'payments' from public.erp_commercial_workflow_documents where id=si)) p
        where p->>'paymentKey'='r49-sales-fx' and (p->>'invoiceAmount')::numeric=300
          and (p->>'cashAmount')::numeric=450000 and (p->>'exchangeRate')::numeric=1500
          and p->>'cashAccountId'='r49-cash-iqd' and p->>'linkedCashAccountId'='r49-cash-usd')
     or exists(select 1 from public.erp_journal_lines
        where company_id=c and data->>'entryId'=payment_journal and not is_deleted
          and lower(data::text) like '%ledger difference%') then
    raise exception 'sales_fx_exact_cash_conversion_or_journal_lines_incorrect:%',payment_journal;
  end if;
  perform public.erp_r43_reconcile_opportunity_sales_links(c);
  opportunity_state := (select x from jsonb_array_elements(public.erp_r49_opportunity_command('list','{}')) x
    where x->>'id'='r49-runtime-opportunity');
  if opportunity_state->>'paymentStatus'<>'paid'
     or (opportunity_state->>'paidAmount')::numeric<>300
     or (opportunity_state->>'remainingAmount')::numeric<>0
     or opportunity_state->>'status'<>'won'
     or opportunity_state->>'stage'<>'closed' then
    raise exception 'opportunity_payment_projection_stale:%',opportunity_state;
  end if;
  perform public.erp_pay_cloud_sales_workflow_invoice(c,si,jsonb_build_object(
    'paymentKey','r49-sales-fx','cashAccountId','r49-cash-iqd','linkedCashAccountId','r49-cash-usd',
    'paymentCurrency','IQD','invoiceAmount',300,'cashAmount',450000,'exchangeRate',1500,
    'paymentDate','2026-08-10T10:30:00Z','settlementMode','full'
  ));
  if (select count(*) from public.erp_cash_transactions where company_id=c and data->>'paymentKey'='r49-sales-fx' and not is_deleted)<>1 then
    raise exception 'sales_fx_payment_retry_duplicated_cash_transaction';
  end if;
  if (select count(*) from public.erp_journal_entries
      where company_id=c and id=payment_journal and not is_deleted)<>1 then
    raise exception 'sales_fx_payment_retry_duplicated_journal';
  end if;
  result := public.erp_r22_approve_sales_invoice(c,si);
  if coalesce((result->>'idempotent')::boolean,false) is not true then raise exception 'sales_invoice_retry_not_idempotent:%',result; end if;

  -- Draft deletion is the supported cancellable Sales Order path. It owns the
  -- canonical Lost projection and uses the existing R55 follow-up channel.
  cancel_opportunity:=public.erp_r49_opportunity_command('save',jsonb_build_object(
    'create_only',true,'record',jsonb_build_object(
      'id','r55-1-cancel-opportunity','customerId','49000000-0000-4000-8000-000000000020',
      'customerName','R49 Customer','title','R55.1 cancellation','stage','qualified',
      'status','pending','probability',60,
      'assignedUserId','49000000-0000-4000-8000-000000000001',
      'assignedUserName','R49 Admin'
    )
  ));
  cancel_order:=public.erp_r49_create_sales_order(c,jsonb_build_object(
    'customerId','49000000-0000-4000-8000-000000000020',
    'opportunityId','r55-1-cancel-opportunity','currency','USD','exchangeRate',1,
    'discount',0,'effectiveAt','2026-08-10T10:45:00Z',
    'items',jsonb_build_array(jsonb_build_object(
      'itemType','product','itemId','r49-product','description','R49 Product',
      'quantity',1,'unitPrice',20
    ))
  ));
  perform public.erp_delete_cloud_sales_order_v4(c,cancel_order);
  cancel_opportunity:=(select x from jsonb_array_elements(
    public.erp_r49_opportunity_command('list','{}')) x
    where x->>'id'='r55-1-cancel-opportunity');
  if cancel_opportunity->>'status'<>'lost'
     or cancel_opportunity->>'stage'<>'lost'
     or (cancel_opportunity->>'probability')::numeric<>0
     or cancel_opportunity->>'salesOrderStatus'<>'deleted' then
    raise exception 'r55_1_sales_order_cancellation_not_lost:%',cancel_opportunity;
  end if;
  perform public.erp_r43_reconcile_opportunity_sales_links(c);
  perform public.erp_r43_reconcile_opportunity_sales_links(c);
  if (select count(*) from public.erp_enterprise_notifications
      where company_id=c and data->>'type'='opportunity_follow_up'
        and data->>'referenceId'='r55-1-cancel-opportunity'
        and data->>'userId'='49000000-0000-4000-8000-000000000001')<>1 then
    raise exception 'r55_1_lost_notification_retry_not_exactly_once';
  end if;

  insert into public.erp_sales_orders_cloud(
    id,company_id,order_number,customer_id,status,currency,exchange_rate,subtotal,discount,total
  ) values(
    '49000000-0000-4000-8000-000000000030',c,'R49-SOLD-CAR',
    '49000000-0000-4000-8000-000000000020','completed','USD',1,1000,0,1000
  );
  insert into public.erp_sales_order_items_cloud(
    company_id,order_id,item_type,item_id,description,quantity,unit_price,line_total
  ) values(c,'49000000-0000-4000-8000-000000000030','car','r49-sold-car','R49 Sold Car',1,1000,1000);
  insert into public.erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,status,payload
  ) values(
    '49000000-0000-4000-8000-000000000031',c,'sales','invoice',
    '49000000-0000-4000-8000-000000000030','R49-SOLD-INVOICE','approved','{"currency":"USD","totalAmount":1000}'
  );
  mo := public.erp_r49_create_cloud_maintenance_order(
    c,'r49-sold-car','r49-warehouse','paid',10,100,'USD',1,'runtime maintenance',
    jsonb_build_array(jsonb_build_object(
      'product_id','r49-product','quantity',2,'warehouse_id','r49-warehouse','unit_price',20
    )),'r49-maintenance-expense','2026-08-10T11:00:00Z'
  );
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>5 then raise exception 'maintenance_order_creation_changed_stock:%',qty; end if;
  maintenance_result := public.erp_r37_advance_maintenance_workflow(c,mo);
  maintenance_result := public.erp_r37_advance_maintenance_workflow(c,mo);
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>5 then raise exception 'maintenance_pre_issue_changed_stock:%',qty; end if;
  maintenance_result := public.erp_r37_advance_maintenance_workflow(c,mo);
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>3 then raise exception 'maintenance_issue_stock_expected_3_actual_%',qty; end if;
  select count(*) into movements from public.erp_inventory_movements
    where company_id=c and data->>'movementType'='maintenance_out'
      and data->>'referenceId'=mo::text and not is_deleted;
  if movements<>1 then raise exception 'maintenance_issue_movement_expected_1_actual_%',movements; end if;
  select coalesce(sum(quantity),0),coalesce(sum(total_cost),0),count(*)
    into fifo_quantity,fifo_cost,layers
  from public.erp_inventory_fifo_consumptions
  where company_id=c and delivery_id=mo and sales_order_id=mo and status='active';
  select coalesce(sum(remaining_quantity*unit_cost),0) into inventory_value
  from public.erp_inventory_cost_layers
  where company_id=c and item_type='product' and item_id='r49-product'
    and status in ('active','consumed');
  if fifo_quantity<>2 or fifo_cost<>30 or layers<>1 or inventory_value<>45
     or (select invoice_journal_entry_id from public.erp_maintenance_orders where id=mo) is not null
     or exists(select 1 from public.erp_inventory_fifo_consumptions
       where company_id=c and delivery_id=mo and journal_entry_id is not null) then
    raise exception 'maintenance_issue_operational_valuation_expected_qty_2_cost_30_value_45_no_gl';
  end if;
  layer_count_before:=layers;
  maintenance_result := public.erp_r37_advance_maintenance_workflow(c,mo);
  if (select workflow_stage from public.erp_maintenance_orders where id=mo)<>'invoice_draft'
     or (select public.erp_try_numeric(data->>'quantity',0) from public.erp_warehouse_stock
         where company_id=c and data->>'productId'='r49-product'
           and data->>'warehouseId'='r49-warehouse' and not is_deleted)<>3
     or (select coalesce(sum(quantity),0) from public.erp_inventory_fifo_consumptions
         where company_id=c and delivery_id=mo and status='active')<>2
     or (select coalesce(sum(total_cost),0) from public.erp_inventory_fifo_consumptions
         where company_id=c and delivery_id=mo and status='active')<>30
     or (select coalesce(sum(remaining_quantity*unit_cost),0) from public.erp_inventory_cost_layers
         where company_id=c and item_type='product' and item_id='r49-product'
           and status in ('active','consumed'))<>45 then
    raise exception 'maintenance_issue_retry_boundary_not_idempotent';
  end if;
  maintenance_result := public.erp_r37_advance_maintenance_workflow(c,mo);
  if (select workflow_stage from public.erp_maintenance_orders where id=mo)<>'invoice_approved'
     or (select invoice_journal_entry_id from public.erp_maintenance_orders where id=mo) is null then
    raise exception 'maintenance_invoice_not_approved_or_journal_missing';
  end if;
  perform public.erp_v762_assert_posted_journal_balanced(
    c,(select invoice_journal_entry_id from public.erp_maintenance_orders where id=mo),'r49_runtime_maintenance'
  );
  select cost_journal_entry_ids->0->>'journalEntryId' into cost_journal
  from public.erp_maintenance_orders where id=mo;
  if cost_journal is null
     or (select coalesce(sum(quantity),0) from public.erp_inventory_fifo_consumptions
         where company_id=c and delivery_id=mo and sales_order_id=mo and status='active')<>2
     or (select coalesce(sum(total_cost),0) from public.erp_inventory_fifo_consumptions
         where company_id=c and delivery_id=mo and sales_order_id=mo and status='active')<>30
     or (select count(*) from public.erp_inventory_fifo_consumptions
         where company_id=c and delivery_id=mo and sales_order_id=mo and status='active'
           and journal_entry_id=cost_journal)<>1 then
    raise exception 'maintenance_fifo_accounting_trace_expected_qty_2_cost_30_journal_%',cost_journal;
  end if;
  perform public.erp_v762_assert_posted_journal_balanced(
    c,cost_journal,'r49_runtime_maintenance_fifo_cost'
  );
  if (select public.erp_try_numeric(data->>'quantity',0) from public.erp_warehouse_stock
      where company_id=c and data->>'productId'='r49-product'
        and data->>'warehouseId'='r49-warehouse' and not is_deleted)<>3
     or (select count(*) from public.erp_inventory_fifo_consumptions
         where company_id=c and delivery_id=mo and status='active')<>layer_count_before
     or (select coalesce(sum(total_cost),0) from public.erp_inventory_fifo_consumptions
         where company_id=c and delivery_id=mo and status='active')<>30
     or (select coalesce(sum(remaining_quantity*unit_cost),0) from public.erp_inventory_cost_layers
         where company_id=c and item_type='product' and item_id='r49-product'
           and status in ('active','consumed'))<>45 then
    raise exception 'maintenance_invoice_mutated_operational_valuation';
  end if;
  maintenance_result := public.erp_v736_post_maintenance_invoice(c,mo);
  if (select count(*) from public.erp_inventory_movements
      where company_id=c and data->>'movementType'='maintenance_out'
        and data->>'referenceId'=mo::text and not is_deleted)<>1 then
    raise exception 'maintenance_invoice_retry_duplicated_issue';
  end if;
  maintenance_result := public.erp_v2300_record_maintenance_payment_batch(c,mo,jsonb_build_array(jsonb_build_object(
    'paymentKey','r49-maintenance-payment','cashAccountId','r49-cash-usd',
    'paymentCurrency','USD','invoiceAmount',100,'cashAmount',100,'exchangeRate',1,
    'paymentDate','2026-08-10T11:30:00Z','settlementMode','full'
  )));
  if (select paid_amount from public.erp_maintenance_orders where id=mo)<>100
     or (select count(*) from public.erp_cash_transactions
         where company_id=c and data->>'paymentKey'='r49-maintenance-payment' and not is_deleted)<>1 then
    raise exception 'maintenance_payment_state_incorrect';
  end if;
  maintenance_result := public.erp_v2300_record_maintenance_payment_batch(c,mo,jsonb_build_array(jsonb_build_object(
    'paymentKey','r49-maintenance-payment','cashAccountId','r49-cash-usd',
    'paymentCurrency','USD','invoiceAmount',100,'cashAmount',100,'exchangeRate',1,
    'paymentDate','2026-08-10T11:30:00Z','settlementMode','full'
  )));
  if (select count(*) from public.erp_cash_transactions
      where company_id=c and data->>'paymentKey'='r49-maintenance-payment' and not is_deleted)<>1 then
    raise exception 'maintenance_payment_retry_duplicated_cash_transaction';
  end if;
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>3 then raise exception 'maintenance_invoice_repeated_stock:%',qty; end if;

  select coalesce(sum(remaining_quantity*unit_cost),0) into inventory_value
    from public.erp_inventory_cost_layers
    where company_id=c and item_type='product' and item_id='r49-product'
      and remaining_quantity>0 and status in ('active','consumed');
  if inventory_value<>45 then
    raise exception 'maintenance_remaining_inventory_value_expected_45_actual_%',inventory_value;
  end if;

  transfer_id:=public.erp_r49_transfer_inventory_stock(
    c,'r49-product','r49-warehouse','r49-destination-warehouse',1,
    'R49 company-value-preserving transfer'
  );
  if transfer_id is null
     or (select public.erp_try_numeric(data->>'quantity',0)
         from public.erp_warehouse_stock
         where company_id=c and data->>'productId'='r49-product'
           and data->>'warehouseId'='r49-warehouse' and not is_deleted)<>2
     or (select public.erp_try_numeric(data->>'quantity',0)
         from public.erp_warehouse_stock
         where company_id=c and data->>'productId'='r49-product'
           and data->>'warehouseId'='r49-destination-warehouse' and not is_deleted)<>1
     or (select coalesce(sum(public.erp_try_numeric(data->>'quantity',0)),0)
         from public.erp_warehouse_stock
         where company_id=c and data->>'productId'='r49-product' and not is_deleted)<>3
     or (select coalesce(sum(
           public.erp_try_numeric(data->>'quantity',0)
           * public.erp_try_numeric(data->>'averageUnitCost',0)
         ),0) from public.erp_warehouse_stock
         where company_id=c and data->>'productId'='r49-product' and not is_deleted)<>45
     or (select coalesce(sum(remaining_quantity*unit_cost),0)
         from public.erp_inventory_cost_layers
         where company_id=c and item_type='product' and item_id='r49-product'
           and remaining_quantity>0 and status in ('active','consumed'))<>45
     or (select count(*) from public.erp_inventory_movements
         where company_id=c and data->>'referenceType'='warehouse_transfer'
           and data->>'referenceId'=transfer_id and not is_deleted)<>2 then
    raise exception 'warehouse_transfer_changed_company_quantity_or_value:%',transfer_id;
  end if;

  -- Duplicate product lines are accepted by the maintenance input contract.
  -- The final line receives the exact currency remainder, so line totals must
  -- reconcile exactly to the FIFO consumption total without cent drift.
  mo := public.erp_r49_create_cloud_maintenance_order(
    c,'r49-sold-car','r49-warehouse','paid',0,50,'USD',1,'R54 rounding allocation',
    jsonb_build_array(
      jsonb_build_object('product_id','r49-product','quantity',1,'warehouse_id','r49-warehouse','unit_price',20),
      jsonb_build_object('product_id','r49-product','quantity',1,'warehouse_id','r49-warehouse','unit_price',20)
    ),'r49-maintenance-expense','2026-08-10T12:00:00Z'
  );
  maintenance_result:=public.erp_r37_advance_maintenance_workflow(c,mo);
  maintenance_result:=public.erp_r37_advance_maintenance_workflow(c,mo);
  maintenance_result:=public.erp_r37_advance_maintenance_workflow(c,mo);
  if (select count(*) from public.erp_maintenance_parts
      where company_id=c and maintenance_order_id=mo and not is_deleted and line_type<>'service')<>2
     or (select coalesce(sum(total_cost),0) from public.erp_maintenance_parts
         where company_id=c and maintenance_order_id=mo and not is_deleted and line_type<>'service')<>30
     or (select coalesce(sum(total_cost),0) from public.erp_inventory_fifo_consumptions
         where company_id=c and delivery_id=mo and status='active')<>30 then
    raise exception 'maintenance_multiline_fifo_rounding_expected_exact_30';
  end if;
end
$runtime$;

rollback;
