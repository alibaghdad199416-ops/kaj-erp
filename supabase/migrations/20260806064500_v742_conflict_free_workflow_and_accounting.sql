-- Quality Line ERP 18.9.12 / V7.4.2
-- Conflict-free final workflow: resilient invoicing, invoice-owned accounting
-- nomenclature, and projection compatibility for historical logistics statuses.
begin;

-- Normalize historical approved logistics and preserve future compatibility.
update public.erp_commercial_workflow_documents
set status='approved', payload=coalesce(payload,'{}'::jsonb)||jsonb_build_object(
  'accountingOwner','invoice','logisticsQuantityOnly',true,
  'inventoryPostedAt',coalesce(payload->>'inventoryPostedAt',payload->>'postedAt',payload->>'approvedAt',now()::text)
), updated_at=now()
where document_type in ('delivery','receipt','maintenance_issue')
  and lower(coalesce(status,'')) in ('posted','completed','confirmed')
  and not is_deleted;

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
    and d.document_type=v_type
    and lower(coalesce(d.status,'')) in ('approved','posted','completed','confirmed')
    and not d.is_deleted
    and (d.payload ? 'inventoryPostedAt' or d.payload ? 'postedAt' or d.payload ? 'approvedAt')
  order by d.updated_at desc limit 1;
  if v_result is null then raise exception 'approved_inventory_document_required'; end if;
  perform public.erp_validate_commercial_warehouse_allocations(
    p_company_id,p_order_id,p_module,v_result->'allocations',false);
  return v_result;
end;
$$;

create or replace function public.erp_list_cloud_sales_workflow_orders(p_company_id uuid)
returns setof jsonb
language sql
security definer
set search_path=public
as $$
  select jsonb_build_object(
    'id',o.id::text,
    'documentType','salesOrder','documentTitle','أمر بيع',
    'orderNumber',o.order_number,
    'customerId',o.customer_id,
    'customerName',coalesce(c.data->>'name',''),
    'opportunityId',o.opportunity_id,
    'status',o.status,
    'currency',upper(o.currency),
    'exchangeRate',o.exchange_rate,
    'subtotal',o.subtotal,'discount',o.discount,'total',o.total,
    'notes',o.notes,'createdAt',o.created_at::text,'updatedAt',o.updated_at::text,
    'deliveryId',d.id::text,
    'deliveryNumber',d.document_number,
    'deliveryTitle','إذن تجهيز مخزني للبيع',
    'deliveryStatus',d.status,
    'deliveryAccountingOwner',coalesce(d.payload->>'accountingOwner','invoice'),
    'deliveryValuationPendingInvoice',public.erp_try_boolean(d.payload->>'valuationPendingInvoice',true),
    'invoiceId',i.id::text,
    'invoiceNumber',i.document_number,
    'invoiceTitle','فاتورة بيع',
    'invoiceStatus',i.status,
    'invoicePaid',public.erp_try_numeric(i.payload->>'paidAmount',0),
    'invoiceRemaining',public.erp_try_numeric(i.payload->>'remainingAmount',public.erp_try_numeric(i.payload->>'totalAmount',0)),
    'paymentStatus',coalesce(i.payload->>'paymentStatus',case
      when i.id is null then 'not_invoiced'
      when public.erp_try_numeric(i.payload->>'remainingAmount',public.erp_try_numeric(i.payload->>'totalAmount',0))<=0 then 'paid'
      else 'unpaid' end),
    'journalEntryId',i.payload->>'journalEntryId',
    'journalEntryNumber',j.data->>'entryNumber',
    'costJournalEntries',coalesce(i.payload->'costJournalEntries','[]'::jsonb),
    'accountingOwner',case when i.id is null then null else coalesce(i.payload->>'accountingOwner','invoice') end,
    'accountingReference',coalesce(i.payload->>'journalEntryId',i.id::text,o.id::text),
    'canCreateDelivery',lower(coalesce(o.status,''))='approved' and d.id is null,
    'canApproveDelivery',lower(coalesce(d.status,''))='draft',
    'canCancelDelivery',lower(coalesce(d.status,'')) in ('draft','approved','posted','completed','confirmed'),
    'canCreateInvoice',lower(coalesce(o.status,''))='approved' and lower(coalesce(d.status,'')) in ('approved','posted','completed','confirmed') and i.id is null,
    'canApproveInvoice',lower(coalesce(i.status,''))='draft',
    'canRecordPayment',lower(coalesce(i.status,''))='approved'
      and public.erp_try_numeric(i.payload->>'remainingAmount',public.erp_try_numeric(i.payload->>'totalAmount',0))>0.001,
    'canCancelInvoice',lower(coalesce(i.status,'')) in ('draft','approved')
  )
  from public.erp_sales_orders_cloud o
  left join public.erp_customers c
    on c.id=o.customer_id and c.company_id=o.company_id and not c.is_deleted
  left join lateral (
    select x.* from public.erp_commercial_workflow_documents x
    where x.company_id=o.company_id and x.module='sales'
      and x.document_type='delivery' and x.parent_id=o.id and not x.is_deleted
      and lower(coalesce(x.status,'')) not in ('cancelled','canceled','voided')
    order by x.updated_at desc,x.created_at desc,x.id desc limit 1
  ) d on true
  left join lateral (
    select x.* from public.erp_commercial_workflow_documents x
    where x.company_id=o.company_id and x.module='sales'
      and x.document_type='invoice' and x.parent_id=o.id and not x.is_deleted
      and lower(coalesce(x.status,'')) not in ('cancelled','canceled','voided')
    order by x.updated_at desc,x.created_at desc,x.id desc limit 1
  ) i on true
  left join lateral (
    select je.* from public.erp_journal_entries je
    where je.company_id=o.company_id and not je.is_deleted
      and je.id=i.payload->>'journalEntryId'
    limit 1
  ) j on true
  where o.company_id=p_company_id and not o.is_deleted
    and public.erp_is_company_member(p_company_id)
  order by o.created_at desc,o.id desc;
$$;

create or replace function public.erp_list_cloud_purchase_workflow_orders(p_company_id uuid)
returns setof jsonb
language sql
security definer
set search_path=public
as $$
  select jsonb_build_object(
    'id',o.id::text,
    'documentType','purchaseOrder','documentTitle','أمر شراء',
    'orderNumber',o.order_number,
    'supplierId',o.supplier_id,
    'supplierName',coalesce(s.data->>'name',''),
    'status',o.status,
    'currency',upper(o.currency),
    'exchangeRate',o.exchange_rate,
    'subtotal',o.subtotal,'discount',o.discount,'total',o.total,
    'notes',o.notes,'createdAt',o.created_at::text,'updatedAt',o.updated_at::text,
    'receiptId',r.id::text,
    'receiptNumber',r.document_number,
    'receiptTitle','إشعار استلام مخزني للشراء',
    'receiptStatus',r.status,
    'receiptAccountingOwner',coalesce(r.payload->>'accountingOwner','invoice'),
    'receiptValuationPendingInvoice',public.erp_try_boolean(r.payload->>'valuationPendingInvoice',true),
    'invoiceId',i.id::text,
    'invoiceNumber',i.document_number,
    'invoiceTitle','فاتورة شراء',
    'invoiceStatus',i.status,
    'invoicePaid',public.erp_try_numeric(i.payload->>'paidAmount',0),
    'invoiceRemaining',public.erp_try_numeric(i.payload->>'remainingAmount',public.erp_try_numeric(i.payload->>'totalAmount',0)),
    'paymentStatus',coalesce(i.payload->>'paymentStatus',case
      when i.id is null then 'not_invoiced'
      when public.erp_try_numeric(i.payload->>'remainingAmount',public.erp_try_numeric(i.payload->>'totalAmount',0))<=0 then 'paid'
      else 'unpaid' end),
    'journalEntryId',i.payload->>'journalEntryId',
    'journalEntryNumber',j.data->>'entryNumber',
    'costJournalEntries',coalesce(i.payload->'costJournalEntries','[]'::jsonb),
    'accountingOwner',case when i.id is null then null else coalesce(i.payload->>'accountingOwner','invoice') end,
    'accountingReference',coalesce(i.payload->>'journalEntryId',i.id::text,o.id::text),
    'canCreateReceipt',lower(coalesce(o.status,''))='approved' and r.id is null,
    'canApproveReceipt',lower(coalesce(r.status,''))='draft',
    'canCancelReceipt',lower(coalesce(r.status,'')) in ('draft','approved','posted','completed','confirmed'),
    'canCreateInvoice',lower(coalesce(o.status,''))='approved' and lower(coalesce(r.status,'')) in ('approved','posted','completed','confirmed') and i.id is null,
    'canApproveInvoice',lower(coalesce(i.status,''))='draft',
    'canRecordPayment',lower(coalesce(i.status,''))='approved'
      and public.erp_try_numeric(i.payload->>'remainingAmount',public.erp_try_numeric(i.payload->>'totalAmount',0))>0.001,
    'canCancelInvoice',lower(coalesce(i.status,'')) in ('draft','approved')
  )
  from public.erp_purchase_orders_cloud o
  left join public.erp_suppliers s
    on s.id=o.supplier_id and s.company_id=o.company_id and not s.is_deleted
  left join lateral (
    select x.* from public.erp_commercial_workflow_documents x
    where x.company_id=o.company_id and x.module='purchases'
      and x.document_type='receipt' and x.parent_id=o.id and not x.is_deleted
      and lower(coalesce(x.status,'')) not in ('cancelled','canceled','voided')
    order by x.updated_at desc,x.created_at desc,x.id desc limit 1
  ) r on true
  left join lateral (
    select x.* from public.erp_commercial_workflow_documents x
    where x.company_id=o.company_id and x.module='purchases'
      and x.document_type='invoice' and x.parent_id=o.id and not x.is_deleted
      and lower(coalesce(x.status,'')) not in ('cancelled','canceled','voided')
    order by x.updated_at desc,x.created_at desc,x.id desc limit 1
  ) i on true
  left join lateral (
    select je.* from public.erp_journal_entries je
    where je.company_id=o.company_id and not je.is_deleted
      and je.id=i.payload->>'journalEntryId'
    limit 1
  ) j on true
  where o.company_id=p_company_id and not o.is_deleted
    and public.erp_is_company_member(p_company_id)
  order by o.created_at desc,o.id desc;
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
    -- posted separately in every item's configured cost currency.
    v_lines:=jsonb_build_array(jsonb_build_object(
      'accountId',v_clearing_account,'debit',v_total,'credit',0,
      'description','مطابقة مخزون فاتورة الشراء'));

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
            'description','إدخال مخزون شراء '||r.description,'itemType',r.item_type,
            'itemId',r.item_id,'quantity',r.quantity,'unitCost',v_adjusted_unit_cost),
          jsonb_build_object(
            'accountId',v_clearing_account,'debit',0,'credit',v_converted_amount,
            'description','مطابقة مخزون شراء '||r.description,'itemType',r.item_type,
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
        p_company_id,'purchase_invoice_inventory_'||lower(e.key),p_invoice_id::text,
        public.erp_next_document_number(
          p_company_id,'purchase_inventory_journal_'||lower(e.key),'PII-'||e.key,v_effective),
        'قيد مخزون فاتورة الشراء '||d.document_number,e.key,e.value,v_effective);
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
    'approve_invoice',d.status,'approved','invoice-owned accounting posted from configured item accounts');
end;
$$;

commit;
