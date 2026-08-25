-- V6.8.1 forward repair:
-- erp_inventory_fifo_consumptions stores item identifiers in item_type/item_id.
-- The already-applied V6.8 sales-delivery reversal referenced a non-existent
-- product_id column, so redefine only the affected function forward in history.

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
          and c.item_type='product'
          and c.item_id=v_allocation."itemId";
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
