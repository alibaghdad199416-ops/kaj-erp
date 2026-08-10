\set ON_ERROR_STOP on
\pset pager off

-- Canonical R49 ERP transaction proof. This test runs only inside the
-- repository-owned disposable local database and rolls every fixture back.
begin;
set local session_replication_role=replica;

insert into auth.users(
  instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,
  raw_app_meta_data,raw_user_meta_data,created_at,updated_at
) values (
  '00000000-0000-0000-0000-000000000000','49000000-0000-4000-8000-000000000001',
  'authenticated','authenticated','r49-runtime@local.invalid','',now(),'{}','{}',now(),now()
);

insert into public.companies(id,slug,name_ar,name_en,is_active) values
  ('49000000-0000-4000-8000-000000000010','r49-runtime','R49 محلي','R49 local',true);
insert into public.company_memberships(
  company_id,user_id,user_uid,user_email,role_code,is_system_admin,is_active
) values (
  '49000000-0000-4000-8000-000000000010','49000000-0000-4000-8000-000000000001',
  '49000000-0000-4000-8000-000000000001','r49-runtime@local.invalid','admin',true,true
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
  ('49000000-0000-4000-8000-000000000010','r49-maintenance-expense','52001','R49 maintenance expense','expense','USD',0,true,now(),now(),'49000000-0000-4000-8000-000000000001');

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
  opportunity jsonb; opportunities jsonb;
  qty numeric; movements integer; layers integer; journals integer;
  movement_rows jsonb;
  purchase_journal text; sales_journal text;
  error_detail text;
begin
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
  perform public.erp_phase2_approve_purchase_receipt(c,receipt);
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  select count(*) into movements from public.erp_inventory_movements
    where company_id=c and data->>'movementType'='purchase_in'
      and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>10 or movements<>1 then raise exception 'purchase_receipt_retry_not_idempotent:qty=% movements=%',qty,movements; end if;

  pi := public.erp_create_cloud_purchase_workflow_invoice(c,po);
  result := public.erp_r22_approve_purchase_invoice(c,pi);
  if coalesce((result->>'ok')::boolean,false) is not true then raise exception 'purchase_invoice_failed:%',result; end if;
  purchase_journal := result->>'journalEntryId';
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>10 then raise exception 'purchase_invoice_changed_stock:%',qty; end if;
  select count(*) into layers from public.erp_inventory_cost_layers where company_id=c and receipt_id=receipt;
  if layers<>1 then raise exception 'purchase_invoice_layer_expected_1_actual_%',layers; end if;
  perform public.erp_v762_assert_posted_journal_balanced(c,purchase_journal,'r49_runtime_purchase');
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
  perform public.erp_pay_cloud_purchase_workflow_invoice(c,pi,jsonb_build_object(
    'paymentKey','r49-purchase-payment','cashAccountId','r49-cash-usd',
    'paymentCurrency','USD','invoiceAmount',100,'cashAmount',100,'exchangeRate',1,
    'paymentDate','2026-08-10T08:30:00Z','settlementMode','full'
  ));
  if (select count(*) from public.erp_cash_transactions where company_id=c and data->>'paymentKey'='r49-purchase-payment' and not is_deleted)<>1 then
    raise exception 'purchase_payment_retry_duplicated_cash_transaction';
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
  pi2 := public.erp_create_cloud_purchase_workflow_invoice(c,po2);
  result := public.erp_r22_approve_purchase_invoice(c,pi2);
  if coalesce((result->>'ok')::boolean,false) is not true then raise exception 'second_purchase_invoice_failed:%',result; end if;
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>20 then raise exception 'two_purchase_receipts_stock_expected_20_actual_%',qty; end if;

  so := public.erp_r49_create_sales_order(c,jsonb_build_object(
    'customerId','49000000-0000-4000-8000-000000000020','currency','USD','exchangeRate',1,'discount',0,
    'effectiveAt','2026-08-10T10:00:00Z','items',jsonb_build_array(jsonb_build_object(
      'itemType','product','itemId','r49-product','description','R49 Product',
      'quantity',15,'unitPrice',20
    ))
  ));
  perform public.erp_r49_approve_sales_order(c,so);
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>20 then raise exception 'sales_order_approval_changed_stock:%',qty; end if;
  delivery := public.erp_r49_create_sales_delivery(c,so,'r49-warehouse','runtime delivery');
  perform public.erp_phase2_approve_sales_delivery(c,delivery);
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>5 then raise exception 'sales_delivery_stock_expected_5_actual_%',qty; end if;
  select count(*) into movements from public.erp_inventory_movements
    where company_id=c and data->>'movementType'='sale_out'
      and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if movements<>1 then raise exception 'sales_delivery_movement_expected_1_actual_%',movements; end if;
  perform public.erp_phase2_approve_sales_delivery(c,delivery);
  select public.erp_try_numeric(data->>'quantity',0) into qty from public.erp_warehouse_stock
    where company_id=c and data->>'productId'='r49-product' and data->>'warehouseId'='r49-warehouse' and not is_deleted;
  if qty<>5 then raise exception 'sales_delivery_retry_not_idempotent:%',qty; end if;

  si := public.erp_create_cloud_sales_workflow_invoice(c,so);
  result := public.erp_r22_approve_sales_invoice(c,si);
  if coalesce((result->>'ok')::boolean,false) is not true then raise exception 'sales_invoice_failed:%',result; end if;
  sales_journal := result->>'journalEntryId';
  perform public.erp_v762_assert_posted_journal_balanced(c,sales_journal,'r49_runtime_sales');
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
  perform public.erp_pay_cloud_sales_workflow_invoice(c,si,jsonb_build_object(
    'paymentKey','r49-sales-fx','cashAccountId','r49-cash-iqd','linkedCashAccountId','r49-cash-usd',
    'paymentCurrency','IQD','invoiceAmount',300,'cashAmount',450000,'exchangeRate',1500,
    'paymentDate','2026-08-10T10:30:00Z','settlementMode','full'
  ));
  if (select count(*) from public.erp_cash_transactions where company_id=c and data->>'paymentKey'='r49-sales-fx' and not is_deleted)<>1 then
    raise exception 'sales_fx_payment_retry_duplicated_cash_transaction';
  end if;
  result := public.erp_r22_approve_sales_invoice(c,si);
  if coalesce((result->>'idempotent')::boolean,false) is not true then raise exception 'sales_invoice_retry_not_idempotent:%',result; end if;

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
  maintenance_result := public.erp_r37_advance_maintenance_workflow(c,mo);
  maintenance_result := public.erp_r37_advance_maintenance_workflow(c,mo);
  if (select workflow_stage from public.erp_maintenance_orders where id=mo)<>'invoice_approved'
     or (select invoice_journal_entry_id from public.erp_maintenance_orders where id=mo) is null then
    raise exception 'maintenance_invoice_not_approved_or_journal_missing';
  end if;
  perform public.erp_v762_assert_posted_journal_balanced(
    c,(select invoice_journal_entry_id from public.erp_maintenance_orders where id=mo),'r49_runtime_maintenance'
  );
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
end
$runtime$;

rollback;
