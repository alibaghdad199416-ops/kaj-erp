-- Quality Line ERP 18.9.6 / V7.3.6
-- Invoice-owned valuation/accounting, quantity-only logistics, two-currency
-- revenue bindings, maintenance invoice posting, and two-way opportunity state.
begin;

alter table public.erp_maintenance_orders
  add column if not exists invoice_journal_entry_id text,
  add column if not exists cost_journal_entry_ids jsonb not null default '[]'::jsonb,
  add column if not exists accounting_payload jsonb not null default '{}'::jsonb;

create or replace function public.erp_v736_ensure_currency_revenue_accounts(
  p_company_id uuid
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_parent text;
  v_iqd text := 'v736-revenue-iqd-'||substr(md5(p_company_id::text),1,14);
  v_usd text := 'v736-revenue-usd-'||substr(md5(p_company_id::text),1,14);
  v_maint_iqd text := 'v736-maint-revenue-iqd-'||substr(md5(p_company_id::text),1,12);
  v_maint_usd text := 'v736-maint-revenue-usd-'||substr(md5(p_company_id::text),1,12);
begin
  perform public.erp_seed_default_accounts(p_company_id);
  select account_id into v_parent from public.erp_accounts
   where organization_id=p_company_id and code='4100' and is_active limit 1;
  if v_parent is null then raise exception 'revenue_account_parent_missing'; end if;

  insert into public.erp_accounts(
    organization_id,account_id,code,name,account_type,parent_account_id,
    currency,opening_balance,is_active,source_updated_at,synced_at,synced_by
  ) values
    (p_company_id,v_iqd,'4191','إيراد مبيعات المنتجات والسيارات - دينار','revenue',v_parent,'IQD',0,true,now(),now(),auth.uid()),
    (p_company_id,v_usd,'4192','إيراد مبيعات المنتجات والسيارات - دولار','revenue',v_parent,'USD',0,true,now(),now(),auth.uid()),
    (p_company_id,v_maint_iqd,'4193','إيراد خدمات الصيانة - دينار','revenue',v_parent,'IQD',0,true,now(),now(),auth.uid()),
    (p_company_id,v_maint_usd,'4194','إيراد خدمات الصيانة - دولار','revenue',v_parent,'USD',0,true,now(),now(),auth.uid())
  on conflict(organization_id,code) do update set
    name=excluded.name,account_type='revenue',parent_account_id=excluded.parent_account_id,
    currency=excluded.currency,is_active=true,synced_at=now(),synced_by=auth.uid();

  select account_id into v_iqd from public.erp_accounts where organization_id=p_company_id and code='4191' limit 1;
  select account_id into v_usd from public.erp_accounts where organization_id=p_company_id and code='4192' limit 1;
  select account_id into v_maint_iqd from public.erp_accounts where organization_id=p_company_id and code='4193' limit 1;
  select account_id into v_maint_usd from public.erp_accounts where organization_id=p_company_id and code='4194' limit 1;

  return jsonb_build_object(
    'salesRevenueIqdAccountId',v_iqd,
    'salesRevenueUsdAccountId',v_usd,
    'maintenanceRevenueIqdAccountId',v_maint_iqd,
    'maintenanceRevenueUsdAccountId',v_maint_usd
  );
end;
$$;

create or replace function public.erp_v736_ensure_purchase_clearing_accounts(
  p_company_id uuid
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_parent text;
  v_iqd text:='v736-purchase-clearing-iqd-'||substr(md5(p_company_id::text),1,10);
  v_usd text:='v736-purchase-clearing-usd-'||substr(md5(p_company_id::text),1,10);
begin
  perform public.erp_seed_default_accounts(p_company_id);
  select account_id into v_parent from public.erp_accounts
   where organization_id=p_company_id and code='1300' and is_active limit 1;
  if v_parent is null then raise exception 'inventory_asset_parent_missing'; end if;

  insert into public.erp_accounts(
    organization_id,account_id,code,name,account_type,parent_account_id,
    currency,opening_balance,is_active,source_updated_at,synced_at,synced_by
  ) values
    (p_company_id,v_iqd,'1391','تسوية رسملة المشتريات - دينار','asset',v_parent,'IQD',0,true,now(),now(),auth.uid()),
    (p_company_id,v_usd,'1392','تسوية رسملة المشتريات - دولار','asset',v_parent,'USD',0,true,now(),now(),auth.uid())
  on conflict(organization_id,code) do update set
    name=excluded.name,account_type='asset',parent_account_id=excluded.parent_account_id,
    currency=excluded.currency,is_active=true,synced_at=now(),synced_by=auth.uid();

  select account_id into v_iqd from public.erp_accounts
   where organization_id=p_company_id and code='1391' limit 1;
  select account_id into v_usd from public.erp_accounts
   where organization_id=p_company_id and code='1392' limit 1;
  return jsonb_build_object('IQD',v_iqd,'USD',v_usd);
end;
$$;

create or replace function public.erp_v736_convert_currency(
  p_amount numeric,p_from_currency text,p_to_currency text,p_iqd_per_usd numeric
) returns numeric
language plpgsql immutable as $$
declare v_from text:=upper(p_from_currency); v_to text:=upper(p_to_currency);
begin
  if coalesce(p_amount,0)=0 or v_from=v_to then return coalesce(p_amount,0); end if;
  if coalesce(p_iqd_per_usd,0)<=0 then raise exception 'invalid_exchange_rate'; end if;
  if v_from='IQD' and v_to='USD' then return p_amount/p_iqd_per_usd; end if;
  if v_from='USD' and v_to='IQD' then return p_amount*p_iqd_per_usd; end if;
  raise exception 'unsupported_currency_conversion:%:%',v_from,v_to;
end;
$$;

create or replace function public.erp_v736_item_accounting(
  p_company_id uuid,p_item_type text,p_item_id text,p_invoice_currency text default null
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_data jsonb; v_defaults jsonb; v_revenue_defaults jsonb;
  v_cost_currency text; v_asset text; v_expense text; v_revenue text;
  v_invoice_currency text:=upper(nullif(btrim(coalesce(p_invoice_currency,'')),''));
begin
  if lower(btrim(p_item_type))='car' then
    select data into v_data from public.erp_cars
     where company_id=p_company_id and id=p_item_id and not is_deleted;
  else
    select data into v_data from public.erp_inventory
     where company_id=p_company_id and id=p_item_id and not is_deleted;
  end if;
  if v_data is null then raise exception 'inventory_item_not_found:%',p_item_id; end if;
  if lower(coalesce(v_data->>'itemType',v_data->>'item_type','stock'))='service' then
    raise exception 'service_item_has_no_inventory_posting:%',p_item_id;
  end if;

  v_defaults:=public.erp_v735_ensure_operational_accounts(p_company_id);
  v_revenue_defaults:=public.erp_v736_ensure_currency_revenue_accounts(p_company_id);
  v_cost_currency:=upper(coalesce(
    nullif(v_data->>'costCurrency',''),nullif(v_data->>'cost_currency',''),
    nullif(v_data->>'currency',''),'USD'));
  if v_cost_currency not in ('IQD','USD') then raise exception 'invalid_item_cost_currency:%',p_item_id; end if;

  v_asset:=nullif(coalesce(v_data->>'inventoryAssetAccountId',v_data->>'inventory_asset_account_id'),'');
  v_expense:=nullif(coalesce(
    v_data->>'salesCostExpenseAccountId',v_data->>'sales_cost_expense_account_id',
    v_data->>'costOfSalesAccountId',v_data->>'costOfSaleAccountId',
    v_data->>'cost_of_sales_account_id',v_data->>'cost_of_sale_account_id'),'');
  if not public.erp_v735_account_usable(p_company_id,v_asset,'asset',v_cost_currency) then
    v_asset:=v_defaults->>'inventoryAssetAccountId';
  end if;
  if not public.erp_v735_account_usable(p_company_id,v_expense,'expense',v_cost_currency) then
    v_expense:=v_defaults->>'costExpenseAccountId';
  end if;
  perform public.erp_phase2_account_guard(p_company_id,v_asset,'asset',v_cost_currency);
  perform public.erp_phase2_account_guard(p_company_id,v_expense,'expense',v_cost_currency);

  if v_invoice_currency='IQD' then
    v_revenue:=nullif(coalesce(v_data->>'salesRevenueIqdAccountId',v_data->>'sales_revenue_iqd_account_id'),'');
    if v_revenue is null then v_revenue:=v_revenue_defaults->>'salesRevenueIqdAccountId'; end if;
  elsif v_invoice_currency='USD' then
    v_revenue:=nullif(coalesce(v_data->>'salesRevenueUsdAccountId',v_data->>'sales_revenue_usd_account_id'),'');
    if v_revenue is null then v_revenue:=v_revenue_defaults->>'salesRevenueUsdAccountId'; end if;
  end if;
  if v_invoice_currency is not null then
    if not exists(select 1 from public.erp_accounts a
      where a.organization_id=p_company_id and a.account_id=v_revenue and a.is_active
        and lower(a.account_type)='revenue' and upper(a.currency)=v_invoice_currency) then
      raise exception 'item_revenue_account_required:%:%',p_item_id,v_invoice_currency;
    end if;
  end if;

  return jsonb_build_object(
    'costCurrency',v_cost_currency,'assetAccountId',v_asset,
    'costExpenseAccountId',v_expense,'revenueAccountId',v_revenue,
    'data',v_data
  );
end;
$$;

-- Backfill old master data with explicit IQD/USD revenue bindings while still
-- requiring every future edit to validate the selected account type/currency.
do $$
declare c record; d jsonb;
begin
  for c in select id from public.companies loop
    d:=public.erp_v736_ensure_currency_revenue_accounts(c.id);
    update public.erp_inventory set data=data||jsonb_build_object(
      'salesRevenueIqdAccountId',coalesce(nullif(data->>'salesRevenueIqdAccountId',''),d->>'salesRevenueIqdAccountId'),
      'sales_revenue_iqd_account_id',coalesce(nullif(data->>'sales_revenue_iqd_account_id',''),d->>'salesRevenueIqdAccountId'),
      'salesRevenueUsdAccountId',coalesce(nullif(data->>'salesRevenueUsdAccountId',''),d->>'salesRevenueUsdAccountId'),
      'sales_revenue_usd_account_id',coalesce(nullif(data->>'sales_revenue_usd_account_id',''),d->>'salesRevenueUsdAccountId'),
      'schema_version',greatest(public.erp_try_numeric(data->>'schema_version',0),4),
      'updatedAt',now()),updated_at=now()
    where company_id=c.id and not is_deleted;
    update public.erp_cars set data=data||jsonb_build_object(
      'salesRevenueIqdAccountId',coalesce(nullif(data->>'salesRevenueIqdAccountId',''),d->>'salesRevenueIqdAccountId'),
      'sales_revenue_iqd_account_id',coalesce(nullif(data->>'sales_revenue_iqd_account_id',''),d->>'salesRevenueIqdAccountId'),
      'salesRevenueUsdAccountId',coalesce(nullif(data->>'salesRevenueUsdAccountId',''),d->>'salesRevenueUsdAccountId'),
      'sales_revenue_usd_account_id',coalesce(nullif(data->>'sales_revenue_usd_account_id',''),d->>'salesRevenueUsdAccountId'),
      'schema_version',greatest(public.erp_try_numeric(data->>'schema_version',0),4),
      'updatedAt',now()),updated_at=now()
    where company_id=c.id and not is_deleted;
  end loop;
end $$;

create or replace function public.erp_v736_active_logistics(
  p_company_id uuid,p_order_id uuid,p_module text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_type text; v_result jsonb;
begin
  v_type:=case when p_module='sales' then 'delivery' when p_module='purchases' then 'receipt' else null end;
  if v_type is null then raise exception 'invalid workflow module'; end if;
  select jsonb_build_object(
    'id',d.id::text,'number',d.document_number,'allocations',d.payload->'allocations',
    'effectiveAt',coalesce(d.effective_at,d.created_at),'warehouseIds',d.payload->'warehouseIds'
  ) into v_result
  from public.erp_commercial_workflow_documents d
  where d.company_id=p_company_id and d.parent_id=p_order_id and d.module=p_module
    and d.document_type=v_type and d.status='approved' and not d.is_deleted
    and d.payload ? 'inventoryPostedAt'
  order by d.updated_at desc limit 1;
  if v_result is null then raise exception 'approved_inventory_document_required'; end if;
  perform public.erp_validate_commercial_warehouse_allocations(
    p_company_id,p_order_id,p_module,v_result->'allocations',false);
  return v_result;
end;
$$;

-- Warehouse approval changes only quantity/location/state. No item valuation,
-- FIFO layer, journal, revenue, payable, receivable, or car cost is produced.
create or replace function public.erp_v736_assert_invoice_logistics(
  p_company_id uuid,p_order_id uuid,p_module text,p_logistics_id uuid,
  p_invoice_allocations jsonb
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_active jsonb;
  v_invoice jsonb;
  v_logistics jsonb;
begin
  v_active:=public.erp_v736_active_logistics(p_company_id,p_order_id,p_module);
  if nullif(v_active->>'id','')::uuid is distinct from p_logistics_id then
    raise exception 'invoice_logistics_reference_mismatch';
  end if;
  v_invoice:=public.erp_validate_commercial_warehouse_allocations(
    p_company_id,p_order_id,p_module,p_invoice_allocations,p_module='sales');
  v_logistics:=public.erp_validate_commercial_warehouse_allocations(
    p_company_id,p_order_id,p_module,v_active->'allocations',p_module='sales');

  if exists(
    with invoice_rows as (
      select lower(x."itemType") item_type,x."itemId" item_id,x."warehouseId" warehouse_id,
             sum(x.quantity) quantity
      from jsonb_to_recordset(v_invoice) as x(
        "itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
      group by 1,2,3
    ), logistics_rows as (
      select lower(x."itemType") item_type,x."itemId" item_id,x."warehouseId" warehouse_id,
             sum(x.quantity) quantity
      from jsonb_to_recordset(v_logistics) as x(
        "itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
      group by 1,2,3
    ), differences as (
      (select * from invoice_rows except select * from logistics_rows)
      union all
      (select * from logistics_rows except select * from invoice_rows)
    )
    select 1 from differences
  ) then
    raise exception 'invoice_quantities_must_equal_approved_logistics';
  end if;

  return v_active||jsonb_build_object('invoiceAllocations',v_invoice);
end;
$$;

create or replace function public.erp_approve_cloud_purchase_receipt(
  p_company_id uuid,p_receipt_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare d public.erp_commercial_workflow_documents%rowtype; a record; s public.erp_warehouse_stock%rowtype; v_alloc jsonb; v_qty numeric;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['purchases.approve','purchases.update','purchases.create']);
  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_receipt_id and module='purchases'
     and document_type='receipt' and not is_deleted for update;
  if not found then raise exception 'purchase_receipt_not_found'; end if;
  if d.status='cancelled' then raise exception 'purchase_receipt_cancelled'; end if;
  if d.payload ? 'inventoryPostedAt' then return; end if;
  v_alloc:=public.erp_validate_commercial_warehouse_allocations(
    p_company_id,d.parent_id,'purchases',d.payload->'allocations',false);
  for a in select * from jsonb_to_recordset(v_alloc) as x(
    "itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
  loop
    if a."itemType"='product' then
      s:=public.erp_inventory_ensure_stock(p_company_id,a."warehouseId",a."itemId");
      v_qty:=public.erp_try_numeric(s.data->>'quantity',0);
      update public.erp_warehouse_stock set data=data||jsonb_build_object(
        'quantity',v_qty+a.quantity,'updatedAt',now(),'valuationPendingInvoice',true),
        updated_at=now(),updated_by=auth.uid() where id=s.id;
      perform public.erp_inventory_insert_movement(
        p_company_id,a."itemId",a."warehouseId",'purchase_in',a.quantity,0,
        'purchase_receipt',d.id::text,d.document_number);
      perform public.erp_inventory_refresh_product(p_company_id,a."itemId");
    else
      perform 1 from public.erp_cars where company_id=p_company_id and id=a."itemId" and not is_deleted for update;
      if not found then raise exception 'purchase_car_not_found:%',a."itemId"; end if;
      update public.erp_cars set data=(data-'purchaseOrderId')||jsonb_build_object(
        'status','متوفرة','warehouseId',a."warehouseId",'receivedAt',now(),
        'purchaseReceiptId',d.id::text,'sourcePurchaseOrderId',d.parent_id::text,
        'valuationPendingInvoice',true,'updatedAt',now()),updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=a."itemId";
    end if;
  end loop;
  update public.erp_commercial_workflow_documents set status='approved',
    payload=(payload-'costJournalEntryId'-'fifoCostJournalEntryId')||jsonb_build_object(
      'allocations',v_alloc,'inventoryPostedAt',now(),'inventoryPostedBy',auth.uid(),
      'valuationPendingInvoice',true,'accountingOwner','invoice'),updated_at=now()
  where company_id=p_company_id and id=p_receipt_id;
  perform public.erp_commercial_audit(p_company_id,'purchases',d.parent_id,d.id,d.document_number,
    'approve_receipt',d.status,'approved','quantity-only; valuation owned by invoice');
end;
$$;

create or replace function public.erp_approve_cloud_sales_delivery(
  p_company_id uuid,p_delivery_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare d public.erp_commercial_workflow_documents%rowtype; a record; s public.erp_warehouse_stock%rowtype; v_alloc jsonb; v_available numeric; v_cost numeric;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['sales.approve','sales.update','sales.create']);
  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_delivery_id and module='sales'
     and document_type='delivery' and not is_deleted for update;
  if not found then raise exception 'sales_delivery_not_found'; end if;
  if d.status='cancelled' then raise exception 'sales_delivery_cancelled'; end if;
  if d.payload ? 'inventoryPostedAt' then return; end if;
  v_alloc:=public.erp_validate_commercial_warehouse_allocations(
    p_company_id,d.parent_id,'sales',d.payload->'allocations',true);
  for a in select * from jsonb_to_recordset(v_alloc) as x(
    "itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
  loop
    if a."itemType"='product' then
      s:=public.erp_inventory_ensure_stock(p_company_id,a."warehouseId",a."itemId");
      v_available:=public.erp_try_numeric(s.data->>'quantity',0)-public.erp_try_numeric(s.data->>'reservedQuantity',0);
      if v_available<a.quantity then raise exception 'sales_insufficient_stock:%',a."description"; end if;
      v_cost:=public.erp_try_numeric(s.data->>'averageUnitCost',public.erp_try_numeric(s.data->>'unitCost',0));
      update public.erp_warehouse_stock set data=data||jsonb_build_object(
        'quantity',public.erp_try_numeric(data->>'quantity',0)-a.quantity,'updatedAt',now()),
        updated_at=now(),updated_by=auth.uid() where id=s.id;
      perform public.erp_inventory_insert_movement(
        p_company_id,a."itemId",a."warehouseId",'sale_out',-a.quantity,v_cost,
        'sales_delivery',d.id::text,d.document_number);
      perform public.erp_inventory_refresh_product(p_company_id,a."itemId");
    else
      perform 1 from public.erp_cars where company_id=p_company_id and id=a."itemId" and not is_deleted
        and coalesce(data->>'warehouseId',data->>'warehouse_id')=a."warehouseId" for update;
      if not found then raise exception 'sales_car_not_available:%',a."itemId"; end if;
      update public.erp_cars set data=(data-'warehouseId'-'warehouse_id')||jsonb_build_object(
        'status','قيد البيع','salesOrderId',d.parent_id::text,'lastWarehouseId',a."warehouseId",
        'deliveredAt',now(),'salesDeliveryId',d.id::text,'sourceSalesOrderId',d.parent_id::text,
        'valuationPendingInvoice',true,'updatedAt',now()),updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=a."itemId";
    end if;
  end loop;
  update public.erp_commercial_workflow_documents set status='approved',
    payload=(payload-'costJournalEntryId'-'fifoCostJournalEntryId')||jsonb_build_object(
      'allocations',v_alloc,'inventoryPostedAt',now(),'inventoryPostedBy',auth.uid(),
      'valuationPendingInvoice',true,'accountingOwner','invoice'),updated_at=now()
  where company_id=p_company_id and id=p_delivery_id;
  perform public.erp_commercial_audit(p_company_id,'sales',d.parent_id,d.id,d.document_number,
    'approve_delivery',d.status,'approved','quantity-only; valuation owned by invoice');
end;
$$;

create or replace function public.erp_phase2_post_purchase_receipt(p_company_id uuid,p_receipt_id uuid)
returns text language sql security definer set search_path=public as $$ select null::text $$;
create or replace function public.erp_phase2_post_sales_delivery(p_company_id uuid,p_delivery_id uuid)
returns text language sql security definer set search_path=public as $$ select null::text $$;
create or replace function public.erp_phase3_post_maintenance_issue(p_company_id uuid,p_order_id uuid)
returns text language sql security definer set search_path=public as $$ select null::text $$;
create or replace function public.erp_phase2_approve_purchase_receipt(p_company_id uuid,p_receipt_id uuid)
returns void language sql security definer set search_path=public as $$ select public.erp_approve_cloud_purchase_receipt(p_company_id,p_receipt_id) $$;
create or replace function public.erp_phase2_approve_sales_delivery(p_company_id uuid,p_delivery_id uuid)
returns void language sql security definer set search_path=public as $$ select public.erp_approve_cloud_sales_delivery(p_company_id,p_delivery_id) $$;

create or replace function public.erp_create_cloud_sales_workflow_invoice(p_company_id uuid,p_order_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid(); o public.erp_sales_orders_cloud%rowtype; l jsonb; v_number text;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['sales.create','sales.update','sales.approve']);
  select * into o from public.erp_sales_orders_cloud where company_id=p_company_id and id=p_order_id and status='approved' and not is_deleted for update;
  if not found then raise exception 'approved_sales_order_required'; end if;
  l:=public.erp_v736_active_logistics(p_company_id,p_order_id,'sales');
  if exists(select 1 from public.erp_commercial_workflow_documents where company_id=p_company_id and parent_id=p_order_id and module='sales' and document_type='invoice' and not is_deleted and status<>'cancelled') then
    raise exception 'active_sales_invoice_exists';
  end if;
  v_number:=public.erp_next_document_number(p_company_id,'sales_invoice','SI',coalesce(o.effective_at,o.created_at));
  insert into public.erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,payload,effective_at
  ) values(v_id,p_company_id,'sales','invoice',p_order_id,v_number,jsonb_build_object(
    'currency',o.currency,'totalAmount',o.total,'paidAmount',0,'remainingAmount',o.total,
    'paymentStatus','unpaid','payments','[]'::jsonb,'createdBy',auth.uid(),
    'logisticsDocumentId',l->>'id','logisticsDocumentNumber',l->>'number',
    'allocations',l->'allocations','warehouseIds',l->'warehouseIds','accountingOwner','invoice'),
    coalesce(o.effective_at,o.created_at));
  perform public.erp_commercial_audit(p_company_id,'sales',p_order_id,v_id,v_number,'create_invoice',null,'draft','exact approved delivery quantities');
  return v_id;
end;
$$;

create or replace function public.erp_create_cloud_purchase_workflow_invoice(p_company_id uuid,p_order_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid:=gen_random_uuid(); o public.erp_purchase_orders_cloud%rowtype; l jsonb; v_number text;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['purchases.create','purchases.update','purchases.approve']);
  select * into o from public.erp_purchase_orders_cloud where company_id=p_company_id and id=p_order_id and status='approved' and not is_deleted for update;
  if not found then raise exception 'approved_purchase_order_required'; end if;
  l:=public.erp_v736_active_logistics(p_company_id,p_order_id,'purchases');
  if exists(select 1 from public.erp_commercial_workflow_documents where company_id=p_company_id and parent_id=p_order_id and module='purchases' and document_type='invoice' and not is_deleted and status<>'cancelled') then
    raise exception 'active_purchase_invoice_exists';
  end if;
  v_number:=public.erp_next_document_number(p_company_id,'purchase_invoice','PI',coalesce(o.effective_at,o.created_at));
  insert into public.erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,payload,effective_at
  ) values(v_id,p_company_id,'purchases','invoice',p_order_id,v_number,jsonb_build_object(
    'currency',o.currency,'totalAmount',o.total,'paidAmount',0,'remainingAmount',o.total,
    'paymentStatus','unpaid','payments','[]'::jsonb,'createdBy',auth.uid(),
    'logisticsDocumentId',l->>'id','logisticsDocumentNumber',l->>'number',
    'allocations',l->'allocations','warehouseIds',l->'warehouseIds','accountingOwner','invoice'),
    coalesce(o.effective_at,o.created_at));
  perform public.erp_commercial_audit(p_company_id,'purchases',p_order_id,v_id,v_number,'create_invoice',null,'draft','exact approved receipt quantities');
  return v_id;
end;
$$;

create or replace function public.erp_v736_void_journal_id(p_company_id uuid,p_entry_id text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if nullif(btrim(coalesce(p_entry_id,'')),'') is null then return; end if;
  update public.erp_journal_lines set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
   where company_id=p_company_id and not is_deleted and data->>'entryId'=p_entry_id;
  update public.erp_journal_entries set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
   where company_id=p_company_id and id=p_entry_id and not is_deleted;
end;
$$;

create or replace function public.erp_v736_detach_legacy_purchase_receipt_accounting(
  p_company_id uuid,p_receipt_id uuid
) returns boolean
language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  o public.erp_purchase_orders_cloud%rowtype;
  a record;
  r record;
  s public.erp_warehouse_stock%rowtype;
  v_alloc jsonb;
  v_current_qty numeric;
  v_current_avg numeric;
  v_previous_qty numeric;
  v_previous_avg numeric;
  v_legacy boolean:=false;
  v_product_ids text[]:='{}'::text[];
  v_product_id text;
begin
  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_receipt_id and module='purchases'
     and document_type='receipt' and status='approved' and not is_deleted for update;
  if not found then raise exception 'approved_purchase_receipt_required'; end if;
  select * into o from public.erp_purchase_orders_cloud
   where company_id=p_company_id and id=d.parent_id and not is_deleted;
  if not found then raise exception 'linked_purchase_order_not_found'; end if;

  v_legacy:=coalesce(d.payload->>'accountingOwner','')<>'invoice'
    and (
      nullif(coalesce(d.payload->>'inventoryJournalEntryId',d.payload->>'costJournalEntryId'), '') is not null
      or exists(select 1 from public.erp_inventory_cost_layers l
        where l.company_id=p_company_id and l.receipt_id=p_receipt_id
          and l.status<>'reversed' and l.source_type<>'purchase_invoice')
    );
  if not v_legacy then return false; end if;

  if exists(
    select 1 from public.erp_inventory_fifo_consumptions c
    join public.erp_inventory_cost_layers l on l.id=c.layer_id
    where l.company_id=p_company_id and l.receipt_id=p_receipt_id and c.status='active'
  ) then
    raise exception 'legacy_purchase_receipt_cost_already_consumed';
  end if;

  v_alloc:=public.erp_validate_commercial_warehouse_allocations(
    p_company_id,d.parent_id,'purchases',d.payload->'allocations',false);
  for a in
    select x."itemType",x."itemId",max(x."description") "description",
           x."warehouseId",sum(x.quantity) quantity
    from jsonb_to_recordset(v_alloc) as x(
      "itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
    group by x."itemType",x."itemId",x."warehouseId"
  loop
    select x.unit_cost into r from public.erp_purchase_order_items_cloud x
     where x.company_id=p_company_id and x.order_id=d.parent_id and not x.is_deleted
       and x.item_type=a."itemType" and x.item_id=a."itemId" limit 1;
    if r.unit_cost is null then raise exception 'purchase_order_line_missing:%',a."description"; end if;

    if a."itemType"='product' then
      s:=public.erp_inventory_ensure_stock(p_company_id,a."warehouseId",a."itemId");
      v_current_qty:=public.erp_try_numeric(s.data->>'quantity',0);
      v_current_avg:=public.erp_try_numeric(s.data->>'averageUnitCost',0);
      if v_current_qty<a.quantity then
        raise exception 'legacy_purchase_receipt_quantity_already_moved:%',a."description";
      end if;
      v_previous_qty:=v_current_qty-a.quantity;
      v_previous_avg:=case when v_previous_qty>0 then greatest(
        0,((v_current_qty*v_current_avg)-(a.quantity*r.unit_cost))/v_previous_qty)
        else 0 end;
      update public.erp_warehouse_stock set data=data||jsonb_build_object(
        'averageUnitCost',round(v_previous_avg,6),'valuationPendingInvoice',true,
        'valuationInvoiceId',null,'legacyReceiptValuationDetachedAt',now(),'updatedAt',now()),
        updated_at=now(),updated_by=auth.uid() where id=s.id;
      if not a."itemId"=any(v_product_ids) then
        v_product_ids:=array_append(v_product_ids,a."itemId");
      end if;
    else
      update public.erp_cars set data=data||jsonb_build_object(
        'legacyReceiptPurchasePrice',public.erp_try_numeric(data->>'purchasePrice',0),
        'purchasePrice',0,'purchase_price',0,'valuationPendingInvoice',true,
        'valuationUpdatedByInvoiceId',null,'legacyReceiptValuationDetachedAt',now(),'updatedAt',now()),
        updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=a."itemId" and not is_deleted;
    end if;
  end loop;

  foreach v_product_id in array v_product_ids loop
    perform public.erp_inventory_refresh_product(p_company_id,v_product_id);
    update public.erp_inventory set data=data||jsonb_build_object(
      'valuationPendingInvoice',true,'valuationUpdatedByInvoiceId',null,
      'legacyReceiptValuationDetachedAt',now(),'updatedAt',now()),
      updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=v_product_id and not is_deleted;
  end loop;

  perform public.erp_v736_void_journal_id(
    p_company_id,nullif(coalesce(d.payload->>'inventoryJournalEntryId',d.payload->>'costJournalEntryId'),''));
  perform public.erp_phase2_void_reference_journals(p_company_id,'purchases_inventory',p_receipt_id::text);
  update public.erp_inventory_cost_layers set remaining_quantity=0,status='reversed',
    updated_at=now(),updated_by=auth.uid()
   where company_id=p_company_id and receipt_id=p_receipt_id
     and source_type<>'purchase_invoice' and status<>'reversed';
  update public.erp_inventory_movements set data=data||jsonb_build_object(
    'unitCost',0,'totalCost',0,'valuationPendingInvoice',true,'updatedAt',now()),
    updated_at=now(),updated_by=auth.uid()
   where company_id=p_company_id and not is_deleted
     and data->>'referenceType'='purchase_receipt' and data->>'referenceId'=p_receipt_id::text;
  update public.erp_commercial_workflow_documents set
    payload=(payload-'inventoryJournalEntryId'-'costJournalEntryId'-'fifoLayersRegisteredAt')||jsonb_build_object(
      'accountingOwner','invoice','valuationPendingInvoice',true,
      'legacyReceiptAccountingDetachedAt',now(),'allocations',v_alloc),updated_at=now()
   where company_id=p_company_id and id=p_receipt_id;
  return true;
end;
$$;

-- Correct safely reversible V7.3.5 receipts immediately. Receipts whose cost
-- was already consumed are left flagged for manual reversal rather than being
-- changed partially.
do $$
declare r record;
begin
  for r in
    select d.company_id,d.id from public.erp_commercial_workflow_documents d
    where d.module='purchases' and d.document_type='receipt' and d.status='approved'
      and not d.is_deleted and coalesce(d.payload->>'accountingOwner','')<>'invoice'
  loop
    begin
      perform public.erp_v736_detach_legacy_purchase_receipt_accounting(r.company_id,r.id);
    exception when others then
      update public.erp_commercial_workflow_documents set payload=payload||jsonb_build_object(
        'invoiceAccountingMigrationBlocked',true,'invoiceAccountingMigrationError',sqlerrm,
        'invoiceAccountingMigrationCheckedAt',now()),updated_at=now()
       where company_id=r.company_id and id=r.id;
    end;
  end loop;
end $$;

-- Detach any accounting created by older sales-delivery approvals. Active FIFO
-- consumption rows are retained only as the invoice's future cost source.
do $$
declare d record; v_old text;
begin
  for d in
    select company_id,id,payload from public.erp_commercial_workflow_documents
    where module='sales' and document_type='delivery' and status='approved'
      and not is_deleted and (
        coalesce(payload->>'accountingOwner','')<>'invoice'
        or nullif(coalesce(payload->>'fifoCostJournalEntryId',payload->>'costJournalEntryId'),'') is not null)
  loop
    v_old:=nullif(coalesce(d.payload->>'fifoCostJournalEntryId',d.payload->>'costJournalEntryId'),'');
    perform public.erp_v736_void_journal_id(d.company_id,v_old);
    perform public.erp_phase2_void_reference_journals(d.company_id,'sales_inventory_fifo',d.id::text);
    update public.erp_inventory_fifo_consumptions set journal_entry_id=null
     where company_id=d.company_id and delivery_id=d.id and status='active';
    update public.erp_inventory_movements set data=data||jsonb_build_object(
      'unitCost',0,'totalCost',0,'valuationPendingInvoice',true,'updatedAt',now()),
      updated_at=now(),updated_by=auth.uid()
     where company_id=d.company_id and not is_deleted
       and data->>'referenceType'='sales_delivery' and data->>'referenceId'=d.id::text;
    update public.erp_commercial_workflow_documents set
      payload=(payload-'costJournalEntryId'-'fifoCostJournalEntryId')||jsonb_build_object(
        'accountingOwner','invoice','valuationPendingInvoice',true,
        'legacyDeliveryAccountingDetachedAt',now()),updated_at=now()
     where company_id=d.company_id and id=d.id;
  end loop;
end $$;

-- Old maintenance stock issue accounting and vehicle-cost updates are removed
-- immediately. Quantity remains issued; the invoice will own cost/accounting.
do $$
declare o record; v_previous numeric;
begin
  for o in
    select * from public.erp_maintenance_orders
    where not is_deleted and workflow_stage in (
      'stock_issue_approved','invoice_draft','invoice_approved','paid','completed')
  loop
    perform public.erp_phase2_void_reference_journals(
      o.company_id,'maintenance_stock_issue',o.id::text);
    if not o.is_sold_car and coalesce(o.car_cost_added,0)>0 then
      select greatest(public.erp_try_numeric(
        coalesce(c.data->>'maintenanceCost',c.data->>'maintenance_cost'),0)-o.car_cost_added,0)
        into v_previous
      from public.erp_cars c
      where c.company_id=o.company_id and c.id=coalesce(o.source_car_id,o.car_id::text)
        and not c.is_deleted for update;
      update public.erp_cars set data=data||jsonb_build_object(
        'maintenanceCost',coalesce(v_previous,0),'maintenance_cost',coalesce(v_previous,0),
        'maintenanceValuationInvoiceId',null,'updatedAt',now()),
        updated_at=now(),updated_by=auth.uid()
      where company_id=o.company_id and id=coalesce(o.source_car_id,o.car_id::text) and not is_deleted;
    end if;
    update public.erp_inventory_movements set data=data||jsonb_build_object(
      'unitCost',0,'totalCost',0,'valuationPendingInvoice',true,'updatedAt',now()),
      updated_at=now(),updated_by=auth.uid()
     where company_id=o.company_id and not is_deleted
       and lower(coalesce(data->>'referenceType',data->>'reference_type',''))='maintenance_order'
       and coalesce(data->>'referenceId',data->>'reference_id')=o.id::text
       and lower(coalesce(data->>'movementType',data->>'movement_type',''))='maintenance_out';
    update public.erp_maintenance_orders set car_cost_added=0,
      accounting_payload=accounting_payload||jsonb_build_object(
        'accountingOwner','invoice','legacyStockIssueAccountingDetachedAt',now(),
        'previousCarMaintenanceCost',coalesce(v_previous,0)),updated_at=now(),updated_by=auth.uid()
     where company_id=o.company_id and id=o.id;
  end loop;
end $$;

create or replace function public.erp_v736_post_sales_invoice_costs(
  p_company_id uuid,p_invoice_id uuid,p_order_id uuid,p_delivery_id uuid,p_effective_at timestamptz
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype; a record; l public.erp_inventory_cost_layers%rowtype;
  v_accounts jsonb; v_data jsonb; v_needed numeric; v_existing numeric; v_take numeric;
  v_cost numeric; v_currency text; v_lines_by_currency jsonb:='{}'::jsonb;
  v_lines jsonb; v_entries jsonb:='[]'::jsonb; v_breakdown jsonb:='[]'::jsonb;
  c record; e record; v_entry text; v_old text;
begin
  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_delivery_id and parent_id=p_order_id
     and module='sales' and document_type='delivery' and status='approved' and not is_deleted for update;
  if not found then raise exception 'approved_sales_delivery_required'; end if;

  -- Remove any journal created by older delivery-owned accounting, while
  -- preserving its active FIFO consumptions as the cost source for this invoice.
  v_old:=nullif(coalesce(d.payload->>'fifoCostJournalEntryId',d.payload->>'costJournalEntryId'),'');
  perform public.erp_v736_void_journal_id(p_company_id,v_old);
  perform public.erp_phase2_void_reference_journals(p_company_id,'sales_inventory_fifo',p_delivery_id::text);

  for a in
    select x."itemType",x."itemId",max(x."description") "description",
           x."warehouseId",sum(x.quantity) quantity
    from jsonb_to_recordset(d.payload->'allocations') as x(
      "itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
    group by x."itemType",x."itemId",x."warehouseId"
  loop
    select coalesce(sum(fc.quantity),0) into v_existing
    from public.erp_inventory_fifo_consumptions fc
    where fc.company_id=p_company_id and fc.delivery_id=p_delivery_id and fc.status='active'
      and fc.item_type=a."itemType" and fc.item_id=a."itemId" and fc.warehouse_id=a."warehouseId";
    v_needed:=a.quantity-v_existing;
    if v_needed<0 then raise exception 'invoice_quantity_below_existing_cost_consumption:%',a."description"; end if;

    if v_needed>0 and not exists(
      select 1 from public.erp_inventory_cost_layers x
      where x.company_id=p_company_id and x.item_type=a."itemType" and x.item_id=a."itemId"
        and x.warehouse_id=a."warehouseId" and x.status in ('active','consumed')
        and x.remaining_quantity>0 and x.effective_at<=p_effective_at
    ) then
      v_accounts:=public.erp_v736_item_accounting(p_company_id,a."itemType",a."itemId",null);
      v_data:=v_accounts->'data';
      if a."itemType"='car' then
        v_cost:=public.erp_try_numeric(v_data->>'purchasePrice',public.erp_try_numeric(v_data->>'costPrice',0))+
                public.erp_try_numeric(v_data->>'maintenanceCost',public.erp_try_numeric(v_data->>'maintenance_cost',0));
      else
        v_cost:=public.erp_try_numeric(v_data->>'unitCost',
          public.erp_try_numeric(v_data->>'unit_cost',public.erp_try_numeric(v_data->>'purchasePrice',0)));
      end if;
      insert into public.erp_inventory_cost_layers(
        company_id,item_type,item_id,warehouse_id,layer_number,effective_at,
        original_quantity,remaining_quantity,unit_cost,currency,asset_account_id,
        cost_expense_account_id,source_type
      ) values(
        p_company_id,a."itemType",a."itemId",a."warehouseId",
        'OPEN-INV-'||substr(replace(p_invoice_id::text,'-',''),1,16)||'-'||substr(md5(a."itemId"||a."warehouseId"),1,6),
        p_effective_at,v_needed,v_needed,greatest(v_cost,0),v_accounts->>'costCurrency',
        v_accounts->>'assetAccountId',v_accounts->>'costExpenseAccountId','invoice_opening'
      );
    end if;

    for l in
      select * from public.erp_inventory_cost_layers x
      where x.company_id=p_company_id and x.item_type=a."itemType" and x.item_id=a."itemId"
        and x.warehouse_id=a."warehouseId" and x.status in ('active','consumed')
        and x.remaining_quantity>0 and x.effective_at<=p_effective_at
      order by x.effective_at,x.created_at,x.id for update
    loop
      exit when v_needed<=0;
      v_take:=least(v_needed,l.remaining_quantity);
      update public.erp_inventory_cost_layers set remaining_quantity=remaining_quantity-v_take,
        status=case when remaining_quantity-v_take<=0 then 'consumed' else 'active' end,
        updated_at=now(),updated_by=auth.uid() where id=l.id;
      insert into public.erp_inventory_fifo_consumptions(
        company_id,delivery_id,sales_order_id,layer_id,item_type,item_id,warehouse_id,
        quantity,unit_cost,effective_at,status
      ) values(
        p_company_id,p_delivery_id,p_order_id,l.id,a."itemType",a."itemId",a."warehouseId",
        v_take,l.unit_cost,p_effective_at,'active'
      ) on conflict(company_id,delivery_id,layer_id) do update set
        quantity=excluded.quantity,unit_cost=excluded.unit_cost,effective_at=excluded.effective_at,
        status='active',reversed_at=null;
      v_needed:=v_needed-v_take;
    end loop;
    if v_needed>0 then raise exception 'insufficient_invoice_cost_layers:%',a."description"; end if;
  end loop;

  for c in
    select fc.*,l.currency,l.asset_account_id,l.cost_expense_account_id,l.layer_number
    from public.erp_inventory_fifo_consumptions fc
    join public.erp_inventory_cost_layers l on l.id=fc.layer_id
    where fc.company_id=p_company_id and fc.delivery_id=p_delivery_id and fc.status='active'
    order by l.currency,l.effective_at,l.created_at
  loop
    v_currency:=upper(c.currency);
    v_lines:=coalesce(v_lines_by_currency->v_currency,'[]'::jsonb)||jsonb_build_array(
      jsonb_build_object('accountId',c.cost_expense_account_id,'debit',c.total_cost,'credit',0,
        'description','تكلفة بيع حسب الفاتورة','itemType',c.item_type,'itemId',c.item_id,
        'warehouseId',c.warehouse_id,'layerId',c.layer_id,'layerNumber',c.layer_number,
        'quantity',c.quantity,'unitCost',c.unit_cost),
      jsonb_build_object('accountId',c.asset_account_id,'debit',0,'credit',c.total_cost,
        'description','إخراج كلفة المخزون حسب الفاتورة','itemType',c.item_type,'itemId',c.item_id,
        'warehouseId',c.warehouse_id,'layerId',c.layer_id,'layerNumber',c.layer_number,
        'quantity',c.quantity,'unitCost',c.unit_cost)
    );
    v_lines_by_currency:=jsonb_set(v_lines_by_currency,array[v_currency],v_lines,true);
    v_breakdown:=v_breakdown||jsonb_build_array(jsonb_build_object(
      'currency',v_currency,'itemType',c.item_type,'itemId',c.item_id,'warehouseId',c.warehouse_id,
      'layerId',c.layer_id,'layerNumber',c.layer_number,'quantity',c.quantity,
      'unitCost',c.unit_cost,'totalCost',c.total_cost));
  end loop;

  for e in select key,value from jsonb_each(v_lines_by_currency) loop
    v_entry:=public.erp_phase2_insert_journal_at(
      p_company_id,'sales_invoice_cost_'||lower(e.key),p_invoice_id::text,
      public.erp_next_document_number(p_company_id,'sales_cost_journal_'||lower(e.key),'SIC-'||e.key,p_effective_at),
      'قيد كلفة فاتورة البيع حسب عملة المخزون',e.key,e.value,p_effective_at);
    update public.erp_inventory_fifo_consumptions fc set journal_entry_id=v_entry
    from public.erp_inventory_cost_layers l
    where fc.company_id=p_company_id and fc.delivery_id=p_delivery_id and fc.status='active'
      and l.id=fc.layer_id and upper(l.currency)=upper(e.key);
    v_entries:=v_entries||jsonb_build_array(jsonb_build_object('currency',e.key,'journalEntryId',v_entry));
  end loop;

  update public.erp_commercial_workflow_documents set
    payload=(payload-'costJournalEntryId'-'fifoCostJournalEntryId')||jsonb_build_object(
      'accountingOwner','invoice','accountedByInvoiceId',p_invoice_id::text,
      'valuationPendingInvoice',false,'invoiceCostPostedAt',now()),updated_at=now()
  where company_id=p_company_id and id=p_delivery_id;
  return jsonb_build_object('journalEntries',v_entries,'breakdown',v_breakdown);
end;
$$;

create or replace function public.erp_approve_cloud_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns void language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype; v_currency text; v_total numeric; v_effective timestamptz;
  v_partner_id text; v_partner_type text; v_partner_account text; v_lines jsonb:='[]'::jsonb;
  v_entry text; v_factor numeric; v_subtotal numeric; r record; a record; ac jsonb; s public.erp_warehouse_stock%rowtype;
  v_amount numeric; v_current_qty numeric; v_previous_qty numeric; v_previous_avg numeric; v_new_avg numeric;
  v_adjusted_unit_cost numeric; v_logistics_id uuid; v_logistics jsonb;
  v_snapshots jsonb:='[]'::jsonb; v_cost_result jsonb:='{}'::jsonb;
  v_old_data jsonb; v_layer_number text; v_order_rate numeric:=1;
  v_cost_currency text; v_converted_amount numeric; v_clearing_accounts jsonb;
  v_clearing_account text; v_cost_lines_by_currency jsonb:='{}'::jsonb;
  v_cost_lines jsonb; v_cost_entries jsonb:='[]'::jsonb; v_cost_entry text; e record;
begin
  if p_module not in ('sales','purchases') then raise exception 'invalid workflow module'; end if;
  perform public.erp_require_any_cloud_permission(p_company_id,
    case when p_module='sales' then array['sales.approve','sales.update'] else array['purchases.approve','purchases.update'] end);
  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_invoice_id and module=p_module
     and document_type='invoice' and not is_deleted for update;
  if not found then raise exception 'workflow_invoice_not_found'; end if;
  if d.status='approved' and nullif(d.payload->>'journalEntryId','') is not null then return; end if;
  if d.status not in ('draft','approved') then raise exception 'workflow_invoice_invalid_status'; end if;
  v_currency:=upper(coalesce(d.payload->>'currency',''));
  v_total:=public.erp_try_numeric(d.payload->>'totalAmount',0);
  v_effective:=coalesce(d.effective_at,d.created_at,now());
  v_logistics_id:=nullif(d.payload->>'logisticsDocumentId','')::uuid;
  if v_currency not in ('IQD','USD') or v_total<=0 or v_logistics_id is null then
    raise exception 'workflow_invoice_invalid_amount_currency_or_logistics';
  end if;
  v_logistics:=public.erp_v736_assert_invoice_logistics(
    p_company_id,d.parent_id,p_module,v_logistics_id,d.payload->'allocations');

  if p_module='sales' then
    select customer_id,subtotal into v_partner_id,v_subtotal from public.erp_sales_orders_cloud
     where company_id=p_company_id and id=d.parent_id and status='approved' and currency=v_currency and not is_deleted;
    v_partner_type:='customer';
  else
    select supplier_id,subtotal,exchange_rate into v_partner_id,v_subtotal,v_order_rate
      from public.erp_purchase_orders_cloud
     where company_id=p_company_id and id=d.parent_id and status='approved'
       and currency=v_currency and exchange_rate>0 and not is_deleted;
    v_partner_type:='supplier';
  end if;
  if not found then raise exception 'invoice_order_currency_mismatch'; end if;
  v_partner_account:=public.erp_workflow_partner_account(p_company_id,v_partner_type,v_partner_id,v_currency);
  v_factor:=case when coalesce(v_subtotal,0)>0 then v_total/v_subtotal else 1 end;

  if p_module='sales' then
    v_lines:=jsonb_build_array(jsonb_build_object(
      'accountId',v_partner_account,'debit',v_total,'credit',0,'description','ذمة العميل - فاتورة بيع'));
    for r in select * from public.erp_sales_order_items_cloud
      where company_id=p_company_id and order_id=d.parent_id and not is_deleted order by id
    loop
      ac:=public.erp_v736_item_accounting(p_company_id,r.item_type,r.item_id,v_currency);
      v_amount:=r.line_total*v_factor;
      v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
        'accountId',ac->>'revenueAccountId','debit',0,'credit',v_amount,
        'description','إيراد '||r.description,'itemType',r.item_type,'itemId',r.item_id,
        'quantity',r.quantity,'unitPrice',r.unit_price));
      v_old_data:=ac->'data';
      v_snapshots:=v_snapshots||jsonb_build_array(jsonb_build_object(
        'itemType',r.item_type,'itemId',r.item_id,
        'previousSalePrice',public.erp_try_numeric(v_old_data->>'salePrice',public.erp_try_numeric(v_old_data->>'sale_price',0)),
        'previousSaleCurrency',coalesce(v_old_data->>'saleCurrency',v_old_data->>'sale_currency',v_old_data->>'currency')));
      if r.item_type='car' then
        update public.erp_cars set data=data||jsonb_build_object(
          'salePrice',r.unit_price,'sale_price',r.unit_price,'saleCurrency',v_currency,
          'sale_currency',v_currency,'valuationUpdatedByInvoiceId',p_invoice_id::text,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id and not is_deleted;
      else
        update public.erp_inventory set data=data||jsonb_build_object(
          'salePrice',r.unit_price,'sale_price',r.unit_price,'saleCurrency',v_currency,
          'sale_currency',v_currency,'valuationUpdatedByInvoiceId',p_invoice_id::text,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id and not is_deleted;
      end if;
    end loop;
    v_entry:=public.erp_phase2_insert_journal_at(
      p_company_id,'sales_invoice_revenue',p_invoice_id::text,
      public.erp_next_document_number(p_company_id,'sales_invoice_journal','SIJ',v_effective),
      'قيد فاتورة البيع '||d.document_number,v_currency,v_lines,v_effective);
    v_cost_result:=public.erp_v736_post_sales_invoice_costs(
      p_company_id,p_invoice_id,d.parent_id,v_logistics_id,v_effective);
    perform public.erp_mark_sales_order_cars_sold(p_company_id,d.parent_id,p_invoice_id);
  else
    perform public.erp_v736_detach_legacy_purchase_receipt_accounting(
      p_company_id,v_logistics_id);
    v_clearing_accounts:=public.erp_v736_ensure_purchase_clearing_accounts(p_company_id);
    v_clearing_account:=v_clearing_accounts->>v_currency;
    perform public.erp_phase2_account_guard(p_company_id,v_clearing_account,'asset',v_currency);
    -- The supplier invoice is posted in the order currency. Inventory is
    -- capitalized separately in every item's configured cost currency.
    v_lines:=jsonb_build_array(jsonb_build_object(
      'accountId',v_clearing_account,'debit',v_total,'credit',0,
      'description','تسوية رسملة فاتورة الشراء'));

    for r in select * from public.erp_purchase_order_items_cloud
      where company_id=p_company_id and order_id=d.parent_id and not is_deleted order by id
    loop
      ac:=public.erp_v736_item_accounting(p_company_id,r.item_type,r.item_id,null);
      v_cost_currency:=upper(ac->>'costCurrency');
      perform public.erp_phase2_account_guard(p_company_id,ac->>'assetAccountId','asset',v_cost_currency);
      perform public.erp_phase2_account_guard(p_company_id,ac->>'costExpenseAccountId','expense',v_cost_currency);
      v_clearing_account:=v_clearing_accounts->>v_cost_currency;
      perform public.erp_phase2_account_guard(p_company_id,v_clearing_account,'asset',v_cost_currency);
      v_amount:=r.line_total*v_factor;
      v_converted_amount:=public.erp_v736_convert_currency(
        v_amount,v_currency,v_cost_currency,v_order_rate);
      v_adjusted_unit_cost:=case when r.quantity>0 then v_converted_amount/r.quantity else
        public.erp_v736_convert_currency(r.unit_cost,v_currency,v_cost_currency,v_order_rate) end;
      v_cost_lines:=coalesce(v_cost_lines_by_currency->v_cost_currency,'[]'::jsonb)
        ||jsonb_build_array(
          jsonb_build_object(
            'accountId',ac->>'assetAccountId','debit',v_converted_amount,'credit',0,
            'description','رسملة شراء '||r.description,'itemType',r.item_type,
            'itemId',r.item_id,'quantity',r.quantity,'unitCost',v_adjusted_unit_cost),
          jsonb_build_object(
            'accountId',v_clearing_account,'debit',0,'credit',v_converted_amount,
            'description','تسوية رسملة شراء '||r.description,'itemType',r.item_type,
            'itemId',r.item_id,'invoiceCurrency',v_currency,'exchangeRate',v_order_rate)
        );
      v_cost_lines_by_currency:=jsonb_set(
        v_cost_lines_by_currency,array[v_cost_currency],v_cost_lines,true);
      v_old_data:=ac->'data';

      for a in select * from jsonb_to_recordset(d.payload->'allocations') as x(
        "itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
        where x."itemType"=r.item_type and x."itemId"=r.item_id
      loop
        if r.item_type='product' then
          s:=public.erp_inventory_ensure_stock(p_company_id,a."warehouseId",r.item_id);
          v_current_qty:=public.erp_try_numeric(s.data->>'quantity',0);
          if v_current_qty<a.quantity then
            raise exception 'purchase_invoice_quantity_exceeds_current_stock:%',r.description;
          end if;
          v_previous_qty:=v_current_qty-a.quantity;
          v_previous_avg:=public.erp_try_numeric(s.data->>'averageUnitCost',0);
          v_new_avg:=case when v_current_qty>0 then
            ((v_previous_qty*v_previous_avg)+(a.quantity*v_adjusted_unit_cost))/v_current_qty
            else v_adjusted_unit_cost end;
          v_snapshots:=v_snapshots||jsonb_build_array(jsonb_build_object(
            'itemType','product','itemId',r.item_id,'warehouseId',a."warehouseId",
            'previousAverageUnitCost',v_previous_avg,
            'previousPurchasePrice',public.erp_try_numeric(v_old_data->>'purchasePrice',0),
            'previousUnitCost',public.erp_try_numeric(v_old_data->>'unitCost',0),
            'previousCostCurrency',coalesce(v_old_data->>'costCurrency',v_old_data->>'cost_currency',v_old_data->>'currency')));
          update public.erp_warehouse_stock set data=data||jsonb_build_object(
            'averageUnitCost',round(v_new_avg,6),'valuationPendingInvoice',false,
            'valuationInvoiceId',p_invoice_id::text,'valuationCurrency',v_cost_currency,
            'updatedAt',now()),updated_at=now(),updated_by=auth.uid()
          where id=s.id;
          v_layer_number:=(d.payload->>'logisticsDocumentNumber')||'-'||substr(md5(r.item_id||a."warehouseId"),1,6);
          insert into public.erp_inventory_cost_layers(
            company_id,item_type,item_id,warehouse_id,receipt_id,purchase_order_id,source_line_id,
            layer_number,effective_at,original_quantity,remaining_quantity,unit_cost,currency,
            asset_account_id,cost_expense_account_id,source_type
          ) values(
            p_company_id,'product',r.item_id,a."warehouseId",v_logistics_id,d.parent_id,r.id,
            v_layer_number,v_effective,a.quantity,a.quantity,v_adjusted_unit_cost,v_cost_currency,
            ac->>'assetAccountId',ac->>'costExpenseAccountId','purchase_invoice'
          ) on conflict(company_id,receipt_id,item_type,item_id,warehouse_id) do update set
            source_line_id=excluded.source_line_id,layer_number=excluded.layer_number,
            effective_at=excluded.effective_at,original_quantity=excluded.original_quantity,
            remaining_quantity=excluded.remaining_quantity,unit_cost=excluded.unit_cost,
            currency=excluded.currency,asset_account_id=excluded.asset_account_id,
            cost_expense_account_id=excluded.cost_expense_account_id,status='active',
            source_type='purchase_invoice',updated_at=now(),updated_by=auth.uid();
        else
          v_snapshots:=v_snapshots||jsonb_build_array(jsonb_build_object(
            'itemType','car','itemId',r.item_id,'warehouseId',a."warehouseId",
            'previousPurchasePrice',public.erp_try_numeric(v_old_data->>'purchasePrice',0),
            'previousCostCurrency',coalesce(v_old_data->>'costCurrency',v_old_data->>'cost_currency',v_old_data->>'currency')));
          v_layer_number:=(d.payload->>'logisticsDocumentNumber')||'-'||substr(md5(r.item_id),1,6);
          insert into public.erp_inventory_cost_layers(
            company_id,item_type,item_id,warehouse_id,receipt_id,purchase_order_id,source_line_id,
            layer_number,effective_at,original_quantity,remaining_quantity,unit_cost,currency,
            asset_account_id,cost_expense_account_id,source_type
          ) values(
            p_company_id,'car',r.item_id,a."warehouseId",v_logistics_id,d.parent_id,r.id,
            v_layer_number,v_effective,1,1,v_adjusted_unit_cost,v_cost_currency,
            ac->>'assetAccountId',ac->>'costExpenseAccountId','purchase_invoice'
          ) on conflict(company_id,receipt_id,item_type,item_id,warehouse_id) do update set
            source_line_id=excluded.source_line_id,layer_number=excluded.layer_number,
            effective_at=excluded.effective_at,original_quantity=1,remaining_quantity=1,
            unit_cost=excluded.unit_cost,currency=excluded.currency,
            asset_account_id=excluded.asset_account_id,cost_expense_account_id=excluded.cost_expense_account_id,
            status='active',source_type='purchase_invoice',updated_at=now(),updated_by=auth.uid();
        end if;
      end loop;
      if r.item_type='car' then
        update public.erp_cars set data=data||jsonb_build_object(
          'purchasePrice',v_adjusted_unit_cost,'purchase_price',v_adjusted_unit_cost,
          'costCurrency',v_cost_currency,'cost_currency',v_cost_currency,
          'valuationPendingInvoice',false,'valuationUpdatedByInvoiceId',p_invoice_id::text,
          'purchaseInvoiceCurrency',v_currency,'purchaseExchangeRate',v_order_rate,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id and not is_deleted;
      else
        update public.erp_inventory set data=data||jsonb_build_object(
          'purchasePrice',v_adjusted_unit_cost,'purchase_price',v_adjusted_unit_cost,
          'unitCost',v_adjusted_unit_cost,'unit_cost',v_adjusted_unit_cost,
          'costCurrency',v_cost_currency,'cost_currency',v_cost_currency,
          'valuationPendingInvoice',false,'valuationUpdatedByInvoiceId',p_invoice_id::text,
          'purchaseInvoiceCurrency',v_currency,'purchaseExchangeRate',v_order_rate,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id and not is_deleted;
        perform public.erp_inventory_refresh_product(p_company_id,r.item_id);
      end if;
    end loop;

    v_lines:=v_lines||jsonb_build_array(jsonb_build_object(
      'accountId',v_partner_account,'debit',0,'credit',v_total,
      'description','ذمة المورد - فاتورة شراء'));
    v_entry:=public.erp_phase2_insert_journal_at(
      p_company_id,'purchase_invoice',p_invoice_id::text,
      public.erp_next_document_number(p_company_id,'purchase_invoice_journal','PIJ',v_effective),
      'قيد ذمة فاتورة الشراء '||d.document_number,v_currency,v_lines,v_effective);

    for e in select key,value from jsonb_each(v_cost_lines_by_currency) loop
      v_cost_entry:=public.erp_phase2_insert_journal_at(
        p_company_id,'purchase_invoice_valuation_'||lower(e.key),p_invoice_id::text,
        public.erp_next_document_number(
          p_company_id,'purchase_valuation_journal_'||lower(e.key),'PIV-'||e.key,v_effective),
        'قيد رسملة مخزون فاتورة الشراء '||d.document_number,e.key,e.value,v_effective);
      v_cost_entries:=v_cost_entries||jsonb_build_array(jsonb_build_object(
        'currency',e.key,'journalEntryId',v_cost_entry));
    end loop;
    v_cost_result:=jsonb_build_object('journalEntries',v_cost_entries);
    update public.erp_commercial_workflow_documents set payload=payload||jsonb_build_object(
      'valuationPendingInvoice',false,'valuedByInvoiceId',p_invoice_id::text,
      'valuationAppliedAt',now(),'invoiceCurrency',v_currency,
      'exchangeRate',v_order_rate,'costJournalEntries',v_cost_entries),updated_at=now()
    where company_id=p_company_id and id=v_logistics_id;
  end if;

  update public.erp_commercial_workflow_documents set status='approved',
    payload=payload||jsonb_build_object(
      'journalEntryId',v_entry,'costJournalEntries',coalesce(v_cost_result->'journalEntries','[]'::jsonb),
      'costBreakdown',coalesce(v_cost_result->'breakdown','[]'::jsonb),
      'valuationSnapshots',v_snapshots,'approvedAt',now(),'approvedBy',auth.uid(),
      'valuationApplied',true,'accountingOwner','invoice'),updated_at=now()
  where company_id=p_company_id and id=p_invoice_id;
  perform public.erp_commercial_audit(p_company_id,p_module,d.parent_id,d.id,d.document_number,
    'approve_invoice',d.status,'approved','financial and valuation posting owned by invoice');
end;
$$;

create or replace function public.erp_approve_cloud_sales_workflow_invoice(p_company_id uuid,p_invoice_id uuid)
returns void language sql security definer set search_path=public as $$
  select public.erp_approve_cloud_workflow_invoice(p_company_id,p_invoice_id,'sales')
$$;
create or replace function public.erp_approve_cloud_purchase_workflow_invoice(p_company_id uuid,p_invoice_id uuid)
returns void language sql security definer set search_path=public as $$
  select public.erp_approve_cloud_workflow_invoice(p_company_id,p_invoice_id,'purchases')
$$;

create or replace function public.erp_cancel_cloud_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_module text,p_reason text default null
) returns void language plpgsql security definer set search_path=public as $$
declare d public.erp_commercial_workflow_documents%rowtype; j jsonb; s jsonb; v_delivery uuid; c record;
begin
  if p_module not in ('sales','purchases') then raise exception 'invalid workflow module'; end if;
  perform public.erp_require_any_cloud_permission(p_company_id,
    case when p_module='sales' then array['sales.cancel','sales.update','sales.delete'] else array['purchases.cancel','purchases.update','purchases.delete'] end);
  select * into d from public.erp_commercial_workflow_documents
   where company_id=p_company_id and id=p_invoice_id and module=p_module
     and document_type='invoice' and not is_deleted for update;
  if not found then raise exception 'workflow_invoice_not_found'; end if;
  if d.status='cancelled' then return; end if;
  if jsonb_array_length(coalesce(d.payload->'payments','[]'::jsonb))>0 then
    raise exception 'reverse_invoice_payments_first';
  end if;

  perform public.erp_v736_void_journal_id(p_company_id,d.payload->>'journalEntryId');
  for j in select value from jsonb_array_elements(coalesce(d.payload->'costJournalEntries','[]'::jsonb)) loop
    perform public.erp_v736_void_journal_id(p_company_id,j->>'journalEntryId');
  end loop;

  if p_module='sales' then
    v_delivery:=nullif(d.payload->>'logisticsDocumentId','')::uuid;
    if v_delivery is not null then
      update public.erp_inventory_cost_layers l set
        remaining_quantity=least(l.original_quantity,l.remaining_quantity+c.quantity),
        status='active',updated_at=now(),updated_by=auth.uid()
      from public.erp_inventory_fifo_consumptions c
      where c.company_id=p_company_id and c.delivery_id=v_delivery and c.status='active' and l.id=c.layer_id;
      update public.erp_inventory_fifo_consumptions set status='reversed',reversed_at=now()
       where company_id=p_company_id and delivery_id=v_delivery and status='active';
      update public.erp_commercial_workflow_documents set payload=payload||jsonb_build_object(
        'valuationPendingInvoice',true,'accountedByInvoiceId',null,'invoiceCostReversedAt',now()),updated_at=now()
       where company_id=p_company_id and id=v_delivery;
    end if;
    for s in select value from jsonb_array_elements(coalesce(d.payload->'valuationSnapshots','[]'::jsonb)) loop
      if s->>'itemType'='car' then
        update public.erp_cars set data=data||jsonb_build_object(
          'salePrice',public.erp_try_numeric(s->>'previousSalePrice',0),
          'sale_price',public.erp_try_numeric(s->>'previousSalePrice',0),
          'saleCurrency',s->>'previousSaleCurrency','sale_currency',s->>'previousSaleCurrency',
          'valuationUpdatedByInvoiceId',null,'updatedAt',now()),updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=s->>'itemId' and not is_deleted;
      else
        update public.erp_inventory set data=data||jsonb_build_object(
          'salePrice',public.erp_try_numeric(s->>'previousSalePrice',0),
          'sale_price',public.erp_try_numeric(s->>'previousSalePrice',0),
          'saleCurrency',s->>'previousSaleCurrency','sale_currency',s->>'previousSaleCurrency',
          'valuationUpdatedByInvoiceId',null,'updatedAt',now()),updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=s->>'itemId' and not is_deleted;
      end if;
    end loop;
    if d.status='approved' then
      perform public.erp_restore_sales_order_cars_after_invoice_cancel(p_company_id,d.parent_id,p_invoice_id);
    end if;
  else
    if exists(
      select 1 from public.erp_inventory_fifo_consumptions fc
      join public.erp_inventory_cost_layers l on l.id=fc.layer_id
      where l.company_id=p_company_id and l.receipt_id=nullif(d.payload->>'logisticsDocumentId','')::uuid
        and fc.status='active'
    ) then raise exception 'purchase_invoice_cost_already_consumed'; end if;
    update public.erp_inventory_cost_layers set remaining_quantity=0,status='reversed',updated_at=now(),updated_by=auth.uid()
     where company_id=p_company_id and receipt_id=nullif(d.payload->>'logisticsDocumentId','')::uuid
       and source_type='purchase_invoice' and status<>'reversed';
    for s in select value from jsonb_array_elements(coalesce(d.payload->'valuationSnapshots','[]'::jsonb)) loop
      if s->>'itemType'='car' then
        update public.erp_cars set data=data||jsonb_build_object(
          'purchasePrice',public.erp_try_numeric(s->>'previousPurchasePrice',0),
          'purchase_price',public.erp_try_numeric(s->>'previousPurchasePrice',0),
          'costCurrency',s->>'previousCostCurrency','cost_currency',s->>'previousCostCurrency',
          'valuationPendingInvoice',true,'valuationUpdatedByInvoiceId',null,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=s->>'itemId' and not is_deleted;
      else
        update public.erp_warehouse_stock set data=data||jsonb_build_object(
          'averageUnitCost',public.erp_try_numeric(s->>'previousAverageUnitCost',0),
          'valuationPendingInvoice',true,'valuationInvoiceId',null,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and not is_deleted
          and coalesce(data->>'productId',data->>'product_id')=s->>'itemId'
          and coalesce(data->>'warehouseId',data->>'warehouse_id')=s->>'warehouseId';
        update public.erp_inventory set data=data||jsonb_build_object(
          'purchasePrice',public.erp_try_numeric(s->>'previousPurchasePrice',0),
          'purchase_price',public.erp_try_numeric(s->>'previousPurchasePrice',0),
          'unitCost',public.erp_try_numeric(s->>'previousUnitCost',0),
          'unit_cost',public.erp_try_numeric(s->>'previousUnitCost',0),
          'costCurrency',s->>'previousCostCurrency','cost_currency',s->>'previousCostCurrency',
          'valuationPendingInvoice',true,'valuationUpdatedByInvoiceId',null,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=s->>'itemId' and not is_deleted;
        perform public.erp_inventory_refresh_product(p_company_id,s->>'itemId');
      end if;
    end loop;
    update public.erp_commercial_workflow_documents set payload=payload||jsonb_build_object(
      'valuationPendingInvoice',true,'valuedByInvoiceId',null,'valuationReversedAt',now()),updated_at=now()
     where company_id=p_company_id and id=nullif(d.payload->>'logisticsDocumentId','')::uuid;
  end if;

  update public.erp_commercial_workflow_documents set status='cancelled',
    payload=payload||jsonb_build_object('reason',p_reason,'cancelledAt',now(),
      'valuationApplied',false,'accountingReversedAt',now()),updated_at=now()
   where company_id=p_company_id and id=p_invoice_id;
  perform public.erp_commercial_audit(p_company_id,p_module,d.parent_id,d.id,d.document_number,
    'cancel_invoice',d.status,'cancelled',p_reason);
end;
$$;

create or replace function public.erp_cancel_cloud_sales_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_reason text default null
) returns void language sql security definer set search_path=public as $$
  select public.erp_cancel_cloud_workflow_invoice(p_company_id,p_invoice_id,'sales',p_reason)
$$;
create or replace function public.erp_cancel_cloud_purchase_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_reason text default null
) returns void language sql security definer set search_path=public as $$
  select public.erp_cancel_cloud_workflow_invoice(p_company_id,p_invoice_id,'purchases',p_reason)
$$;

create or replace function public.erp_v736_post_maintenance_invoice(
  p_company_id uuid,p_order_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  o public.erp_maintenance_orders%rowtype; p record; ac jsonb; defaults jsonb;
  v_currency text; v_effective timestamptz; v_partner_account text; v_revenue_account text;
  v_revenue_lines jsonb; v_cost_lines jsonb:='{}'::jsonb; v_lines jsonb;
  v_entry text; v_entries jsonb:='[]'::jsonb; v_cost numeric; v_cost_currency text;
  e record; v_car_data jsonb; v_previous_maintenance numeric:=0;
  v_cost_totals jsonb:='{}'::jsonb; v_car_cost_currency text;
  v_car_cost_added numeric:=0;
begin
  select * into o from public.erp_maintenance_orders
   where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if o.invoice_journal_entry_id is not null then
    return jsonb_build_object('journalEntryId',o.invoice_journal_entry_id,'costJournalEntries',o.cost_journal_entry_ids);
  end if;
  if o.pricing_type<>'paid' or o.sale_price<=0 then raise exception 'paid_maintenance_invoice_required'; end if;
  v_currency:=upper(o.currency_code); v_effective:=coalesce(o.maintenance_date,now());
  defaults:=public.erp_v736_ensure_currency_revenue_accounts(p_company_id);
  v_revenue_account:=case when v_currency='IQD' then defaults->>'maintenanceRevenueIqdAccountId' else defaults->>'maintenanceRevenueUsdAccountId' end;
  perform public.erp_phase2_account_guard(p_company_id,v_revenue_account,'revenue',v_currency);
  if o.customer_id is not null then
    v_partner_account:=public.erp_workflow_partner_account(p_company_id,'customer',o.customer_id::text,v_currency);
  else
    select account_id into v_partner_account from public.erp_accounts
     where organization_id=p_company_id and code='1400' and is_active limit 1;
  end if;
  if v_partner_account is null then raise exception 'maintenance_receivable_account_missing'; end if;
  v_revenue_lines:=jsonb_build_array(
    jsonb_build_object('accountId',v_partner_account,'debit',o.sale_price,'credit',0,'description','ذمة فاتورة الصيانة'),
    jsonb_build_object('accountId',v_revenue_account,'debit',0,'credit',o.sale_price,'description','إيراد خدمات الصيانة'));
  v_entry:=public.erp_phase2_insert_journal_at(
    p_company_id,'maintenance_invoice_revenue',p_order_id::text,
    public.erp_next_document_number(p_company_id,'maintenance_invoice_journal','MIJ',v_effective),
    'قيد فاتورة الصيانة '||coalesce(o.invoice_number,o.order_number),v_currency,v_revenue_lines,v_effective);

  for p in select * from public.erp_maintenance_parts
    where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted and line_type<>'service'
  loop
    ac:=public.erp_v736_item_accounting(p_company_id,'product',coalesce(p.source_product_id,p.product_id::text),null);
    v_cost_currency:=ac->>'costCurrency';
    v_cost:=p.quantity*public.erp_try_numeric(ac->'data'->>'unitCost',
      public.erp_try_numeric(ac->'data'->>'unit_cost',public.erp_try_numeric(ac->'data'->>'purchasePrice',p.unit_cost)));
    if v_cost>0 then
      v_lines:=coalesce(v_cost_lines->v_cost_currency,'[]'::jsonb)||jsonb_build_array(
        jsonb_build_object('accountId',ac->>'costExpenseAccountId','debit',v_cost,'credit',0,
          'description','كلفة مواد الصيانة - '||p.product_name,'itemId',coalesce(p.source_product_id,p.product_id::text),'quantity',p.quantity),
        jsonb_build_object('accountId',ac->>'assetAccountId','debit',0,'credit',v_cost,
          'description','إخراج كلفة مواد الصيانة - '||p.product_name,'itemId',coalesce(p.source_product_id,p.product_id::text),'quantity',p.quantity));
      v_cost_lines:=jsonb_set(v_cost_lines,array[v_cost_currency],v_lines,true);
      v_cost_totals:=jsonb_set(
        v_cost_totals,array[v_cost_currency],
        to_jsonb(public.erp_try_numeric(v_cost_totals->>v_cost_currency,0)+v_cost),true);
    end if;
  end loop;
  for e in select key,value from jsonb_each(v_cost_lines) loop
    v_entries:=v_entries||jsonb_build_array(jsonb_build_object(
      'currency',e.key,'journalEntryId',public.erp_phase2_insert_journal_at(
        p_company_id,'maintenance_invoice_cost_'||lower(e.key),p_order_id::text,
        public.erp_next_document_number(p_company_id,'maintenance_cost_journal_'||lower(e.key),'MIC-'||e.key,v_effective),
        'قيد كلفة مواد فاتورة الصيانة',e.key,e.value,v_effective)));
  end loop;

  if not o.is_sold_car then
    select data into v_car_data from public.erp_cars
     where company_id=p_company_id and id=coalesce(o.source_car_id,o.car_id::text)
       and not is_deleted for update;
    v_previous_maintenance:=public.erp_try_numeric(
      v_car_data->>'maintenanceCost',public.erp_try_numeric(v_car_data->>'maintenance_cost',0));
    v_car_cost_currency:=upper(coalesce(
      nullif(v_car_data->>'costCurrency',''),nullif(v_car_data->>'cost_currency',''),
      nullif(v_car_data->>'currency',''),'USD'));
    v_car_cost_added:=public.erp_try_numeric(v_cost_totals->>v_car_cost_currency,0);
    update public.erp_cars set data=data||jsonb_build_object(
      'maintenanceCost',v_previous_maintenance+v_car_cost_added,
      'maintenance_cost',v_previous_maintenance+v_car_cost_added,
      'maintenanceCostCurrency',v_car_cost_currency,
      'maintenanceCostByCurrency',v_cost_totals,
      'maintenanceValuationInvoiceId',p_order_id::text,'updatedAt',now()),
      updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=coalesce(o.source_car_id,o.car_id::text) and not is_deleted;
  end if;
  update public.erp_maintenance_orders set invoice_journal_entry_id=v_entry,
    cost_journal_entry_ids=v_entries,car_cost_added=v_car_cost_added,
    accounting_payload=accounting_payload||jsonb_build_object(
      'accountingOwner','invoice','previousCarMaintenanceCost',v_previous_maintenance,
      'actualCostByCurrency',v_cost_totals,'carCostCurrency',v_car_cost_currency,
      'carCostAdded',v_car_cost_added,'postedAt',now(),'invoiceCurrency',v_currency),updated_at=now()
  where company_id=p_company_id and id=p_order_id;
  return jsonb_build_object('journalEntryId',v_entry,'costJournalEntries',v_entries);
end;
$$;

create or replace function public.erp_v66_reverse_maintenance_stock(
  p_company_id uuid,p_order_id uuid,p_reason text default null
) returns void language plpgsql security definer set search_path=public as $$
declare
  o public.erp_maintenance_orders%rowtype; p record; s public.erp_warehouse_stock%rowtype;
  v_product_id text; v_warehouse_id text; v_issued numeric; v_returned numeric;
  v_restore numeric; v_now timestamptz:=now(); c record;
begin
  select * into o from public.erp_maintenance_orders
   where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;

  for p in
    select coalesce(source_product_id,product_id::text) product_id,
      coalesce(source_warehouse_id,warehouse_id::text,o.source_warehouse_id,o.warehouse_id::text) warehouse_id,
      max(product_name) product_name
    from public.erp_maintenance_parts
    where company_id=p_company_id and maintenance_order_id=p_order_id
      and not is_deleted and line_type<>'service'
    group by 1,2
  loop
    v_product_id:=p.product_id; v_warehouse_id:=p.warehouse_id;
    select coalesce(sum(abs(public.erp_try_numeric(data->>'quantity',0))),0) into v_issued
      from public.erp_inventory_movements
     where company_id=p_company_id and not is_deleted
       and coalesce(data->>'referenceId',data->>'reference_id')=p_order_id::text
       and lower(coalesce(data->>'referenceType',data->>'reference_type',''))='maintenance_order'
       and lower(coalesce(data->>'movementType',data->>'movement_type',''))='maintenance_out'
       and coalesce(data->>'productId',data->>'product_id')=v_product_id
       and coalesce(data->>'warehouseId',data->>'warehouse_id')=v_warehouse_id;
    select coalesce(sum(abs(public.erp_try_numeric(data->>'quantity',0))),0) into v_returned
      from public.erp_inventory_movements
     where company_id=p_company_id and not is_deleted
       and coalesce(data->>'referenceId',data->>'reference_id')=p_order_id::text
       and lower(coalesce(data->>'movementType',data->>'movement_type',''))='maintenance_return'
       and coalesce(data->>'productId',data->>'product_id')=v_product_id
       and coalesce(data->>'warehouseId',data->>'warehouse_id')=v_warehouse_id;
    v_restore:=greatest(v_issued-v_returned,0);
    if v_restore<=0 then continue; end if;
    s:=public.erp_inventory_ensure_stock(p_company_id,v_warehouse_id,v_product_id);
    update public.erp_warehouse_stock set data=data||jsonb_build_object(
      'quantity',public.erp_try_numeric(data->>'quantity',0)+v_restore,
      'updatedAt',v_now),updated_at=v_now,updated_by=auth.uid() where id=s.id;
    perform public.erp_inventory_insert_movement(
      p_company_id,v_product_id,v_warehouse_id,'maintenance_return',v_restore,0,
      'maintenance_cancel',p_order_id::text,coalesce(nullif(btrim(p_reason),''),'إلغاء صرف الصيانة'));
    perform public.erp_inventory_refresh_product(p_company_id,v_product_id);
  end loop;

  -- Future-proof cancellation if maintenance FIFO rows exist.
  update public.erp_inventory_cost_layers l set
    remaining_quantity=least(l.original_quantity,l.remaining_quantity+c.quantity),
    status='active',updated_at=v_now,updated_by=auth.uid()
  from public.erp_inventory_fifo_consumptions c
  where c.company_id=p_company_id and c.delivery_id=p_order_id and c.status='active' and l.id=c.layer_id;
  update public.erp_inventory_fifo_consumptions set status='reversed',reversed_at=v_now
   where company_id=p_company_id and delivery_id=p_order_id and status='active';
  perform public.erp_phase2_void_reference_journals(
    p_company_id,'maintenance_stock_issue',p_order_id::text);
end;
$$;

-- Rebuild invoice accounting for already-approved paid maintenance invoices
-- that came from the legacy stock-issue-owned workflow.
do $$
declare o record;
begin
  for o in select company_id,id from public.erp_maintenance_orders
    where not is_deleted and pricing_type='paid' and workflow_stage in ('invoice_approved','paid','completed')
      and invoice_journal_entry_id is null and sale_price>0
  loop
    begin
      perform public.erp_v736_post_maintenance_invoice(o.company_id,o.id);
    exception when others then
      update public.erp_maintenance_orders set accounting_payload=accounting_payload||jsonb_build_object(
        'invoiceAccountingMigrationBlocked',true,'invoiceAccountingMigrationError',sqlerrm,
        'invoiceAccountingMigrationCheckedAt',now()),updated_at=now()
       where company_id=o.company_id and id=o.id;
    end;
  end loop;
end $$;

create or replace function public.erp_advance_cloud_maintenance_workflow(
  p_company_id uuid,p_order_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare o public.erp_maintenance_orders%rowtype; p record; s public.erp_warehouse_stock%rowtype;
  v_now timestamptz:=now(); product_id text; warehouse_id text;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['maintenance.approve']);
  select * into o from public.erp_maintenance_orders
   where id=p_order_id and company_id=p_company_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if o.workflow_stage='order_draft' then
    update public.erp_maintenance_orders set workflow_stage='order_approved',status='approved',updated_at=v_now where id=o.id;
  elsif o.workflow_stage='order_approved' then
    update public.erp_maintenance_orders set workflow_stage='stock_issue_draft',stock_issue_number='PENDING',updated_at=v_now where id=o.id;
  elsif o.workflow_stage='stock_issue_draft' then
    for p in select * from public.erp_maintenance_parts
      where company_id=p_company_id and maintenance_order_id=o.id and not is_deleted and line_type<>'service'
    loop
      product_id:=coalesce(p.source_product_id,p.product_id::text);
      warehouse_id:=coalesce(p.source_warehouse_id,p.warehouse_id::text,o.source_warehouse_id,o.warehouse_id::text);
      select * into s from public.erp_warehouse_stock
       where company_id=p_company_id and not is_deleted
         and coalesce(data->>'warehouseId',data->>'warehouse_id')=warehouse_id
         and coalesce(data->>'productId',data->>'product_id')=product_id for update;
      if not found or public.erp_try_numeric(s.data->>'quantity',0)-public.erp_try_numeric(s.data->>'reservedQuantity',0)<p.quantity then
        raise exception 'maintenance_insufficient_stock:%',p.product_name;
      end if;
      update public.erp_warehouse_stock set data=data||jsonb_build_object(
        'quantity',public.erp_try_numeric(data->>'quantity',0)-p.quantity,'updatedAt',v_now),
        updated_at=v_now,updated_by=auth.uid() where id=s.id;
      perform public.erp_inventory_insert_movement(
        p_company_id,product_id,warehouse_id,'maintenance_out',-p.quantity,0,
        'maintenance_order',o.id::text,'صرف كمي للصيانة '||o.order_number);
    end loop;
    perform public.erp_phase3_refresh_maintenance_products(p_company_id,o.id);
    update public.erp_maintenance_orders set workflow_stage='stock_issue_approved',
      stock_issue_number=case when stock_issue_number is null or stock_issue_number='PENDING' then
        public.erp_next_document_number(p_company_id,'maintenance_stock_issue','MSI',o.maintenance_date) else stock_issue_number end,
      car_cost_added=0,updated_at=v_now where id=o.id;
  elsif o.workflow_stage='stock_issue_approved' then
    update public.erp_maintenance_orders set
      workflow_stage=case when pricing_type='paid' then 'invoice_draft' else 'completed' end,
      status=case when pricing_type='paid' then status else 'completed' end,
      invoice_number=case when pricing_type='paid' then 'PENDING' else invoice_number end,updated_at=v_now where id=o.id;
  elsif o.workflow_stage='invoice_draft' then
    update public.erp_maintenance_orders set invoice_number=case
      when invoice_number is null or invoice_number='PENDING' then
        public.erp_next_document_number(p_company_id,'maintenance_invoice','MINV',o.maintenance_date)
      else invoice_number end,updated_at=v_now where id=o.id;
    perform public.erp_v736_post_maintenance_invoice(p_company_id,o.id);
    update public.erp_maintenance_orders set workflow_stage='invoice_approved',updated_at=v_now where id=o.id;
  else raise exception 'maintenance_no_next_stage'; end if;
end;
$$;

create or replace function public.erp_cancel_cloud_maintenance_order(
  p_company_id uuid,p_order_id uuid,p_reason text default null
) returns void language plpgsql security definer set search_path=public as $$
declare o public.erp_maintenance_orders%rowtype; j jsonb; v_prev numeric;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['maintenance.cancel']);
  select * into o from public.erp_maintenance_orders
   where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if o.workflow_stage='cancelled' then return; end if;
  if coalesce(o.paid_amount,0)>0 or exists(select 1 from public.erp_maintenance_payments
    where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted) then
    raise exception 'maintenance_reverse_payments_first';
  end if;
  perform public.erp_v736_void_journal_id(p_company_id,o.invoice_journal_entry_id);
  for j in select value from jsonb_array_elements(coalesce(o.cost_journal_entry_ids,'[]'::jsonb)) loop
    perform public.erp_v736_void_journal_id(p_company_id,j->>'journalEntryId');
  end loop;
  if not o.is_sold_car and o.car_cost_added>0 then
    v_prev:=public.erp_try_numeric(o.accounting_payload->>'previousCarMaintenanceCost',0);
    update public.erp_cars set data=data||jsonb_build_object(
      'maintenanceCost',v_prev,'maintenance_cost',v_prev,'maintenanceValuationInvoiceId',null,'updatedAt',now()),
      updated_at=now(),updated_by=auth.uid()
    where company_id=p_company_id and id=coalesce(o.source_car_id,o.car_id::text) and not is_deleted;
  end if;
  perform public.erp_v66_reverse_maintenance_stock(
    p_company_id,p_order_id,coalesce(nullif(btrim(p_reason),''),'إلغاء أمر الصيانة'));
  update public.erp_maintenance_orders set workflow_stage='cancelled',status='cancelled',cancelled_at=now(),
    cancel_reason=nullif(btrim(p_reason),''),car_cost_added=0,invoice_journal_entry_id=null,
    cost_journal_entry_ids='[]'::jsonb,accounting_payload=accounting_payload||jsonb_build_object('reversedAt',now()),updated_at=now()
  where company_id=p_company_id and id=p_order_id;
end;
$$;

create or replace function public.erp_sync_opportunity_sales_lifecycle(
  p_company_id uuid,p_opportunity_id text
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_slug text; o public.erp_sales_orders_cloud%rowtype;
  d public.erp_commercial_workflow_documents%rowtype;
  i public.erp_commercial_workflow_documents%rowtype;
  v_status text:='pending'; v_closed timestamptz; v_paid numeric:=0; v_remaining numeric:=0;
begin
  if nullif(btrim(coalesce(p_opportunity_id,'')),'') is null then return; end if;
  select slug into v_slug from public.companies where id=p_company_id;
  if v_slug is null then return; end if;
  select * into o from public.erp_sales_orders_cloud
   where company_id=p_company_id and opportunity_id=p_opportunity_id and not is_deleted
   order by updated_at desc,created_at desc,id desc limit 1;
  if found then
    if lower(coalesce(o.status,'draft'))='approved' then v_status:='won'; v_closed:=now(); end if;
    select * into d from public.erp_commercial_workflow_documents
     where company_id=p_company_id and parent_id=o.id and module='sales'
       and document_type='delivery' and not is_deleted order by updated_at desc limit 1;
    select * into i from public.erp_commercial_workflow_documents
     where company_id=p_company_id and parent_id=o.id and module='sales'
       and document_type='invoice' and not is_deleted order by updated_at desc limit 1;
    if i.id is not null then
      v_paid:=public.erp_try_numeric(i.payload->>'paidAmount',0);
      v_remaining:=public.erp_try_numeric(i.payload->>'remainingAmount',public.erp_try_numeric(i.payload->>'totalAmount',0));
    end if;
  end if;
  update public.erp_records set payload=payload||jsonb_build_object(
    'status',v_status,'closedAt',v_closed,
    'salesOrderId',case when o.id is null then null else o.id::text end,
    'saleId',case when o.id is null then null else o.id::text end,
    'salesOrderNumber',o.order_number,'salesOrderStatus',o.status,
    'deliveryId',case when d.id is null then null else d.id::text end,
    'deliveryNumber',d.document_number,'deliveryStatus',d.status,
    'invoiceId',case when i.id is null then null else i.id::text end,
    'invoiceNumber',i.document_number,'invoiceStatus',i.status,
    'invoiceCurrency',i.payload->>'currency','paidAmount',v_paid,'remainingAmount',v_remaining,
    'paymentStatus',coalesce(i.payload->>'paymentStatus',case when v_remaining<=0 and i.id is not null then 'paid' else 'unpaid' end),
    'workflowLinked',o.id is not null,'opportunityStatusSource','sales_workflow','updatedAt',now()),updated_at=now()
  where company_id=v_slug and entity_type='opportunities' and record_id=p_opportunity_id and deleted_at is null;
end;
$$;

create or replace function public.erp_v736_sales_document_opportunity_sync()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_company uuid; v_order uuid; v_opportunity text;
begin
  v_company:=case when tg_op='DELETE' then old.company_id else new.company_id end;
  v_order:=case when tg_op='DELETE' then old.parent_id else new.parent_id end;
  if (case when tg_op='DELETE' then old.module else new.module end)<>'sales' then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;
  select opportunity_id into v_opportunity from public.erp_sales_orders_cloud
   where company_id=v_company and id=v_order limit 1;
  perform public.erp_sync_opportunity_sales_lifecycle(v_company,v_opportunity);
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists erp_v736_sales_document_opportunity_sync_trg on public.erp_commercial_workflow_documents;
create trigger erp_v736_sales_document_opportunity_sync_trg
after insert or update or delete on public.erp_commercial_workflow_documents
for each row execute function public.erp_v736_sales_document_opportunity_sync();

create or replace function public.erp_v736_sales_order_opportunity_sync()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='DELETE' then
    perform public.erp_sync_opportunity_sales_lifecycle(old.company_id,old.opportunity_id);
    return old;
  elsif tg_op='INSERT' then
    perform public.erp_sync_opportunity_sales_lifecycle(new.company_id,new.opportunity_id);
    return new;
  end if;

  if old.company_id is distinct from new.company_id
     or old.opportunity_id is distinct from new.opportunity_id then
    perform public.erp_sync_opportunity_sales_lifecycle(old.company_id,old.opportunity_id);
  end if;
  if new.company_id is distinct from old.company_id
     or new.opportunity_id is distinct from old.opportunity_id
     or new.status is distinct from old.status
     or new.is_deleted is distinct from old.is_deleted
     or new.order_number is distinct from old.order_number then
    perform public.erp_sync_opportunity_sales_lifecycle(new.company_id,new.opportunity_id);
  end if;
  return new;
end;
$$;

drop trigger if exists erp_v736_sales_order_opportunity_sync_trg on public.erp_sales_orders_cloud;
create trigger erp_v736_sales_order_opportunity_sync_trg
after insert or update or delete on public.erp_sales_orders_cloud
for each row execute function public.erp_v736_sales_order_opportunity_sync();

do $$ declare r record; begin
  for r in select distinct company_id,opportunity_id from public.erp_sales_orders_cloud
    where not is_deleted and nullif(btrim(coalesce(opportunity_id,'')),'') is not null
  loop perform public.erp_sync_opportunity_sales_lifecycle(r.company_id,r.opportunity_id); end loop;
end $$;

revoke all on function public.erp_create_cloud_sales_workflow_invoice(uuid,uuid) from public,anon;
revoke all on function public.erp_create_cloud_purchase_workflow_invoice(uuid,uuid) from public,anon;
revoke all on function public.erp_approve_cloud_sales_workflow_invoice(uuid,uuid) from public,anon;
revoke all on function public.erp_approve_cloud_purchase_workflow_invoice(uuid,uuid) from public,anon;
revoke all on function public.erp_cancel_cloud_sales_workflow_invoice(uuid,uuid,text) from public,anon;
revoke all on function public.erp_cancel_cloud_purchase_workflow_invoice(uuid,uuid,text) from public,anon;
revoke all on function public.erp_phase2_approve_purchase_receipt(uuid,uuid) from public,anon;
revoke all on function public.erp_phase2_approve_sales_delivery(uuid,uuid) from public,anon;
revoke all on function public.erp_advance_cloud_maintenance_workflow(uuid,uuid) from public,anon;
revoke all on function public.erp_cancel_cloud_maintenance_order(uuid,uuid,text) from public,anon;

grant execute on function public.erp_create_cloud_sales_workflow_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_create_cloud_purchase_workflow_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_approve_cloud_sales_workflow_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_approve_cloud_purchase_workflow_invoice(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_cancel_cloud_sales_workflow_invoice(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_cancel_cloud_purchase_workflow_invoice(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_phase2_approve_purchase_receipt(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_phase2_approve_sales_delivery(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_advance_cloud_maintenance_workflow(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_cancel_cloud_maintenance_order(uuid,uuid,text) to authenticated,service_role;

commit;
