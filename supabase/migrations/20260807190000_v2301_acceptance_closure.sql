-- Quality Line ERP V23.0.1 acceptance closure.
-- Final closes: currency-specific revenue selection and vehicle scrap accounting/state.
begin;

-- Prefer the explicitly configured revenue account for the definition currency.
-- The legacy single-account field remains a fallback for migrated records only.
create or replace function public.erp_v764_definition_accounts(
  p_company_id uuid, p_item_type text, p_item_id text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare d jsonb; c text; asset_id text; cost_id text; revenue_id text;
begin
  d:=public.erp_v764_definition_data(p_company_id,p_item_type,p_item_id);
  c:=public.erp_v764_definition_currency(p_company_id,p_item_type,p_item_id);
  asset_id:=nullif(coalesce(d->>'inventoryAssetAccountId',d->>'inventory_asset_account_id'),'');
  cost_id:=nullif(coalesce(d->>'salesCostExpenseAccountId',d->>'sales_cost_expense_account_id',
    d->>'costOfSalesAccountId',d->>'cost_of_sales_account_id'),'');
  revenue_id:=nullif(coalesce(
    case when c='USD' then coalesce(d->>'salesRevenueUsdAccountId',d->>'sales_revenue_usd_account_id')
         else coalesce(d->>'salesRevenueIqdAccountId',d->>'sales_revenue_iqd_account_id') end,
    d->>'salesRevenueAccountId',d->>'sales_revenue_account_id'),'');
  if lower(coalesce(d->>'itemType',d->>'item_type','stock'))<>'service' then
    perform public.erp_phase2_account_guard(p_company_id,asset_id,'asset',c);
    perform public.erp_phase2_account_guard(p_company_id,cost_id,'expense',c);
  end if;
  perform public.erp_phase2_account_guard(p_company_id,revenue_id,'revenue',c);
  return jsonb_build_object('currency',c,'assetAccountId',asset_id,
    'costExpenseAccountId',cost_id,'revenueAccountId',revenue_id);
end; $$;

create or replace function public.erp_v2301_is_scrap_warehouse(
  p_company_id uuid,p_warehouse_id text
) returns boolean
language sql stable security definer set search_path=public as $$
  select coalesce((select lower(coalesce(w.data->>'warehouseType',w.data->>'type','normal'))
      in ('scrap_consumption','scrap','damage')
    from public.erp_warehouses w
    where w.company_id=p_company_id and w.id=p_warehouse_id and not w.is_deleted),false)
$$;

-- A car moved into the scrap/damage warehouse must leave inventory value:
--   Dr scrap expense (same definition currency) / Cr car inventory asset.
-- Reversing/removing the transfer retires that journal. The transfer effective
-- date is the accounting date, not the browser execution time.
create or replace function public.erp_v2301_reconcile_car_scrap_transfer()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_car_id text;
  v_from_id text;
  v_to_id text;
  v_from_scrap boolean;
  v_to_scrap boolean;
  v_car jsonb;
  v_currency text;
  v_asset text;
  v_expense text;
  v_amount numeric;
  v_effective timestamptz;
  v_lines jsonb;
  v_status text;
begin
  -- Always retire a prior posting first. This makes edits, reversals and
  -- recycle-bin deletion idempotent and prevents duplicate scrap journals.
  perform public.erp_phase2_void_reference_journals(
    new.company_id,'inventory_scrap_car',new.id);

  v_status:=lower(btrim(coalesce(new.data->>'status','completed')));
  if new.is_deleted or v_status<>'completed' then return new; end if;

  v_car_id:=nullif(coalesce(new.data->>'carId',new.data->>'car_id'),'');
  v_from_id:=nullif(coalesce(new.data->>'fromWarehouseId',new.data->>'from_warehouse_id'),'');
  v_to_id:=nullif(coalesce(new.data->>'toWarehouseId',new.data->>'to_warehouse_id'),'');
  if v_car_id is null or v_from_id is null or v_to_id is null then return new; end if;

  v_from_scrap:=public.erp_v2301_is_scrap_warehouse(new.company_id,v_from_id);
  v_to_scrap:=public.erp_v2301_is_scrap_warehouse(new.company_id,v_to_id);
  if v_from_scrap=v_to_scrap then return new; end if;

  v_car:=public.erp_v764_definition_data(new.company_id,'car',v_car_id);
  v_currency:=public.erp_v764_definition_currency(new.company_id,'car',v_car_id);
  v_asset:=nullif(coalesce(v_car->>'inventoryAssetAccountId',v_car->>'inventory_asset_account_id'),'');
  perform public.erp_phase2_account_guard(new.company_id,v_asset,'asset',v_currency);

  -- Maintenance is not capitalized in this application; the vehicle inventory
  -- value therefore follows the purchase/cost value only.
  v_amount:=abs(public.erp_try_numeric(
    coalesce(v_car->>'purchasePrice',v_car->>'purchase_price',v_car->>'costPrice',v_car->>'cost_price'),0));
  if v_amount<=0 then raise exception 'car_scrap_value_required:%',v_car_id; end if;

  v_effective:=public.erp_try_timestamptz(
    coalesce(new.data->>'effectiveAt',new.data->>'effective_at',new.data->>'transferDate',new.data->>'transfer_date'),
    new.created_at);
  perform public.erp_validate_operational_date(new.company_id,'inventory',v_effective);

  if v_to_scrap then
    v_expense:=public.erp_v764_scrap_expense_account(new.company_id,v_to_id,v_currency);
    v_lines:=jsonb_build_array(
      jsonb_build_object('accountId',v_expense,'debit',v_amount,'credit',0,'currency',v_currency,
        'description','Vehicle damage/scrap expense'),
      jsonb_build_object('accountId',v_asset,'debit',0,'credit',v_amount,'currency',v_currency,
        'description','Vehicle inventory asset retired to scrap'));
    perform public.erp_phase2_insert_journal_at(
      new.company_id,'inventory_scrap_car',new.id,'SCR-CAR-'||left(new.id,18),
      coalesce(nullif(new.data->>'notes',''),'Vehicle moved to damage/scrap warehouse'),
      v_currency,v_lines,v_effective);

    update public.erp_cars c
    set data=(c.data-'scrapWarehouseTransferId'-'scrappedAt')||jsonb_build_object(
          'status','تالفة','scrapWarehouseTransferId',new.id,'scrappedAt',v_effective,'updatedAt',now()),
        updated_at=now(),updated_by=auth.uid()
    where c.company_id=new.company_id and c.id=v_car_id and not c.is_deleted;
  else
    -- This branch supports a future direct move out of scrap. The current UI
    -- normally uses Reverse/Delete, which retires the original journal.
    v_expense:=public.erp_v764_scrap_expense_account(new.company_id,v_from_id,v_currency);
    v_lines:=jsonb_build_array(
      jsonb_build_object('accountId',v_asset,'debit',v_amount,'credit',0,'currency',v_currency,
        'description','Vehicle inventory asset restored from scrap'),
      jsonb_build_object('accountId',v_expense,'debit',0,'credit',v_amount,'currency',v_currency,
        'description','Vehicle damage/scrap expense reversed'));
    perform public.erp_phase2_insert_journal_at(
      new.company_id,'inventory_scrap_car',new.id,'SCR-CAR-R-'||left(new.id,16),
      coalesce(nullif(new.data->>'notes',''),'Vehicle restored from damage/scrap warehouse'),
      v_currency,v_lines,v_effective);
  end if;
  return new;
end; $$;

drop trigger if exists erp_car_scrap_accounting on public.erp_car_warehouse_transfers;
create trigger erp_car_scrap_accounting
after insert or update of data,is_deleted on public.erp_car_warehouse_transfers
for each row execute function public.erp_v2301_reconcile_car_scrap_transfer();

-- Reverse must also work after the scrap trigger marks the vehicle as damaged.
create or replace function public.erp_reverse_car_warehouse_transfer(
  p_company_id uuid,p_transfer_id text,p_user_name text
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_t public.erp_car_warehouse_transfers%rowtype;
  v_car public.erp_cars%rowtype;
  v_now timestamptz:=clock_timestamp();
  v_current text;
  v_status text;
  v_to_scrap boolean;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  select * into v_t from public.erp_car_warehouse_transfers
  where company_id=p_company_id and id=p_transfer_id and not is_deleted for update;
  if not found then raise exception 'سند النقل غير موجود'; end if;
  if lower(coalesce(v_t.data->>'status',''))<>'completed' then raise exception 'تم إرجاع هذا النقل مسبقاً'; end if;

  select * into v_car from public.erp_cars
  where company_id=p_company_id and id=coalesce(v_t.data->>'carId',v_t.data->>'car_id') and not is_deleted for update;
  if not found then raise exception 'السيارة غير موجودة'; end if;
  v_current:=nullif(btrim(coalesce(v_car.data->>'warehouseId',v_car.data->>'warehouse_id','')),'');
  if v_current<>coalesce(v_t.data->>'toWarehouseId',v_t.data->>'to_warehouse_id') then
    raise exception 'لا يمكن الإرجاع لوجود حركة مخزنية لاحقة';
  end if;
  if nullif(btrim(coalesce(v_car.data->>'salesOrderId','')),'') is not null then
    raise exception 'لا يمكن إرجاع النقل لأن السيارة دخلت في مسار بيع';
  end if;

  v_status:=lower(btrim(coalesce(v_car.data->>'status','')));
  v_to_scrap:=public.erp_v2301_is_scrap_warehouse(
    p_company_id,coalesce(v_t.data->>'toWarehouseId',v_t.data->>'to_warehouse_id'));
  if v_status not in ('available','متوفرة','متوفر','متاحة')
     and not (v_to_scrap and v_status in ('damaged','scrap','تالفة','تالف')) then
    raise exception 'لا يمكن إرجاع النقل لأن حالة السيارة لا تسمح بذلك';
  end if;

  update public.erp_cars c
  set data=(c.data-'warehouseId'-'warehouse_id'-'scrapWarehouseTransferId'-'scrappedAt')||jsonb_build_object(
        'warehouseId',coalesce(v_t.data->>'fromWarehouseId',v_t.data->>'from_warehouse_id'),
        'warehouse_id',coalesce(v_t.data->>'fromWarehouseId',v_t.data->>'from_warehouse_id'),
        'status',case when v_to_scrap then 'متوفرة' else coalesce(c.data->>'status','متوفرة') end,
        'updatedAt',v_now),
      updated_at=v_now,updated_by=auth.uid()
  where c.company_id=p_company_id and c.id=coalesce(v_t.data->>'carId',v_t.data->>'car_id');

  update public.erp_car_warehouse_transfers t
  set data=t.data||jsonb_build_object(
        'status','reversed','reversedAt',v_now,'reversedByUserId',auth.uid()::text,
        'reversedByUserName',p_user_name),updated_at=v_now,updated_by=auth.uid()
  where t.company_id=p_company_id and t.id=p_transfer_id;
end; $$;

-- Keep the policy diagnostic aligned with all accepted scrap warehouse codes.
create or replace function public.erp_v764_accounting_policy_audit(p_company_id uuid)
returns jsonb language sql security definer set search_path=public as $$
  select jsonb_build_object(
    'companyId',p_company_id,
    'definitionsMissingCurrency',(select count(*) from public.erp_inventory i where i.company_id=p_company_id and not i.is_deleted and upper(coalesce(i.data->>'definitionCurrency',i.data->>'costCurrency',i.data->>'currency','')) not in ('USD','IQD'))
      +(select count(*) from public.erp_cars c where c.company_id=p_company_id and not c.is_deleted and upper(coalesce(c.data->>'definitionCurrency',c.data->>'costCurrency',c.data->>'currency','')) not in ('USD','IQD')),
    'scrapWarehousesMissingDualExpense',(select count(*) from public.erp_warehouses w where w.company_id=p_company_id and not w.is_deleted and lower(coalesce(w.data->>'warehouseType',w.data->>'type','')) in ('scrap_consumption','scrap','damage') and (coalesce(w.data->>'scrapExpenseUsdAccountId','')='' or coalesce(w.data->>'scrapExpenseIqdAccountId','')='')),
    'checkedAt',timezone('utc',now())
  ); $$;

revoke all on function public.erp_v2301_is_scrap_warehouse(uuid,text) from public,anon;
revoke all on function public.erp_v2301_reconcile_car_scrap_transfer() from public,anon;
grant execute on function public.erp_v2301_is_scrap_warehouse(uuid,text) to authenticated,service_role;
grant execute on function public.erp_reverse_car_warehouse_transfer(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_v764_definition_accounts(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_v764_accounting_policy_audit(uuid) to authenticated,service_role;

notify pgrst,'reload schema';
commit;

-- NOTE: the statements below are intentionally after the first COMMIT so this
-- migration remains readable in source review. PostgreSQL accepts a new
-- transaction block for the remaining acceptance fixes.
begin;

-- All sales/purchase logistics documents inherit the order's operational
-- timestamp before numbering and before any inventory impact.
create or replace function public.erp_v2301_inherit_commercial_effective_at()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_effective timestamptz;
begin
  if new.parent_id is null or new.module not in ('sales','purchases')
     or new.document_type not in ('delivery','receipt','invoice') then
    return new;
  end if;
  if new.module='sales' then
    select coalesce(o.effective_at,o.created_at) into v_effective
    from public.erp_sales_orders_cloud o
    where o.company_id=new.company_id and o.id=new.parent_id and not o.is_deleted;
  else
    select coalesce(o.effective_at,o.created_at) into v_effective
    from public.erp_purchase_orders_cloud o
    where o.company_id=new.company_id and o.id=new.parent_id and not o.is_deleted;
  end if;
  if v_effective is not null then
    perform public.erp_validate_operational_date(new.company_id,new.module,v_effective);
    new.effective_at:=v_effective;
    new.payload:=coalesce(new.payload,'{}'::jsonb)||jsonb_build_object('effectiveAt',v_effective);
  end if;
  return new;
end; $$;

drop trigger if exists erp_a_v2301_workflow_effective_date on public.erp_commercial_workflow_documents;
create trigger erp_a_v2301_workflow_effective_date
before insert or update of parent_id,module,document_type
on public.erp_commercial_workflow_documents
for each row execute function public.erp_v2301_inherit_commercial_effective_at();

-- Inventory movements created by commercial/maintenance workflows are dated
-- from their source document. createdAt remains the technical execution time.
create or replace function public.erp_v2301_align_inventory_movement_effective_at()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_type text:=lower(coalesce(new.data->>'referenceType','')); v_effective timestamptz;
begin
  if v_type in ('purchase_receipt','sales_delivery') then
    select d.effective_at into v_effective
    from public.erp_commercial_workflow_documents d
    where d.company_id=new.company_id and d.id=nullif(new.data->>'referenceId','')::uuid and not d.is_deleted;
  elsif v_type='maintenance_order' then
    select o.maintenance_date into v_effective
    from public.erp_maintenance_orders o
    where o.company_id=new.company_id and o.id=nullif(new.data->>'referenceId','')::uuid and not o.is_deleted;
  else
    return new;
  end if;
  if v_effective is null then return new; end if;
  update public.erp_inventory_movements m
  set data=m.data||jsonb_build_object('movementDate',v_effective,'effectiveAt',v_effective),
      updated_at=now(),updated_by=auth.uid()
  where m.company_id=new.company_id and m.id=new.id;
  return new;
end; $$;

drop trigger if exists erp_v2301_inventory_movement_effective_date on public.erp_inventory_movements;
create trigger erp_v2301_inventory_movement_effective_date
after insert on public.erp_inventory_movements
for each row execute function public.erp_v2301_align_inventory_movement_effective_at();

-- Vehicle receipt/delivery timestamps must show the entered operational time,
-- while approvedAt/inventoryPostedAt continue to represent the audit time.
create or replace function public.erp_v2301_align_commercial_car_effective_at()
returns trigger language plpgsql security definer set search_path=public as $$
declare a record; v_effective timestamptz:=new.effective_at;
begin
  if new.status<>'approved' or old.status='approved' or v_effective is null then return new; end if;
  if (new.module='purchases' and new.document_type='receipt') then
    for a in select * from jsonb_to_recordset(coalesce(new.payload->'allocations','[]'::jsonb))
      as x("itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
    loop
      if lower(a."itemType")='car' then
        update public.erp_cars c set data=c.data||jsonb_build_object(
          'receivedAt',v_effective,'inventoryEffectiveAt',v_effective,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
        where c.company_id=new.company_id and c.id=a."itemId" and not c.is_deleted;
      end if;
    end loop;
  elsif (new.module='sales' and new.document_type='delivery') then
    for a in select * from jsonb_to_recordset(coalesce(new.payload->'allocations','[]'::jsonb))
      as x("itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
    loop
      if lower(a."itemType")='car' then
        update public.erp_cars c set data=c.data||jsonb_build_object(
          'deliveredAt',v_effective,'inventoryEffectiveAt',v_effective,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
        where c.company_id=new.company_id and c.id=a."itemId" and not c.is_deleted;
      end if;
    end loop;
  end if;
  update public.erp_commercial_workflow_documents d
  set payload=d.payload||jsonb_build_object('inventoryEffectiveAt',v_effective),updated_at=now()
  where d.company_id=new.company_id and d.id=new.id;
  return new;
end; $$;

drop trigger if exists erp_v2301_commercial_car_effective_date on public.erp_commercial_workflow_documents;
create trigger erp_v2301_commercial_car_effective_date
after update of status on public.erp_commercial_workflow_documents
for each row execute function public.erp_v2301_align_commercial_car_effective_at();

-- Maintenance, like sales/purchases, is single-currency at line level.
create or replace function public.erp_v2301_maintenance_line_currency_guard()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_order_currency text; v_item_id text; v_item_currency text;
begin
  select upper(o.currency_code) into v_order_currency
  from public.erp_maintenance_orders o
  where o.company_id=new.company_id and o.id=new.maintenance_order_id and not o.is_deleted;
  v_item_id:=nullif(coalesce(new.source_product_id,new.product_id::text),'');
  if v_order_currency is null or v_item_id is null then return new; end if;
  v_item_currency:=public.erp_v764_definition_currency(new.company_id,'product',v_item_id);
  if v_item_currency<>v_order_currency then
    raise exception 'maintenance_item_currency_mismatch:%:%:%',v_item_id,v_item_currency,v_order_currency;
  end if;
  return new;
end; $$;

drop trigger if exists erp_v2301_maintenance_line_currency on public.erp_maintenance_parts;
create trigger erp_v2301_maintenance_line_currency
before insert or update of source_product_id,product_id,maintenance_order_id
on public.erp_maintenance_parts for each row
execute function public.erp_v2301_maintenance_line_currency_guard();

-- Maintenance invoice owns accounting, but must not capitalize consumed parts
-- into the vehicle value. Parts still post Dr configured cost / Cr configured
-- inventory asset; revenue/customer and payment chains remain unchanged.
create or replace function public.erp_v736_post_maintenance_invoice(
  p_company_id uuid,p_order_id uuid
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  o public.erp_maintenance_orders%rowtype; p record; ac jsonb; defaults jsonb;
  v_currency text; v_effective timestamptz; v_partner_account text; v_revenue_account text;
  v_revenue_lines jsonb; v_cost_lines jsonb:='{}'::jsonb; v_lines jsonb;
  v_entry text; v_entries jsonb:='[]'::jsonb; v_cost numeric; v_cost_currency text;
  e record; v_cost_totals jsonb:='{}'::jsonb;
begin
  select * into o from public.erp_maintenance_orders
   where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if o.invoice_journal_entry_id is not null then
    return jsonb_build_object('journalEntryId',o.invoice_journal_entry_id,
      'costJournalEntries',o.cost_journal_entry_ids,'capitalizationApplied',false);
  end if;
  if o.pricing_type<>'paid' or o.sale_price<=0 then raise exception 'paid_maintenance_invoice_required'; end if;
  v_currency:=upper(o.currency_code); v_effective:=coalesce(o.maintenance_date,now());
  perform public.erp_validate_operational_date(p_company_id,'maintenance',v_effective);
  defaults:=public.erp_v736_ensure_currency_revenue_accounts(p_company_id);
  v_revenue_account:=case when v_currency='IQD' then defaults->>'maintenanceRevenueIqdAccountId' else defaults->>'maintenanceRevenueUsdAccountId' end;
  perform public.erp_phase2_account_guard(p_company_id,v_revenue_account,'revenue',v_currency);
  if o.customer_id is not null then
    perform public.erp_v764_assert_partner_dual_ledgers(p_company_id,o.customer_id::text,'customer');
    v_partner_account:=public.erp_workflow_partner_account(p_company_id,'customer',o.customer_id::text,v_currency);
  else
    select account_id into v_partner_account from public.erp_accounts
     where organization_id=p_company_id and code='1400' and is_active limit 1;
  end if;
  if v_partner_account is null then raise exception 'maintenance_receivable_account_missing'; end if;
  perform public.erp_phase2_account_guard(p_company_id,v_partner_account,'asset',v_currency);
  v_revenue_lines:=jsonb_build_array(
    jsonb_build_object('accountId',v_partner_account,'debit',o.sale_price,'credit',0,'currency',v_currency,'description','ذمة فاتورة الصيانة'),
    jsonb_build_object('accountId',v_revenue_account,'debit',0,'credit',o.sale_price,'currency',v_currency,'description','إيراد خدمات الصيانة'));
  v_entry:=public.erp_phase2_insert_journal_at(
    p_company_id,'maintenance_invoice_revenue',p_order_id::text,
    public.erp_next_document_number(p_company_id,'maintenance_invoice_journal','MIJ',v_effective),
    'قيد فاتورة الصيانة '||coalesce(o.invoice_number,o.order_number),v_currency,v_revenue_lines,v_effective);

  for p in select * from public.erp_maintenance_parts
    where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted and line_type<>'service'
  loop
    if public.erp_v764_definition_currency(p_company_id,'product',coalesce(p.source_product_id,p.product_id::text))<>v_currency then
      raise exception 'maintenance_item_currency_mismatch:%',coalesce(p.source_product_id,p.product_id::text);
    end if;
    ac:=public.erp_v764_definition_accounts(p_company_id,'product',coalesce(p.source_product_id,p.product_id::text));
    v_cost_currency:=ac->>'currency';
    v_cost:=p.quantity*coalesce(nullif(p.unit_cost,0),public.erp_try_numeric(
      (public.erp_v764_definition_data(p_company_id,'product',coalesce(p.source_product_id,p.product_id::text)))->>'unitCost',0));
    if v_cost>0 then
      v_lines:=coalesce(v_cost_lines->v_cost_currency,'[]'::jsonb)||jsonb_build_array(
        jsonb_build_object('accountId',ac->>'costExpenseAccountId','debit',v_cost,'credit',0,'currency',v_cost_currency,
          'description','كلفة مواد الصيانة - '||p.product_name,'itemId',coalesce(p.source_product_id,p.product_id::text),'quantity',p.quantity),
        jsonb_build_object('accountId',ac->>'assetAccountId','debit',0,'credit',v_cost,'currency',v_cost_currency,
          'description','إخراج كلفة مواد الصيانة - '||p.product_name,'itemId',coalesce(p.source_product_id,p.product_id::text),'quantity',p.quantity));
      v_cost_lines:=jsonb_set(v_cost_lines,array[v_cost_currency],v_lines,true);
      v_cost_totals:=jsonb_set(v_cost_totals,array[v_cost_currency],
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

  update public.erp_maintenance_orders set invoice_journal_entry_id=v_entry,
    cost_journal_entry_ids=v_entries,car_cost_added=0,
    accounting_payload=accounting_payload||jsonb_build_object(
      'accountingOwner','invoice','actualCostByCurrency',v_cost_totals,
      'carCostAdded',0,'capitalizationApplied',false,'capitalizationPolicy','disabled',
      'postedAt',now(),'effectiveAt',v_effective,'invoiceCurrency',v_currency),updated_at=now()
  where company_id=p_company_id and id=p_order_id;
  return jsonb_build_object('journalEntryId',v_entry,'costJournalEntries',v_entries,
    'capitalizationApplied',false,'effectiveAt',v_effective);
end;
$$;

revoke all on function public.erp_v2301_inherit_commercial_effective_at() from public,anon;
revoke all on function public.erp_v2301_align_inventory_movement_effective_at() from public,anon;
revoke all on function public.erp_v2301_align_commercial_car_effective_at() from public,anon;
revoke all on function public.erp_v2301_maintenance_line_currency_guard() from public,anon;
grant execute on function public.erp_v736_post_maintenance_invoice(uuid,uuid) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
