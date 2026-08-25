-- Quality Line ERP 18.9.9 / V7.3.9
-- Operational invoice approval without automatic capitalization journals,
-- strict same-currency cashbox payments, resilient logistics invoicing,
-- working cash transfers, and complete opportunity/sales lifecycle links.
begin;

-- Approved logistics from older deployments may not contain the later
-- inventoryPostedAt marker. Approval status + validated allocations are the
-- source of truth, so those documents must remain invoiceable.
create or replace function public.erp_v736_active_logistics(
  p_company_id uuid,p_order_id uuid,p_module text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_type text; v_result jsonb;
begin
  v_type:=case when p_module='sales' then 'delivery' when p_module='purchases' then 'receipt' else null end;
  if v_type is null then raise exception 'invalid_workflow_module'; end if;

  select jsonb_build_object(
    'id',d.id::text,'number',d.document_number,
    'allocations',coalesce(d.payload->'allocations','[]'::jsonb),
    'effectiveAt',coalesce(d.effective_at,d.created_at),
    'warehouseIds',coalesce(d.payload->'warehouseIds','[]'::jsonb)
  ) into v_result
  from public.erp_commercial_workflow_documents d
  where d.company_id=p_company_id and d.parent_id=p_order_id and d.module=p_module
    and d.document_type=v_type and lower(coalesce(d.status,''))='approved'
    and not d.is_deleted
  order by d.updated_at desc,d.created_at desc,d.id desc limit 1;

  if v_result is null then raise exception 'approved_inventory_document_required'; end if;
  perform public.erp_validate_commercial_warehouse_allocations(
    p_company_id,p_order_id,p_module,v_result->'allocations',p_module='sales');

  update public.erp_commercial_workflow_documents
  set payload=payload||jsonb_build_object(
      'inventoryPostedAt',coalesce(payload->>'inventoryPostedAt',now()::text),
      'accountingOwner','none','quantityOnly',true
    ),updated_at=now()
  where company_id=p_company_id and id=(v_result->>'id')::uuid;
  return v_result;
end;
$$;

-- Invoice approval remains the operational/valuation boundary but does not
-- require revenue, asset, cost or capitalization account inputs and does not
-- create automatic journal entries.
create or replace function public.erp_approve_cloud_workflow_invoice(
  p_company_id uuid,p_invoice_id uuid,p_module text
) returns void
language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  v_currency text; v_total numeric; v_logistics_id uuid; v_order_rate numeric:=1;
  r record; v_old_data jsonb; v_snapshots jsonb:='[]'::jsonb;
  v_cost_currency text; v_unit_value numeric;
begin
  if p_module not in ('sales','purchases') then raise exception 'invalid_workflow_module'; end if;
  perform public.erp_require_any_cloud_permission(
    p_company_id,
    case when p_module='sales'
      then array['sales.approve','sales.update']
      else array['purchases.approve','purchases.update'] end
  );

  select * into d from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and module=p_module
    and document_type='invoice' and not is_deleted for update;
  if not found then raise exception 'workflow_invoice_not_found'; end if;
  if lower(coalesce(d.status,''))='approved' then return; end if;
  if lower(coalesce(d.status,''))<>'draft' then raise exception 'workflow_invoice_invalid_status'; end if;

  v_currency:=upper(coalesce(d.payload->>'currency',''));
  v_total:=public.erp_try_numeric(d.payload->>'totalAmount',0);
  v_logistics_id:=nullif(d.payload->>'logisticsDocumentId','')::uuid;
  if v_currency not in ('IQD','USD') or v_total<=0 or v_logistics_id is null then
    raise exception 'workflow_invoice_invalid_amount_currency_or_logistics';
  end if;
  perform public.erp_v736_assert_invoice_logistics(
    p_company_id,d.parent_id,p_module,v_logistics_id,d.payload->'allocations');

  if p_module='sales' then
    perform 1 from public.erp_sales_orders_cloud
    where company_id=p_company_id and id=d.parent_id and status='approved'
      and upper(currency)=v_currency and not is_deleted;
    if not found then raise exception 'invoice_order_currency_mismatch'; end if;

    for r in select * from public.erp_sales_order_items_cloud
      where company_id=p_company_id and order_id=d.parent_id and not is_deleted order by id
    loop
      if r.item_type='car' then
        select data into v_old_data from public.erp_cars
        where company_id=p_company_id and id=r.item_id and not is_deleted;
        v_snapshots:=v_snapshots||jsonb_build_array(jsonb_build_object(
          'itemType','car','itemId',r.item_id,
          'previousSalePrice',public.erp_try_numeric(v_old_data->>'salePrice',public.erp_try_numeric(v_old_data->>'sale_price',0)),
          'previousSaleCurrency',coalesce(v_old_data->>'saleCurrency',v_old_data->>'sale_currency',v_old_data->>'currency')));
        update public.erp_cars set data=data||jsonb_build_object(
          'salePrice',r.unit_price,'sale_price',r.unit_price,
          'saleCurrency',v_currency,'sale_currency',v_currency,
          'valuationUpdatedByInvoiceId',p_invoice_id::text,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id and not is_deleted;
      else
        select data into v_old_data from public.erp_inventory
        where company_id=p_company_id and id=r.item_id and not is_deleted;
        v_snapshots:=v_snapshots||jsonb_build_array(jsonb_build_object(
          'itemType','product','itemId',r.item_id,
          'previousSalePrice',public.erp_try_numeric(v_old_data->>'salePrice',public.erp_try_numeric(v_old_data->>'sale_price',0)),
          'previousSaleCurrency',coalesce(v_old_data->>'saleCurrency',v_old_data->>'sale_currency',v_old_data->>'currency')));
        update public.erp_inventory set data=data||jsonb_build_object(
          'salePrice',r.unit_price,'sale_price',r.unit_price,
          'saleCurrency',v_currency,'sale_currency',v_currency,
          'valuationUpdatedByInvoiceId',p_invoice_id::text,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id and not is_deleted;
      end if;
    end loop;
    perform public.erp_mark_sales_order_cars_sold(p_company_id,d.parent_id,p_invoice_id);
  else
    select exchange_rate into v_order_rate from public.erp_purchase_orders_cloud
    where company_id=p_company_id and id=d.parent_id and status='approved'
      and upper(currency)=v_currency and exchange_rate>0 and not is_deleted;
    if not found then raise exception 'invoice_order_currency_mismatch'; end if;

    for r in select * from public.erp_purchase_order_items_cloud
      where company_id=p_company_id and order_id=d.parent_id and not is_deleted order by id
    loop
      if r.item_type='car' then
        select data into v_old_data from public.erp_cars
        where company_id=p_company_id and id=r.item_id and not is_deleted;
      else
        select data into v_old_data from public.erp_inventory
        where company_id=p_company_id and id=r.item_id and not is_deleted;
      end if;
      v_cost_currency:=upper(coalesce(
        nullif(v_old_data->>'costCurrency',''),nullif(v_old_data->>'cost_currency',''),
        nullif(v_old_data->>'currency',''),v_currency));
      if v_cost_currency not in ('IQD','USD') then v_cost_currency:=v_currency; end if;
      v_unit_value:=public.erp_v736_convert_currency(
        r.unit_cost,v_currency,v_cost_currency,v_order_rate);
      v_snapshots:=v_snapshots||jsonb_build_array(jsonb_build_object(
        'itemType',r.item_type,'itemId',r.item_id,
        'previousPurchasePrice',public.erp_try_numeric(v_old_data->>'purchasePrice',public.erp_try_numeric(v_old_data->>'purchase_price',0)),
        'previousUnitCost',public.erp_try_numeric(v_old_data->>'unitCost',public.erp_try_numeric(v_old_data->>'unit_cost',0)),
        'previousCostCurrency',coalesce(v_old_data->>'costCurrency',v_old_data->>'cost_currency',v_old_data->>'currency')));
      if r.item_type='car' then
        update public.erp_cars set data=data||jsonb_build_object(
          'purchasePrice',v_unit_value,'purchase_price',v_unit_value,
          'costCurrency',v_cost_currency,'cost_currency',v_cost_currency,
          'valuationPendingInvoice',false,'valuationUpdatedByInvoiceId',p_invoice_id::text,
          'purchaseInvoiceCurrency',v_currency,'purchaseExchangeRate',v_order_rate,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id and not is_deleted;
      else
        update public.erp_inventory set data=data||jsonb_build_object(
          'purchasePrice',v_unit_value,'purchase_price',v_unit_value,
          'unitCost',v_unit_value,'unit_cost',v_unit_value,
          'costCurrency',v_cost_currency,'cost_currency',v_cost_currency,
          'valuationPendingInvoice',false,'valuationUpdatedByInvoiceId',p_invoice_id::text,
          'purchaseInvoiceCurrency',v_currency,'purchaseExchangeRate',v_order_rate,'updatedAt',now()),
          updated_at=now(),updated_by=auth.uid()
        where company_id=p_company_id and id=r.item_id and not is_deleted;
        perform public.erp_inventory_refresh_product(p_company_id,r.item_id);
      end if;
    end loop;
  end if;

  update public.erp_commercial_workflow_documents
  set status='approved',
      payload=(payload-'journalEntryId'-'costJournalEntries'-'costBreakdown')||jsonb_build_object(
        'approvedAt',now(),'approvedBy',auth.uid(),'valuationApplied',true,
        'valuationSnapshots',v_snapshots,'accountingOwner','none',
        'automaticJournalPosting',false,'paidAmount',public.erp_try_numeric(payload->>'paidAmount',0),
        'remainingAmount',greatest(0,v_total-public.erp_try_numeric(payload->>'paidAmount',0))
      ),updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=p_invoice_id;

  update public.erp_commercial_workflow_documents
  set payload=(payload-'journalEntryId'-'costJournalEntries')||jsonb_build_object(
      'valuationPendingInvoice',false,'valuedByInvoiceId',p_invoice_id::text,
      'valuationAppliedAt',now(),'accountingOwner','none','quantityOnly',true
    ),updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=v_logistics_id;

  perform public.erp_commercial_audit(
    p_company_id,p_module,d.parent_id,d.id,d.document_number,
    'approve_invoice',d.status,'approved','operational invoice approval without automatic capitalization journals');
end;
$$;

-- Shared operational payment batch. Payment, invoice and order remain linked;
-- cashbox and invoice/order must use exactly the same currency.
create or replace function public.erp_apply_cloud_workflow_invoice_payment_batch(
  p_company_id uuid,p_invoice_id uuid,p_module text,p_payments jsonb
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  p jsonb; v_currency text; v_cash_id text; v_cash_currency text;
  v_amount numeric; v_cash_amount numeric; v_remaining numeric; v_paid numeric;
  v_payment_id text; v_tx_id text; v_voucher text; v_date timestamptz;
  v_results jsonb:='[]'::jsonb; v_payments jsonb;
begin
  if p_module not in ('sales','purchases') then raise exception 'invalid_workflow_module'; end if;
  perform public.erp_require_any_cloud_permission(
    p_company_id,case when p_module='sales' then array['cashbox.receipt'] else array['cashbox.payment'] end);
  if p_payments is null or jsonb_typeof(p_payments)<>'array' or jsonb_array_length(p_payments)=0 then
    raise exception 'payment_batch_required';
  end if;
  select * into d from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and module=p_module
    and document_type='invoice' and status='approved' and not is_deleted for update;
  if not found then raise exception 'approved_invoice_required'; end if;

  v_currency:=upper(coalesce(d.payload->>'currency',''));
  v_paid:=public.erp_try_numeric(d.payload->>'paidAmount',0);
  v_remaining:=public.erp_try_numeric(d.payload->>'remainingAmount',
    public.erp_try_numeric(d.payload->>'totalAmount',0)-v_paid);
  v_payments:=coalesce(d.payload->'payments','[]'::jsonb);

  for p in select value from jsonb_array_elements(p_payments) loop
    v_cash_id:=nullif(btrim(p->>'cashAccountId'),'');
    v_amount:=public.erp_try_numeric(p->>'invoiceAmount',0);
    v_cash_amount:=public.erp_try_numeric(p->>'cashAmount',v_amount);
    v_date:=public.erp_try_timestamptz(p->>'paymentDate',now());
    if upper(coalesce(p->>'paymentCurrency',''))<>v_currency then
      raise exception 'payment_currency_must_match_order_currency:%',v_currency;
    end if;
    if public.erp_try_numeric(p->>'exchangeRate',1)<>1 then
      raise exception 'same_currency_payment_exchange_rate_must_be_one';
    end if;
    if v_cash_id is null or v_amount<=0 or abs(v_cash_amount-v_amount)>0.01 or v_amount>v_remaining+0.01 then
      raise exception 'invalid_or_excessive_invoice_payment';
    end if;
    select upper(coalesce(ca.data->>'currency','')) into v_cash_currency
    from public.erp_cash_accounts ca
    where ca.company_id=p_company_id and ca.id=v_cash_id and not ca.is_deleted
      and public.erp_try_boolean(ca.data->>'isActive',true) for share;
    if not found or v_cash_currency<>v_currency then
      raise exception 'cashbox_currency_must_match_order_currency:%',v_currency;
    end if;

    v_payment_id:=gen_random_uuid()::text;
    v_tx_id:=gen_random_uuid()::text;
    v_voucher:=public.erp_next_document_number(
      p_company_id,case when p_module='sales' then 'customer_payment' else 'supplier_payment' end,
      case when p_module='sales' then 'CP' else 'SP' end,v_date);
    insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by)
    values(p_company_id,v_tx_id,jsonb_build_object(
      'id',v_tx_id,'cashAccountId',v_cash_id,'voucherNumber',v_voucher,
      'type',case when p_module='sales' then 'receipt' else 'payment' end,
      'category',case when p_module='sales' then 'customer_payment' else 'supplier_payment' end,
      'amount',v_cash_amount,'currency',v_currency,'exchangeRate',1,
      'invoiceAmount',v_amount,'invoiceCurrency',v_currency,'transactionDate',v_date,
      'referenceType','workflow_invoice_payment','referenceId',v_payment_id,
      'invoiceId',p_invoice_id::text,'orderId',d.parent_id::text,'module',p_module,
      'invoiceNumber',d.document_number,'notes',nullif(btrim(p->>'notes'),''),
      'automaticJournalPosting',false
    ),auth.uid(),auth.uid());

    v_paid:=v_paid+v_amount;
    v_remaining:=greatest(0,v_remaining-v_amount);
    v_payments:=v_payments||jsonb_build_array(jsonb_build_object(
      'paymentId',v_payment_id,'cashTransactionId',v_tx_id,'voucherNumber',v_voucher,
      'cashAccountId',v_cash_id,'paymentCurrency',v_currency,'invoiceCurrency',v_currency,
      'invoiceAmount',v_amount,'cashAmount',v_cash_amount,'exchangeRate',1,
      'paymentDate',v_date,'notes',nullif(btrim(p->>'notes'),''),
      'journalEntryId',null,'automaticJournalPosting',false));
    v_results:=v_results||jsonb_build_array(v_payments->-1);
  end loop;

  update public.erp_commercial_workflow_documents
  set payload=payload||jsonb_build_object(
      'payments',v_payments,'paidAmount',v_paid,'remainingAmount',v_remaining,
      'paymentStatus',case when v_remaining<=0.001 then 'paid' when v_paid>0 then 'partial' else 'unpaid' end,
      'automaticJournalPosting',false
    ),updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=p_invoice_id;
  return v_results;
end;
$$;

create or replace function public.erp_pay_cloud_sales_workflow_invoice_batch(
  p_company_id uuid,p_invoice_id uuid,p_payments jsonb
) returns jsonb language sql security definer set search_path=public as $$
  select public.erp_apply_cloud_workflow_invoice_payment_batch(
    p_company_id,p_invoice_id,'sales',p_payments)
$$;

create or replace function public.erp_pay_cloud_purchase_workflow_invoice_batch(
  p_company_id uuid,p_invoice_id uuid,p_payments jsonb
) returns jsonb language sql security definer set search_path=public as $$
  select public.erp_apply_cloud_workflow_invoice_payment_batch(
    p_company_id,p_invoice_id,'purchases',p_payments)
$$;

-- Maintenance invoice approval follows the same operational rule: stock issue
-- changes quantity, invoice approval changes stage/number, and no automatic
-- capitalization journal or account input is required.
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
    update public.erp_maintenance_orders set
      invoice_number=case when invoice_number is null or invoice_number='PENDING' then
        public.erp_next_document_number(p_company_id,'maintenance_invoice','MINV',o.maintenance_date)
        else invoice_number end,
      workflow_stage='invoice_approved',status='approved',car_cost_added=0,
      invoice_journal_entry_id=null,cost_journal_entry_ids='[]'::jsonb,
      accounting_payload=coalesce(accounting_payload,'{}'::jsonb)||jsonb_build_object(
        'automaticJournalPosting',false,'accountingOwner','none','approvedAt',v_now),
      updated_at=v_now
    where id=o.id;
  else raise exception 'maintenance_no_next_stage'; end if;
end;
$$;

create or replace function public.erp_v737_record_maintenance_payment(
  p_company_id uuid,p_order_id uuid,p_payment jsonb
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  o public.erp_maintenance_orders%rowtype; v_payment_id uuid:=gen_random_uuid();
  v_key text; v_tx text:=gen_random_uuid()::text; v_cash text; v_currency text;
  v_amount numeric; v_remaining numeric; v_next numeric; v_date timestamptz;
  v_voucher text; v_existing public.erp_maintenance_payments%rowtype;
begin
  perform public.erp_require_any_cloud_permission(p_company_id,array['cashbox.receipt']);
  select * into o from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found or o.pricing_type<>'paid' or o.sale_price<=0
     or o.workflow_stage not in ('invoice_approved','paid') then
    raise exception 'maintenance_approved_invoice_required';
  end if;
  v_currency:=upper(o.currency_code);
  if upper(coalesce(p_payment->>'paymentCurrency',''))<>v_currency then
    raise exception 'payment_currency_must_match_order_currency:%',v_currency;
  end if;
  if public.erp_try_numeric(p_payment->>'exchangeRate',1)<>1 then
    raise exception 'same_currency_payment_exchange_rate_must_be_one';
  end if;
  v_key:=coalesce(nullif(btrim(p_payment->>'paymentKey'),''),gen_random_uuid()::text);
  select * into v_existing from public.erp_maintenance_payments
  where company_id=p_company_id and maintenance_order_id=p_order_id
    and payment_key=v_key and not is_deleted limit 1;
  if found then return jsonb_build_object('paymentId',v_existing.id,'idempotent',true); end if;

  v_cash:=nullif(btrim(p_payment->>'cashAccountId'),'');
  v_amount:=public.erp_try_numeric(p_payment->>'invoiceAmount',0);
  if abs(public.erp_try_numeric(p_payment->>'cashAmount',v_amount)-v_amount)>0.01 then
    raise exception 'maintenance_cash_amount_mismatch';
  end if;
  v_remaining:=greatest(0,o.sale_price-coalesce(o.paid_amount,0));
  if v_cash is null or v_amount<=0 or v_amount>v_remaining+0.01 then
    raise exception 'maintenance_invalid_payment';
  end if;
  perform 1 from public.erp_cash_accounts ca
  where ca.company_id=p_company_id and ca.id=v_cash and not ca.is_deleted
    and public.erp_try_boolean(ca.data->>'isActive',true)
    and upper(coalesce(ca.data->>'currency',''))=v_currency for share;
  if not found then raise exception 'cashbox_currency_must_match_order_currency:%',v_currency; end if;

  v_date:=public.erp_try_timestamptz(p_payment->>'paymentDate',now());
  v_voucher:=public.erp_next_document_number(p_company_id,'maintenance_payment','MP',v_date);
  insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_tx,jsonb_build_object(
    'id',v_tx,'cashAccountId',v_cash,'voucherNumber',v_voucher,'type','receipt',
    'category','maintenance_payment','amount',v_amount,'currency',v_currency,
    'exchangeRate',1,'invoiceAmount',v_amount,'invoiceCurrency',v_currency,
    'transactionDate',v_date,'referenceType','maintenance_payment',
    'referenceId',v_payment_id::text,'maintenanceOrderId',o.id::text,
    'invoiceNumber',o.invoice_number,'paymentKey',v_key,
    'notes',nullif(btrim(p_payment->>'notes'),''),'automaticJournalPosting',false
  ),auth.uid(),auth.uid());

  insert into public.erp_maintenance_payments(
    id,company_id,maintenance_order_id,amount,currency_code,exchange_rate,
    amount_in_order_currency,payment_date,notes,cash_transaction_id,
    journal_entry_id,updated_at,updated_by,payment_key,settlement_mode,
    settlement_account_id,payment_payload
  ) values(
    v_payment_id,p_company_id,o.id,v_amount,v_currency,1,v_amount,v_date,
    nullif(btrim(p_payment->>'notes'),''),v_tx,null,now(),auth.uid(),v_key,
    'partial',null,p_payment||jsonb_build_object(
      'paymentId',v_payment_id::text,'cashTransactionId',v_tx,
      'invoiceCurrency',v_currency,'journalEntryId',null,'automaticJournalPosting',false)
  );

  v_next:=least(o.sale_price,coalesce(o.paid_amount,0)+v_amount);
  update public.erp_maintenance_orders set paid_amount=v_next,
    workflow_stage=case when v_next+0.001>=sale_price then 'paid' else 'invoice_approved' end,
    status=case when v_next+0.001>=sale_price then 'completed' else 'approved' end,
    updated_at=now() where company_id=p_company_id and id=o.id;
  return jsonb_build_object(
    'paymentId',v_payment_id,'paymentKey',v_key,'cashTransactionId',v_tx,
    'journalEntryId',null,'invoiceAmount',v_amount,'cashAmount',v_amount,
    'paymentCurrency',v_currency,'invoiceCurrency',v_currency,
    'remainingAmount',greatest(0,o.sale_price-v_next));
end;
$$;

-- Cash transfer is an operational cash document. It supports same-currency
-- transfers (rate 1) and cross-currency transfers without requiring ledger or
-- FX-clearing account definitions.
create or replace function public.erp_transfer_cloud_cash(
  p_company_id uuid,p_from_cash_account_id text,p_to_cash_account_id text,
  p_source_amount numeric,p_target_amount numeric,p_exchange_rate numeric,
  p_transfer_date timestamptz,p_notes text default null
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_from public.erp_cash_accounts%rowtype; v_to public.erp_cash_accounts%rowtype;
  v_transfer text:=gen_random_uuid()::text; v_number text;
  v_from_currency text; v_to_currency text; v_balance numeric:=0;
  v_out text:=gen_random_uuid()::text; v_in text:=gen_random_uuid()::text;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['cashbox.transfer','cashbox.payment','cashbox.receipt','accounting.update']);
  if p_from_cash_account_id=p_to_cash_account_id or p_source_amount<=0
     or p_target_amount<=0 or p_exchange_rate<=0 or p_transfer_date is null then
    raise exception 'invalid_cash_transfer';
  end if;
  select * into v_from from public.erp_cash_accounts
  where company_id=p_company_id and id=p_from_cash_account_id and not is_deleted
    and public.erp_try_boolean(data->>'isActive',true) for update;
  if not found then raise exception 'source_cashbox_not_found'; end if;
  select * into v_to from public.erp_cash_accounts
  where company_id=p_company_id and id=p_to_cash_account_id and not is_deleted
    and public.erp_try_boolean(data->>'isActive',true) for update;
  if not found then raise exception 'target_cashbox_not_found'; end if;
  v_from_currency:=upper(coalesce(v_from.data->>'currency',''));
  v_to_currency:=upper(coalesce(v_to.data->>'currency',''));
  if v_from_currency not in ('IQD','USD') or v_to_currency not in ('IQD','USD') then
    raise exception 'unsupported_cashbox_currency';
  end if;
  if v_from_currency=v_to_currency then
    if abs(p_exchange_rate-1)>0.000001 or abs(p_source_amount-p_target_amount)>0.01 then
      raise exception 'same_currency_transfer_requires_rate_one';
    end if;
  elsif abs(p_target_amount-(p_source_amount*p_exchange_rate))>
      greatest(0.01,abs(p_source_amount*p_exchange_rate)*0.000001) then
    raise exception 'cash_transfer_amount_rate_mismatch';
  end if;

  select public.erp_try_numeric(coalesce(v_from.data->>'openingBalance',v_from.data->>'opening_balance'),0)
    +coalesce(sum(case when lower(coalesce(ct.data->>'type','')) in ('receipt','income','in','cash_in','customer_receipt','transfer_in')
      then public.erp_try_numeric(ct.data->>'amount',0) else -public.erp_try_numeric(ct.data->>'amount',0) end),0)
  into v_balance from public.erp_cash_transactions ct
  where ct.company_id=p_company_id and not ct.is_deleted
    and coalesce(ct.data->>'cashAccountId',ct.data->>'cash_account_id')=p_from_cash_account_id;
  if v_balance<p_source_amount then raise exception 'source_cashbox_balance_insufficient'; end if;

  v_number:=public.erp_next_document_number(p_company_id,'cash_transfer','CTR',p_transfer_date);
  insert into public.erp_cash_transfers(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_transfer,jsonb_build_object(
    'id',v_transfer,'transferNumber',v_number,'fromAccountId',p_from_cash_account_id,
    'toAccountId',p_to_cash_account_id,'sourceAmount',p_source_amount,
    'sourceCurrency',v_from_currency,'targetAmount',p_target_amount,
    'targetCurrency',v_to_currency,'exchangeRate',p_exchange_rate,
    'transferDate',p_transfer_date,'notes',p_notes,'automaticJournalPosting',false,
    'createdAt',now()),auth.uid(),auth.uid());

  insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by)
  values
  (p_company_id,v_out,jsonb_build_object(
    'id',v_out,'voucherNumber',v_number||'-OUT','type','payment','category','cash_transfer',
    'amount',p_source_amount,'currency',v_from_currency,'transactionDate',p_transfer_date,
    'partyType','cash_account','partyId',p_to_cash_account_id,'partyName',v_to.data->>'name',
    'paymentMethod','cash_transfer','referenceType','cash_transfer','referenceId',v_transfer,
    'cashAccountId',p_from_cash_account_id,'notes',p_notes,'automaticJournalPosting',false),auth.uid(),auth.uid()),
  (p_company_id,v_in,jsonb_build_object(
    'id',v_in,'voucherNumber',v_number||'-IN','type','receipt','category','cash_transfer',
    'amount',p_target_amount,'currency',v_to_currency,'transactionDate',p_transfer_date,
    'partyType','cash_account','partyId',p_from_cash_account_id,'partyName',v_from.data->>'name',
    'paymentMethod','cash_transfer','referenceType','cash_transfer','referenceId',v_transfer,
    'cashAccountId',p_to_cash_account_id,'notes',p_notes,'automaticJournalPosting',false),auth.uid(),auth.uid());
end;
$$;

-- Keep every active opportunity link synchronized, including draft orders.
create or replace function public.erp_sync_opportunity_sales_lifecycle(
  p_company_id uuid,p_opportunity_id text
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_slug text; o public.erp_sales_orders_cloud%rowtype;
  d public.erp_commercial_workflow_documents%rowtype;
  i public.erp_commercial_workflow_documents%rowtype;
  v_paid numeric:=0; v_remaining numeric:=0; v_status text:='pending';
begin
  if nullif(btrim(coalesce(p_opportunity_id,'')),'') is null then return; end if;
  select slug into v_slug from public.companies where id=p_company_id;
  if v_slug is null then return; end if;
  select * into o from public.erp_sales_orders_cloud
  where company_id=p_company_id and opportunity_id=p_opportunity_id and not is_deleted
  order by updated_at desc,created_at desc,id desc limit 1;
  if o.id is not null then
    v_status:=case when lower(coalesce(o.status,''))='approved' then 'won' else 'pending' end;
    select * into d from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=o.id and module='sales'
      and document_type='delivery' and not is_deleted
      and lower(coalesce(status,'')) not in ('cancelled','canceled','voided')
    order by updated_at desc,created_at desc,id desc limit 1;
    select * into i from public.erp_commercial_workflow_documents
    where company_id=p_company_id and parent_id=o.id and module='sales'
      and document_type='invoice' and not is_deleted
      and lower(coalesce(status,'')) not in ('cancelled','canceled','voided')
    order by updated_at desc,created_at desc,id desc limit 1;
    v_paid:=public.erp_try_numeric(i.payload->>'paidAmount',0);
    v_remaining:=public.erp_try_numeric(i.payload->>'remainingAmount',public.erp_try_numeric(i.payload->>'totalAmount',0));
  end if;
  update public.erp_records set payload=payload||jsonb_build_object(
    'status',v_status,'closedAt',case when v_status='won' then now() else null end,
    'salesOrderId',case when o.id is null then null else o.id::text end,
    'saleId',case when o.id is null then null else o.id::text end,
    'salesOrderNumber',o.order_number,'salesOrderStatus',o.status,
    'deliveryId',case when d.id is null then null else d.id::text end,
    'deliveryNumber',d.document_number,'deliveryStatus',d.status,
    'invoiceId',case when i.id is null then null else i.id::text end,
    'invoiceNumber',i.document_number,'invoiceStatus',i.status,
    'invoiceCurrency',i.payload->>'currency','paidAmount',v_paid,'remainingAmount',v_remaining,
    'paymentStatus',case when i.id is null then 'not_invoiced' when v_remaining<=0.001 then 'paid' when v_paid>0 then 'partial' else 'unpaid' end,
    'workflowLinked',o.id is not null,'workflowCanOpen',o.id is not null,
    'workflowAccountingOwner','none','opportunityStatusSource','sales_workflow','updatedAt',now()
  ),updated_at=now()
  where company_id=v_slug and entity_type='opportunities'
    and record_id=p_opportunity_id and deleted_at is null;
end;
$$;

revoke all on function public.erp_v736_active_logistics(uuid,uuid,text) from public,anon;
revoke all on function public.erp_approve_cloud_workflow_invoice(uuid,uuid,text) from public,anon;
revoke all on function public.erp_apply_cloud_workflow_invoice_payment_batch(uuid,uuid,text,jsonb) from public,anon;
revoke all on function public.erp_pay_cloud_sales_workflow_invoice_batch(uuid,uuid,jsonb) from public,anon;
revoke all on function public.erp_pay_cloud_purchase_workflow_invoice_batch(uuid,uuid,jsonb) from public,anon;
revoke all on function public.erp_advance_cloud_maintenance_workflow(uuid,uuid) from public,anon;
revoke all on function public.erp_v737_record_maintenance_payment(uuid,uuid,jsonb) from public,anon;
revoke all on function public.erp_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) from public,anon;
revoke all on function public.erp_sync_opportunity_sales_lifecycle(uuid,text) from public,anon;

grant execute on function public.erp_v736_active_logistics(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_approve_cloud_workflow_invoice(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_apply_cloud_workflow_invoice_payment_batch(uuid,uuid,text,jsonb) to authenticated,service_role;
grant execute on function public.erp_pay_cloud_sales_workflow_invoice_batch(uuid,uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_pay_cloud_purchase_workflow_invoice_batch(uuid,uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_advance_cloud_maintenance_workflow(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_v737_record_maintenance_payment(uuid,uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text) to authenticated,service_role;
grant execute on function public.erp_sync_opportunity_sales_lifecycle(uuid,text) to authenticated,service_role;

-- Refresh current projections so draft opportunity links become visible now.
do $$ declare r record; begin
  for r in select company_id,opportunity_id from public.erp_sales_orders_cloud
    where not is_deleted and nullif(btrim(coalesce(opportunity_id,'')),'') is not null
  loop
    perform public.erp_sync_opportunity_sales_lifecycle(r.company_id,r.opportunity_id);
  end loop;
end $$;

commit;
