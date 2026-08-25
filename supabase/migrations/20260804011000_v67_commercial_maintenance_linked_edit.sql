begin;

-- V6.7: responsive commercial logistics reversal and full linked editing.
-- Sales, purchases, and maintenance keep one atomic update path that reverses
-- generated inventory/accounting/payment links and rebuilds them to the same
-- workflow state after the edited source data is saved.

create or replace function public.erp_cancel_cloud_sales_delivery(
  p_company_id uuid,
  p_delivery_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_invoice record;
  v_allocation record;
  v_allocations jsonb;
  v_stock public.erp_warehouse_stock%rowtype;
  v_qty numeric;
  v_cost numeric;
  v_journal text;
  v_now timestamptz:=now();
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['sales.cancel','sales.update','sales.delete']
  );
  select d.* into v_doc
  from public.erp_commercial_workflow_documents as d
  where d.company_id=p_company_id
    and d.id=p_delivery_id
    and d.module='sales'
    and d.document_type='delivery'
    and not d.is_deleted
  for update;
  if not found or v_doc.status='cancelled' then return; end if;

  for v_invoice in
    select d.id
    from public.erp_commercial_workflow_documents as d
    where d.company_id=p_company_id
      and d.parent_id=v_doc.parent_id
      and d.module='sales'
      and d.document_type='invoice'
      and not d.is_deleted
      and d.status<>'cancelled'
    order by d.created_at desc,d.id desc
  loop
    perform public.erp_cancel_cloud_sales_workflow_invoice(
      p_company_id,v_invoice.id,'Reverse sales invoice before deleting delivery'
    );
  end loop;

  if v_doc.status='approved'
     and v_doc.payload ? 'inventoryPostedAt'
     and not (v_doc.payload ? 'inventoryReversedAt') then
    v_allocations:=v_doc.payload->'allocations';
    if coalesce(jsonb_typeof(v_allocations),'null')<>'array' then
      select coalesce(jsonb_agg(jsonb_build_object(
        'itemType',x.item_type,
        'itemId',x.item_id,
        'description',x.description,
        'warehouseId',v_doc.warehouse_id,
        'quantity',x.quantity
      ) order by x.id),'[]'::jsonb)
      into v_allocations
      from public.erp_sales_order_items_cloud as x
      where x.company_id=p_company_id
        and x.order_id=v_doc.parent_id
        and not x.is_deleted;
    end if;

    for v_allocation in
      select *
      from jsonb_to_recordset(v_allocations) as a(
        "itemType" text,
        "itemId" text,
        "description" text,
        "warehouseId" text,
        quantity numeric
      )
    loop
      if v_allocation."itemType"='product' then
        v_stock:=public.erp_inventory_ensure_stock(
          p_company_id,v_allocation."warehouseId",v_allocation."itemId"
        );
        v_qty:=public.erp_try_numeric(v_stock.data->>'quantity',0);
        select coalesce(
          sum(c.quantity*c.unit_cost)/nullif(sum(c.quantity),0),
          public.erp_try_numeric(v_stock.data->>'averageUnitCost',0)
        ) into v_cost
        from public.erp_inventory_fifo_consumptions as c
        where c.company_id=p_company_id
          and c.delivery_id=p_delivery_id
          and c.product_id=v_allocation."itemId";
        v_cost:=coalesce(v_cost,public.erp_try_numeric(v_stock.data->>'averageUnitCost',0));

        update public.erp_warehouse_stock as ws
           set data=ws.data||jsonb_build_object(
                 'quantity',(v_qty+v_allocation.quantity)::int,
                 'updatedAt',v_now
               ),
               updated_at=v_now,
               updated_by=auth.uid()
         where ws.company_id=p_company_id and ws.id=v_stock.id;
        perform public.erp_inventory_insert_movement(
          p_company_id,v_allocation."itemId",v_allocation."warehouseId",
          'sales_delivery_reversal',v_allocation.quantity,v_cost,
          'sales_delivery_cancel',v_doc.id::text,v_doc.document_number
        );
        perform public.erp_inventory_refresh_product(
          p_company_id,v_allocation."itemId"
        );
      else
        update public.erp_cars as c
           set data=(c.data-'salesDeliveryId'-'sales_delivery_id'-'deliveredAt'-'delivered_at'-'lastWarehouseId')
                    ||jsonb_build_object(
                      'status','قيد البيع',
                      'statusValue','pending_sale',
                      'warehouseId',v_allocation."warehouseId",
                      'warehouse_id',v_allocation."warehouseId",
                      'salesOrderId',v_doc.parent_id::text,
                      'updatedAt',v_now
                    ),
               updated_at=v_now,
               updated_by=auth.uid()
         where c.company_id=p_company_id
           and c.id=v_allocation."itemId"
           and not c.is_deleted
           and (
             coalesce(c.data->>'salesDeliveryId',c.data->>'sales_delivery_id')=v_doc.id::text
             or coalesce(c.data->>'salesOrderId',c.data->>'sales_order_id')=v_doc.parent_id::text
           );
      end if;
    end loop;

    v_journal:=nullif(v_doc.payload->>'costJournalEntryId','');
    perform public.erp_v65_soft_delete_journal(
      p_company_id,v_journal,'Reverse sales delivery cost posting'
    );
  end if;

  update public.erp_inventory_cost_layers as l
     set remaining_quantity=least(l.original_quantity,l.remaining_quantity+c.quantity),
         status='active',updated_at=v_now,updated_by=auth.uid()
    from public.erp_inventory_fifo_consumptions as c
   where c.company_id=p_company_id
     and c.delivery_id=p_delivery_id
     and c.status='active'
     and l.id=c.layer_id;
  update public.erp_inventory_fifo_consumptions
     set status='reversed',reversed_at=v_now
   where company_id=p_company_id
     and delivery_id=p_delivery_id
     and status='active';

  update public.erp_commercial_workflow_documents as d
     set status='cancelled',
         payload=d.payload||jsonb_build_object(
           'inventoryReversedAt',v_now,
           'fifoReversedAt',v_now,
           'cancelledAt',v_now,
           'linkedReversalComplete',true
         ),
         updated_at=v_now,
         updated_by=auth.uid()
   where d.company_id=p_company_id and d.id=p_delivery_id;

  perform public.erp_commercial_audit(
    p_company_id,'sales',v_doc.parent_id,v_doc.id,v_doc.document_number,
    'cancel_delivery',v_doc.status,'cancelled','linked inventory and accounting reversal'
  );
end;
$$;

create or replace function public.erp_cancel_cloud_purchase_receipt(
  p_company_id uuid,
  p_receipt_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_invoice record;
  v_allocation record;
  v_allocations jsonb;
  v_stock public.erp_warehouse_stock%rowtype;
  v_qty numeric;
  v_unit_cost numeric;
  v_now timestamptz:=now();
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['purchases.cancel','purchases.update','purchases.delete']
  );
  select d.* into v_doc
  from public.erp_commercial_workflow_documents as d
  where d.company_id=p_company_id
    and d.id=p_receipt_id
    and d.module='purchases'
    and d.document_type='receipt'
    and not d.is_deleted
  for update;
  if not found or v_doc.status='cancelled' then return; end if;

  for v_invoice in
    select d.id
    from public.erp_commercial_workflow_documents as d
    where d.company_id=p_company_id
      and d.parent_id=v_doc.parent_id
      and d.module='purchases'
      and d.document_type='invoice'
      and not d.is_deleted
      and d.status<>'cancelled'
    order by d.created_at desc,d.id desc
  loop
    perform public.erp_cancel_cloud_purchase_workflow_invoice(
      p_company_id,v_invoice.id,'Reverse purchase invoice before deleting receipt'
    );
  end loop;

  if exists(
    select 1
    from public.erp_inventory_fifo_consumptions as c
    join public.erp_inventory_cost_layers as l on l.id=c.layer_id
    where l.company_id=p_company_id
      and l.receipt_id=p_receipt_id
      and c.status='active'
  ) then
    raise exception 'purchase_receipt_has_downstream_sales';
  end if;

  if v_doc.status='approved'
     and v_doc.payload ? 'inventoryPostedAt'
     and not (v_doc.payload ? 'inventoryReversedAt') then
    v_allocations:=v_doc.payload->'allocations';
    if coalesce(jsonb_typeof(v_allocations),'null')<>'array' then
      select coalesce(jsonb_agg(jsonb_build_object(
        'itemType',x.item_type,
        'itemId',x.item_id,
        'description',x.description,
        'warehouseId',v_doc.warehouse_id,
        'quantity',x.quantity
      ) order by x.id),'[]'::jsonb)
      into v_allocations
      from public.erp_purchase_order_items_cloud as x
      where x.company_id=p_company_id
        and x.order_id=v_doc.parent_id
        and not x.is_deleted;
    end if;

    for v_allocation in
      select *
      from jsonb_to_recordset(v_allocations) as a(
        "itemType" text,
        "itemId" text,
        "description" text,
        "warehouseId" text,
        quantity numeric
      )
    loop
      if v_allocation."itemType"='product' then
        select x.unit_cost into v_unit_cost
        from public.erp_purchase_order_items_cloud as x
        where x.company_id=p_company_id
          and x.order_id=v_doc.parent_id
          and not x.is_deleted
          and x.item_type='product'
          and x.item_id=v_allocation."itemId"
        order by x.id
        limit 1;
        v_unit_cost:=coalesce(v_unit_cost,0);
        v_stock:=public.erp_inventory_ensure_stock(
          p_company_id,v_allocation."warehouseId",v_allocation."itemId"
        );
        v_qty:=public.erp_try_numeric(v_stock.data->>'quantity',0);
        if v_qty<v_allocation.quantity then
          raise exception 'purchase_receipt_stock_already_used:%',v_allocation."itemId";
        end if;
        update public.erp_warehouse_stock as ws
           set data=ws.data||jsonb_build_object(
                 'quantity',(v_qty-v_allocation.quantity)::int,
                 'updatedAt',v_now
               ),
               updated_at=v_now,
               updated_by=auth.uid()
         where ws.company_id=p_company_id and ws.id=v_stock.id;
        perform public.erp_inventory_insert_movement(
          p_company_id,v_allocation."itemId",v_allocation."warehouseId",
          'purchase_receipt_reversal',-v_allocation.quantity,v_unit_cost,
          'purchase_receipt_cancel',v_doc.id::text,v_doc.document_number
        );
        perform public.erp_inventory_refresh_product(
          p_company_id,v_allocation."itemId"
        );
      else
        if exists(
          select 1 from public.erp_cars as c
          where c.company_id=p_company_id
            and c.id=v_allocation."itemId"
            and not c.is_deleted
            and (
              lower(coalesce(c.data->>'statusValue',c.data->>'status_value',c.data->>'status',''))
                in ('sold','selling','pending_sale','مباعة','مباع','قيد البيع')
              or nullif(coalesce(c.data->>'salesOrderId',c.data->>'sales_order_id'),'') is not null
            )
        ) then
          raise exception 'purchase_receipt_vehicle_has_downstream_sale:%',v_allocation."itemId";
        end if;
        update public.erp_cars as c
           set data=(c.data-'warehouseId'-'warehouse_id'-'purchaseReceiptId'-'purchase_receipt_id')
                    ||jsonb_build_object(
                      'status','قيد الشراء',
                      'statusValue','pending_purchase',
                      'purchaseOrderId',v_doc.parent_id::text,
                      'updatedAt',v_now
                    ),
               updated_at=v_now,
               updated_by=auth.uid()
         where c.company_id=p_company_id
           and c.id=v_allocation."itemId"
           and not c.is_deleted;
      end if;
    end loop;
  end if;

  update public.erp_inventory_cost_layers
     set remaining_quantity=0,
         status='reversed',
         updated_at=v_now,
         updated_by=auth.uid()
   where company_id=p_company_id
     and receipt_id=p_receipt_id
     and status<>'reversed';

  update public.erp_commercial_workflow_documents as d
     set status='cancelled',
         payload=d.payload||jsonb_build_object(
           'inventoryReversedAt',v_now,
           'cancelledAt',v_now,
           'linkedReversalComplete',true
         ),
         updated_at=v_now,
         updated_by=auth.uid()
   where d.company_id=p_company_id and d.id=p_receipt_id;

  perform public.erp_commercial_audit(
    p_company_id,'purchases',v_doc.parent_id,v_doc.id,v_doc.document_number,
    'cancel_receipt',v_doc.status,'cancelled','linked inventory reversal'
  );
end;
$$;

create or replace function public.erp_restore_commercial_order_links(
  p_company_id uuid,
  p_order_id uuid,
  p_module text,
  p_snapshot jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_logistics jsonb:=p_snapshot->'logistics';
  v_invoice jsonb:=p_snapshot->'invoice';
  v_payments jsonb:=coalesce(p_snapshot->'payments','[]'::jsonb);
  v_allocations jsonb;
  v_logistics_id uuid;
  v_invoice_id uuid;
  v_order_status text:=coalesce(p_snapshot->>'orderStatus','draft');
  v_logistics_status text;
  v_invoice_status text;
begin
  if p_module not in ('sales','purchases') then
    raise exception 'invalid workflow module';
  end if;

  if v_order_status='approved' or v_logistics is not null or v_invoice is not null then
    if p_module='sales' then
      perform public.erp_approve_cloud_sales_order(p_company_id,p_order_id);
    else
      perform public.erp_approve_cloud_purchase_order(p_company_id,p_order_id);
    end if;
  end if;

  if v_logistics is not null then
    v_allocations:=coalesce(v_logistics->'allocations','[]'::jsonb);
    v_logistics_status:=coalesce(v_logistics->>'status','draft');
    if jsonb_typeof(v_allocations)='array' and jsonb_array_length(v_allocations)>0 then
      if p_module='sales' then
        v_logistics_id:=public.erp_create_cloud_sales_delivery_multi(
          p_company_id,p_order_id,v_allocations,v_logistics->>'notes'
        );
      else
        v_logistics_id:=public.erp_create_cloud_purchase_receipt_multi(
          p_company_id,p_order_id,v_allocations,v_logistics->>'notes'
        );
      end if;
    else
      if nullif(v_logistics->>'warehouseId','') is null then
        raise exception 'commercial_logistics_warehouse_missing';
      end if;
      if p_module='sales' then
        v_logistics_id:=public.erp_create_cloud_sales_delivery(
          p_company_id,p_order_id,v_logistics->>'warehouseId',v_logistics->>'notes'
        );
      else
        v_logistics_id:=public.erp_create_cloud_purchase_receipt(
          p_company_id,p_order_id,v_logistics->>'warehouseId',v_logistics->>'notes'
        );
      end if;
    end if;

    if v_logistics_status='approved' then
      if p_module='sales' then
        perform public.erp_approve_cloud_sales_delivery(p_company_id,v_logistics_id);
      else
        perform public.erp_approve_cloud_purchase_receipt(p_company_id,v_logistics_id);
      end if;
    end if;
  end if;

  if v_invoice is not null then
    v_invoice_status:=coalesce(v_invoice->>'status','draft');
    if p_module='sales' then
      v_invoice_id:=public.erp_create_cloud_sales_workflow_invoice(p_company_id,p_order_id);
    else
      v_invoice_id:=public.erp_create_cloud_purchase_workflow_invoice(p_company_id,p_order_id);
    end if;
    if v_invoice_status='approved' then
      if p_module='sales' then
        perform public.erp_approve_cloud_sales_workflow_invoice(p_company_id,v_invoice_id);
      else
        perform public.erp_approve_cloud_purchase_workflow_invoice(p_company_id,v_invoice_id);
      end if;
    end if;

    if jsonb_typeof(v_payments)='array' and jsonb_array_length(v_payments)>0 then
      if v_invoice_status<>'approved' then
        raise exception 'commercial_payments_require_approved_invoice';
      end if;
      if p_module='sales' then
        perform public.erp_pay_cloud_sales_workflow_invoice_batch(
          p_company_id,v_invoice_id,v_payments
        );
      else
        perform public.erp_pay_cloud_purchase_workflow_invoice_batch(
          p_company_id,v_invoice_id,v_payments
        );
      end if;
    end if;
  end if;

  return jsonb_build_object(
    'orderId',p_order_id,
    'logisticsId',v_logistics_id,
    'invoiceId',v_invoice_id,
    'restoredOrderStatus',v_order_status,
    'restoredLogisticsStatus',v_logistics_status,
    'restoredInvoiceStatus',v_invoice_status,
    'restoredPaymentCount',case
      when jsonb_typeof(v_payments)='array' then jsonb_array_length(v_payments)
      else 0 end
  );
end;
$$;

create or replace function public.erp_update_cloud_sales_order_with_links(
  p_company_id uuid,
  p_order_id uuid,
  p_customer_id text,
  p_currency text,
  p_exchange_rate numeric,
  p_discount numeric,
  p_items jsonb,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_snapshot jsonb;
  v_result jsonb;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['sales.update']
  );
  v_snapshot:=public.erp_prepare_commercial_order_change(
    p_company_id,p_order_id,'sales','Edit sales order and rebuild every linked document'
  );
  perform public.erp_update_cloud_sales_order(
    p_company_id,p_order_id,p_customer_id,p_currency,p_exchange_rate,p_discount,p_items,p_notes
  );
  v_result:=public.erp_restore_commercial_order_links(
    p_company_id,p_order_id,'sales',v_snapshot
  );
  update public.erp_commercial_workflow_documents as d
     set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid(),
         payload=d.payload||jsonb_build_object('supersededByLinkedEdit',true,'supersededAt',now())
   where d.company_id=p_company_id
     and d.parent_id=p_order_id
     and d.module='sales'
     and d.id::text in (
       coalesce(v_snapshot#>>'{logistics,id}',''),
       coalesce(v_snapshot#>>'{invoice,id}','')
     )
     and not d.is_deleted;
  perform public.erp_commercial_audit(
    p_company_id,'sales',p_order_id,null,null,'edit_order_with_links',
    v_snapshot->>'orderStatus',v_snapshot->>'orderStatus','Atomic linked edit completed'
  );
  return v_result||jsonb_build_object('snapshot',v_snapshot);
end;
$$;

create or replace function public.erp_update_cloud_purchase_order_with_links(
  p_company_id uuid,
  p_order_id uuid,
  p_supplier_id text,
  p_currency text,
  p_exchange_rate numeric,
  p_discount numeric,
  p_items jsonb,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_snapshot jsonb;
  v_result jsonb;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['purchases.update']
  );
  v_snapshot:=public.erp_prepare_commercial_order_change(
    p_company_id,p_order_id,'purchases','Edit purchase order and rebuild every linked document'
  );
  perform public.erp_update_cloud_purchase_order(
    p_company_id,p_order_id,p_supplier_id,p_currency,p_exchange_rate,p_discount,p_items,p_notes
  );
  v_result:=public.erp_restore_commercial_order_links(
    p_company_id,p_order_id,'purchases',v_snapshot
  );
  update public.erp_commercial_workflow_documents as d
     set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid(),
         payload=d.payload||jsonb_build_object('supersededByLinkedEdit',true,'supersededAt',now())
   where d.company_id=p_company_id
     and d.parent_id=p_order_id
     and d.module='purchases'
     and d.id::text in (
       coalesce(v_snapshot#>>'{logistics,id}',''),
       coalesce(v_snapshot#>>'{invoice,id}','')
     )
     and not d.is_deleted;
  perform public.erp_commercial_audit(
    p_company_id,'purchases',p_order_id,null,null,'edit_order_with_links',
    v_snapshot->>'orderStatus',v_snapshot->>'orderStatus','Atomic linked edit completed'
  );
  return v_result||jsonb_build_object('snapshot',v_snapshot);
end;
$$;

create or replace function public.erp_v67_prepare_maintenance_linked_edit(
  p_company_id uuid,
  p_order_id uuid,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_payments jsonb;
  v_cash record;
  v_now timestamptz:=now();
begin
  select o.* into v_order
  from public.erp_maintenance_orders as o
  where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
  for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if v_order.workflow_stage='cancelled' then
    raise exception 'maintenance_cancelled_order_not_editable';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'amount',p.amount,
    'currencyCode',p.currency_code,
    'exchangeRate',p.exchange_rate,
    'amountInOrderCurrency',p.amount_in_order_currency,
    'notes',p.notes,
    'createdAt',p.created_at
  ) order by p.created_at,p.id),'[]'::jsonb)
  into v_payments
  from public.erp_maintenance_payments as p
  where p.company_id=p_company_id
    and p.maintenance_order_id=p_order_id
    and not p.is_deleted;

  for v_cash in
    select ct.id,coalesce(
      nullif(ct.data->>'journalEntryId',''),nullif(ct.data->>'journal_entry_id',''),
      nullif(ct.data->>'entryId',''),nullif(ct.data->>'entry_id','')
    ) as journal_id
    from public.erp_cash_transactions as ct
    where ct.company_id=p_company_id
      and not ct.is_deleted
      and coalesce(
        ct.data->>'maintenanceOrderId',ct.data->>'maintenance_order_id',
        ct.data->>'referenceId',ct.data->>'reference_id'
      )=p_order_id::text
    for update
  loop
    perform public.erp_v65_soft_delete_journal(
      p_company_id,v_cash.journal_id,coalesce(p_reason,'Maintenance linked edit')
    );
    update public.erp_cash_transactions as ct
       set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
           data=ct.data||jsonb_build_object('deletedAt',v_now,'deleteReason',p_reason)
     where ct.company_id=p_company_id and ct.id=v_cash.id and not ct.is_deleted;
  end loop;

  update public.erp_maintenance_payments
     set is_deleted=true,deleted_at=v_now
   where company_id=p_company_id
     and maintenance_order_id=p_order_id
     and not is_deleted;

  perform public.erp_v66_reverse_maintenance_stock(
    p_company_id,p_order_id,coalesce(p_reason,'Maintenance linked edit')
  );

  update public.erp_maintenance_orders
     set workflow_stage='order_draft',
         status='draft',
         paid_amount=0,
         stock_issue_number=null,
         invoice_number=null,
         cancelled_at=null,
         cancel_reason=null,
         updated_at=v_now,
         updated_by=auth.uid()
   where company_id=p_company_id and id=p_order_id;

  return jsonb_build_object(
    'workflowStage',v_order.workflow_stage,
    'status',v_order.status,
    'paidAmount',v_order.paid_amount,
    'payments',v_payments,
    'stockIssueNumber',v_order.stock_issue_number,
    'invoiceNumber',v_order.invoice_number
  );
end;
$$;

create or replace function public.erp_v67_advance_maintenance_internal(
  p_company_id uuid,
  p_order_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_part record;
  v_stock public.erp_warehouse_stock%rowtype;
  v_product_id text;
  v_warehouse_id text;
  v_now timestamptz:=now();
begin
  select o.* into v_order
  from public.erp_maintenance_orders as o
  where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
  for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;

  if v_order.workflow_stage='order_draft' then
    update public.erp_maintenance_orders
       set workflow_stage='order_approved',status='approved',updated_at=v_now,updated_by=auth.uid()
     where company_id=p_company_id and id=p_order_id;
  elsif v_order.workflow_stage='order_approved' then
    update public.erp_maintenance_orders
       set workflow_stage='stock_issue_draft',stock_issue_number='PENDING',updated_at=v_now,updated_by=auth.uid()
     where company_id=p_company_id and id=p_order_id;
  elsif v_order.workflow_stage='stock_issue_draft' then
    for v_part in
      select p.*
      from public.erp_maintenance_parts as p
      where p.company_id=p_company_id
        and p.maintenance_order_id=p_order_id
        and not p.is_deleted
        and p.line_type<>'service'
    loop
      v_product_id:=coalesce(v_part.source_product_id,v_part.product_id::text);
      v_warehouse_id:=coalesce(
        v_part.source_warehouse_id,v_part.warehouse_id::text,
        v_order.source_warehouse_id,v_order.warehouse_id::text
      );
      v_stock:=public.erp_inventory_ensure_stock(p_company_id,v_warehouse_id,v_product_id);
      if public.erp_try_numeric(v_stock.data->>'quantity',0)-
         public.erp_try_numeric(v_stock.data->>'reservedQuantity',0)<v_part.quantity then
        raise exception 'maintenance_insufficient_stock:%',v_part.product_name;
      end if;
      update public.erp_warehouse_stock as ws
         set data=ws.data||jsonb_build_object(
               'quantity',public.erp_try_numeric(ws.data->>'quantity',0)-v_part.quantity,
               'updatedAt',v_now
             ),
             updated_at=v_now,
             updated_by=auth.uid()
       where ws.company_id=p_company_id and ws.id=v_stock.id;
      perform public.erp_inventory_insert_movement(
        p_company_id,v_product_id,v_warehouse_id,'maintenance_out',-v_part.quantity,
        v_part.unit_cost,'maintenance_order',p_order_id::text,
        'Maintenance issue '||v_order.order_number
      );
    end loop;
    perform public.erp_phase3_refresh_maintenance_products(p_company_id,p_order_id);
    perform public.erp_phase3_post_maintenance_issue(p_company_id,p_order_id);
    update public.erp_maintenance_orders
       set workflow_stage='stock_issue_approved',
           stock_issue_number=public.erp_next_document_number(
             p_company_id,'maintenance_stock_issue','MSI',v_order.maintenance_date
           ),
           updated_at=v_now,
           updated_by=auth.uid()
     where company_id=p_company_id and id=p_order_id;
  elsif v_order.workflow_stage='stock_issue_approved' then
    update public.erp_maintenance_orders
       set workflow_stage=case when pricing_type='paid' then 'invoice_draft' else 'completed' end,
           status=case when pricing_type='paid' then status else 'completed' end,
           invoice_number=case when pricing_type='paid' then 'PENDING' else invoice_number end,
           updated_at=v_now,
           updated_by=auth.uid()
     where company_id=p_company_id and id=p_order_id;
  elsif v_order.workflow_stage='invoice_draft' then
    update public.erp_maintenance_orders
       set workflow_stage='invoice_approved',
           invoice_number=public.erp_next_document_number(
             p_company_id,'maintenance_invoice','MINV',v_order.maintenance_date
           ),
           updated_at=v_now,
           updated_by=auth.uid()
     where company_id=p_company_id and id=p_order_id;
  else
    raise exception 'maintenance_no_next_stage';
  end if;
end;
$$;

create or replace function public.erp_update_cloud_maintenance_draft(
  p_company_id uuid,
  p_order_id uuid,
  p_warehouse_id text,
  p_pricing_type text,
  p_labor_cost numeric,
  p_sale_price numeric,
  p_currency_code text,
  p_exchange_rate numeric,
  p_notes text,
  p_parts jsonb,
  p_maintenance_expense_account_id text default null,
  p_effective_at timestamptz default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_snapshot jsonb;
  v_target_stage text;
  v_current_stage text;
  v_payment jsonb;
  v_guard integer:=0;
  v_paid numeric:=0;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['maintenance.update']
  );
  v_snapshot:=public.erp_v67_prepare_maintenance_linked_edit(
    p_company_id,p_order_id,'Edit maintenance order and rebuild all generated links'
  );
  v_target_stage:=coalesce(v_snapshot->>'workflowStage','order_draft');

  perform public.erp_update_cloud_maintenance_draft_pre_v65(
    p_company_id,p_order_id,p_warehouse_id,p_pricing_type,p_labor_cost,
    p_sale_price,p_currency_code,p_exchange_rate,p_notes,p_parts,
    null,p_effective_at
  );
  update public.erp_maintenance_orders
     set maintenance_expense_account_id=nullif(btrim(p_maintenance_expense_account_id),''),
         updated_at=now(),updated_by=auth.uid()
   where company_id=p_company_id and id=p_order_id and not is_deleted;

  while v_guard<8 loop
    select workflow_stage into v_current_stage
    from public.erp_maintenance_orders
    where company_id=p_company_id and id=p_order_id and not is_deleted;
    exit when v_current_stage=v_target_stage;
    exit when v_target_stage='paid' and v_current_stage='invoice_approved';
    exit when v_target_stage='completed' and v_current_stage='completed';
    perform public.erp_v67_advance_maintenance_internal(p_company_id,p_order_id);
    v_guard:=v_guard+1;
  end loop;

  if v_target_stage='paid' then
    for v_payment in
      select value from jsonb_array_elements(coalesce(v_snapshot->'payments','[]'::jsonb))
    loop
      insert into public.erp_maintenance_payments(
        company_id,maintenance_order_id,amount,currency_code,exchange_rate,
        amount_in_order_currency,notes,created_at
      ) values(
        p_company_id,p_order_id,
        public.erp_try_numeric(v_payment->>'amount',0),
        coalesce(nullif(v_payment->>'currencyCode',''),upper(p_currency_code)),
        greatest(public.erp_try_numeric(v_payment->>'exchangeRate',p_exchange_rate),0.000001),
        public.erp_try_numeric(v_payment->>'amountInOrderCurrency',0),
        nullif(v_payment->>'notes',''),
        coalesce(public.erp_try_timestamptz(v_payment->>'createdAt',now()),now())
      );
      v_paid:=v_paid+public.erp_try_numeric(v_payment->>'amountInOrderCurrency',0);
    end loop;
    update public.erp_maintenance_orders
       set paid_amount=least(v_paid,sale_price),
           workflow_stage=case when v_paid+0.001>=sale_price then 'paid' else 'invoice_approved' end,
           status=case when v_paid+0.001>=sale_price then 'completed' else 'approved' end,
           updated_at=now(),updated_by=auth.uid()
     where company_id=p_company_id and id=p_order_id;
  end if;
end;
$$;

revoke all on function public.erp_cancel_cloud_sales_delivery(uuid,uuid) from public,anon;
revoke all on function public.erp_cancel_cloud_purchase_receipt(uuid,uuid) from public,anon;
revoke all on function public.erp_restore_commercial_order_links(uuid,uuid,text,jsonb) from public,anon;
revoke all on function public.erp_update_cloud_sales_order_with_links(uuid,uuid,text,text,numeric,numeric,jsonb,text) from public,anon;
revoke all on function public.erp_update_cloud_purchase_order_with_links(uuid,uuid,text,text,numeric,numeric,jsonb,text) from public,anon;
revoke all on function public.erp_v67_prepare_maintenance_linked_edit(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.erp_v67_advance_maintenance_internal(uuid,uuid) from public,anon,authenticated;
revoke all on function public.erp_update_cloud_maintenance_draft(uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) from public,anon;
grant execute on function public.erp_cancel_cloud_sales_delivery(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_cancel_cloud_purchase_receipt(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_restore_commercial_order_links(uuid,uuid,text,jsonb) to authenticated,service_role;
grant execute on function public.erp_update_cloud_sales_order_with_links(uuid,uuid,text,text,numeric,numeric,jsonb,text) to authenticated,service_role;
grant execute on function public.erp_update_cloud_purchase_order_with_links(uuid,uuid,text,text,numeric,numeric,jsonb,text) to authenticated,service_role;
grant execute on function public.erp_update_cloud_maintenance_draft(uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) to authenticated,service_role;

commit;
