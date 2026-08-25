-- Quality Line ERP 18.9.10 / V7.4.0
-- Responsive module scaling, definition-owned accounting, linked FX cashbox
-- settlements, and compact seven-character document identifiers.
begin;

-- Restore definition-owned accounting at invoice approval. The restored
-- implementation resolves inventory/cost/revenue accounts from each product,
-- service or vehicle definition and separates journals by their native currency.
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

-- Restore maintenance invoice accounting from configured material/service
-- accounts while preserving order/invoice/payment links.
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

-- Compact identifier: letters first followed by a simple numeric sequence;
-- total length never exceeds seven characters.
create or replace function public.erp_next_document_number(
  p_company_id uuid,p_document_key text,p_prefix text,p_effective_at timestamptz default now()
) returns text language plpgsql security definer set search_path=public as $$
declare v_year int:=extract(year from coalesce(p_effective_at,now()))::int; v_next bigint;
  v_prefix text:=upper(regexp_replace(coalesce(p_prefix,''),'[^A-Za-z]','','g'));
  v_digits int;
begin
  if auth.uid() is not null and not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied';
  end if;
  v_prefix:=left(v_prefix,3);
  if v_prefix='' then v_prefix:='DOC'; end if;
  v_digits:=7-length(v_prefix);
  insert into public.erp_document_sequences(company_id,document_key,fiscal_year,last_number)
  values(p_company_id,lower(btrim(p_document_key)),v_year,1)
  on conflict(company_id,document_key,fiscal_year) do update
    set last_number=public.erp_document_sequences.last_number+1,updated_at=now()
  returning last_number into v_next;
  if v_next>=power(10,v_digits) then
    raise exception 'compact_document_sequence_exhausted:%',p_document_key;
  end if;
  return v_prefix||lpad(v_next::text,v_digits,'0');
end;
$$;

-- Cross-currency invoice payments use a user-selected source cashbox and a
-- linked cashbox in the invoice currency. The source movement records the real
-- cash paid/received; the linked box receives and settles the converted amount
-- atomically, keeping invoice/order/payment references intact.
create or replace function public.erp_apply_cloud_workflow_invoice_payment_batch(
  p_company_id uuid,p_invoice_id uuid,p_module text,p_payments jsonb
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  p jsonb; v_invoice_currency text; v_payment_currency text;
  v_cash_id text; v_linked_cash_id text; v_cash_currency text; v_linked_currency text;
  v_amount numeric; v_cash_amount numeric; v_rate numeric; v_expected numeric;
  v_remaining numeric; v_paid numeric; v_payment_id text; v_tx_id text;
  v_bridge_in text; v_bridge_out text; v_voucher text; v_date timestamptz;
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
  v_invoice_currency:=upper(coalesce(d.payload->>'currency',''));
  v_paid:=public.erp_try_numeric(d.payload->>'paidAmount',0);
  v_remaining:=public.erp_try_numeric(d.payload->>'remainingAmount',
    public.erp_try_numeric(d.payload->>'totalAmount',0)-v_paid);
  v_payments:=coalesce(d.payload->'payments','[]'::jsonb);

  for p in select value from jsonb_array_elements(p_payments) loop
    v_cash_id:=nullif(btrim(p->>'cashAccountId'),'');
    v_linked_cash_id:=nullif(btrim(p->>'linkedCashAccountId'),'');
    v_payment_currency:=upper(coalesce(p->>'paymentCurrency',''));
    v_amount:=public.erp_try_numeric(p->>'invoiceAmount',0);
    v_cash_amount:=public.erp_try_numeric(p->>'cashAmount',0);
    v_rate:=public.erp_try_numeric(p->>'exchangeRate',0);
    v_date:=public.erp_try_timestamptz(p->>'paymentDate',now());
    if v_cash_id is null or v_amount<=0 or v_cash_amount<=0 or v_rate<=0 or v_amount>v_remaining+0.01 then
      raise exception 'invalid_or_excessive_invoice_payment';
    end if;
    select upper(coalesce(ca.data->>'currency','')) into v_cash_currency
    from public.erp_cash_accounts ca where ca.company_id=p_company_id and ca.id=v_cash_id
      and not ca.is_deleted and public.erp_try_boolean(ca.data->>'isActive',true) for share;
    if not found or v_cash_currency<>v_payment_currency then raise exception 'payment_cashbox_currency_mismatch'; end if;
    if v_payment_currency=v_invoice_currency then
      if abs(v_rate-1)>0.000001 or abs(v_cash_amount-v_amount)>0.01 then
        raise exception 'same_currency_payment_requires_rate_one';
      end if;
      v_linked_cash_id:=v_cash_id;
    else
      if v_linked_cash_id is null or v_linked_cash_id=v_cash_id then raise exception 'linked_invoice_currency_cashbox_required'; end if;
      select upper(coalesce(ca.data->>'currency','')) into v_linked_currency
      from public.erp_cash_accounts ca where ca.company_id=p_company_id and ca.id=v_linked_cash_id
        and not ca.is_deleted and public.erp_try_boolean(ca.data->>'isActive',true) for share;
      if not found or v_linked_currency<>v_invoice_currency then raise exception 'linked_cashbox_must_use_invoice_currency'; end if;
      v_expected:=case
        when v_invoice_currency='USD' and v_payment_currency='IQD' then v_amount*v_rate
        when v_invoice_currency='IQD' and v_payment_currency='USD' then v_amount/v_rate
        else null end;
      if v_expected is null or abs(v_cash_amount-v_expected)>greatest(0.01,abs(v_expected)*0.005) then
        raise exception 'cash_amount_exchange_rate_mismatch';
      end if;
    end if;

    v_payment_id:=gen_random_uuid()::text; v_tx_id:=gen_random_uuid()::text;
    v_voucher:=public.erp_next_document_number(p_company_id,
      case when p_module='sales' then 'customer_payment' else 'supplier_payment' end,
      case when p_module='sales' then 'RC' else 'PY' end,v_date);
    insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by)
    values(p_company_id,v_tx_id,jsonb_build_object(
      'id',v_tx_id,'cashAccountId',v_cash_id,'voucherNumber',v_voucher,
      'type',case when p_module='sales' then 'receipt' else 'payment' end,
      'category',case when p_module='sales' then 'customer_payment' else 'supplier_payment' end,
      'amount',v_cash_amount,'currency',v_payment_currency,'exchangeRate',v_rate,
      'invoiceAmount',v_amount,'invoiceCurrency',v_invoice_currency,'transactionDate',v_date,
      'referenceType','workflow_invoice_payment','referenceId',v_payment_id,
      'invoiceId',p_invoice_id::text,'orderId',d.parent_id::text,'module',p_module,
      'invoiceNumber',d.document_number,'linkedCashAccountId',v_linked_cash_id,
      'notes',nullif(btrim(p->>'notes'),''),'automaticJournalPosting',true),auth.uid(),auth.uid());

    if v_payment_currency<>v_invoice_currency then
      v_bridge_in:=gen_random_uuid()::text; v_bridge_out:=gen_random_uuid()::text;
      insert into public.erp_cash_transactions(company_id,id,data,created_by,updated_by) values
      (p_company_id,v_bridge_in,jsonb_build_object(
        'id',v_bridge_in,'cashAccountId',v_linked_cash_id,'voucherNumber',v_voucher,
        'type','receipt','category','linked_fx_conversion','amount',v_amount,
        'currency',v_invoice_currency,'exchangeRate',v_rate,'transactionDate',v_date,
        'referenceType','workflow_invoice_payment_fx','referenceId',v_payment_id,
        'sourceCashAccountId',v_cash_id,'invoiceId',p_invoice_id::text,'orderId',d.parent_id::text),auth.uid(),auth.uid()),
      (p_company_id,v_bridge_out,jsonb_build_object(
        'id',v_bridge_out,'cashAccountId',v_linked_cash_id,'voucherNumber',v_voucher,
        'type','payment','category','invoice_settlement','amount',v_amount,
        'currency',v_invoice_currency,'exchangeRate',1,'transactionDate',v_date,
        'referenceType','workflow_invoice_payment_fx','referenceId',v_payment_id,
        'invoiceId',p_invoice_id::text,'orderId',d.parent_id::text),auth.uid(),auth.uid());
    end if;

    v_paid:=v_paid+v_amount; v_remaining:=greatest(0,v_remaining-v_amount);
    v_payments:=v_payments||jsonb_build_array(jsonb_build_object(
      'paymentId',v_payment_id,'cashTransactionId',v_tx_id,'voucherNumber',v_voucher,
      'cashAccountId',v_cash_id,'linkedCashAccountId',v_linked_cash_id,
      'paymentCurrency',v_payment_currency,'invoiceCurrency',v_invoice_currency,
      'invoiceAmount',v_amount,'cashAmount',v_cash_amount,'exchangeRate',v_rate,
      'paymentDate',v_date,'notes',nullif(btrim(p->>'notes'),''),'automaticJournalPosting',true));
    v_results:=v_results||jsonb_build_array(v_payments->-1);
  end loop;
  update public.erp_commercial_workflow_documents set payload=payload||jsonb_build_object(
    'payments',v_payments,'paidAmount',v_paid,'remainingAmount',v_remaining,
    'paymentStatus',case when v_remaining<=0.001 then 'paid' when v_paid>0 then 'partial' else 'unpaid' end)
  ,updated_at=now(),updated_by=auth.uid() where company_id=p_company_id and id=p_invoice_id;
  return v_results;
end;
$$;

revoke all on function public.erp_apply_cloud_workflow_invoice_payment_batch(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.erp_apply_cloud_workflow_invoice_payment_batch(uuid,uuid,text,jsonb) to authenticated,service_role;

create or replace function public.erp_assign_professional_document_number()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_prefix text;
  v_key text;
  v_effective timestamptz;
  v_parent_effective timestamptz;
  v_expected_year text;
begin
  if tg_table_name='erp_sales_orders_cloud' then
    v_effective:=coalesce(new.effective_at,new.created_at,now());
    v_expected_year:=extract(year from v_effective)::int::text;
    if new.order_number is null
       or new.order_number !~ '^[A-Z]{2,3}[0-9]{4,5}$' then
      new.order_number:=public.erp_next_document_number(
        new.company_id,'sales_order','SO',v_effective);
    end if;
  elsif tg_table_name='erp_purchase_orders_cloud' then
    v_effective:=coalesce(new.effective_at,new.created_at,now());
    v_expected_year:=extract(year from v_effective)::int::text;
    if new.order_number is null
       or new.order_number !~ '^[A-Z]{2,3}[0-9]{4,5}$' then
      new.order_number:=public.erp_next_document_number(
        new.company_id,'purchase_order','PO',v_effective);
    end if;
  elsif tg_table_name='erp_commercial_workflow_documents' then
    if tg_op='INSERT' then
      if new.module='sales' then
        select effective_at into v_parent_effective
        from public.erp_sales_orders_cloud
        where company_id=new.company_id and id=new.parent_id;
      elsif new.module='purchases' then
        select effective_at into v_parent_effective
        from public.erp_purchase_orders_cloud
        where company_id=new.company_id and id=new.parent_id;
      end if;
    end if;
    new.effective_at:=coalesce(v_parent_effective,new.effective_at,new.created_at,now());
    v_effective:=new.effective_at;
    v_expected_year:=extract(year from v_effective)::int::text;
    v_key:=lower(new.module||'_'||new.document_type);
    v_prefix:=case
      when new.module='sales' and new.document_type='delivery' then 'SDN'
      when new.module='purchases' and new.document_type='receipt' then 'GRN'
      when new.module='sales' and new.document_type='invoice' then 'SINV'
      when new.module='purchases' and new.document_type='invoice' then 'PINV'
      when new.module='maintenance' and new.document_type in ('issue','delivery') then 'MIS'
      when new.module='maintenance' and new.document_type='invoice' then 'MINV'
      else upper(left(new.module,2)||left(new.document_type,2)) end;
    if new.document_number is null
       or new.document_number !~ '^[A-Z]{2,3}[0-9]{4,5}$' then
      new.document_number:=public.erp_next_document_number(
        new.company_id,v_key,v_prefix,v_effective);
    end if;
  elsif tg_table_name='erp_maintenance_orders' then
    v_effective:=coalesce(new.maintenance_date,new.created_at,now());
    v_expected_year:=extract(year from v_effective)::int::text;
    if new.order_number is null
       or new.order_number !~ '^[A-Z]{2,3}[0-9]{4,5}$' then
      new.order_number:=public.erp_next_document_number(
        new.company_id,'maintenance_order','MO',v_effective);
    end if;
    if new.stock_issue_number is not null and (
       new.stock_issue_number !~ '^[A-Z]{2,3}[0-9]{4,5}$') then
      new.stock_issue_number:=public.erp_next_document_number(
        new.company_id,'maintenance_stock_issue','MIS',v_effective);
    end if;
    if new.invoice_number is not null and (
       new.invoice_number !~ '^[A-Z]{2,3}[0-9]{4,5}$') then
      new.invoice_number:=public.erp_next_document_number(
        new.company_id,'maintenance_invoice','MINV',v_effective);
    end if;
  end if;
  return new;
end;
$$;

commit;
