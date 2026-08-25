-- Quality Line ERP 18.9.2 / V7.3.2
-- Forward repair for orphaned purchase receipts, vehicle warehouse/state replay,
-- and inventory-product deletion after returning to the opening state.
begin;

-- ---------------------------------------------------------------------------
-- Recompute a vehicle's authoritative operational state from active documents.
-- ---------------------------------------------------------------------------
create or replace function public.erp_v732_refresh_car_state(
  p_company_id uuid,
  p_car_id text,
  p_fallback_warehouse text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_car public.erp_cars%rowtype;
  v_latest_transfer_warehouse text;
  v_purchase_order_id uuid;
  v_purchase_receipt_id uuid;
  v_purchase_warehouse text;
  v_sales_order_id uuid;
  v_sales_delivery_id uuid;
  v_sales_invoice_id uuid;
  v_legacy_sale_id text;
  v_status_value text;
  v_status_label text;
  v_warehouse text;
  v_last_warehouse text;
  v_now timestamptz:=clock_timestamp();
begin
  select c.* into v_car
  from public.erp_cars as c
  where c.company_id=p_company_id
    and c.id=p_car_id
    and not c.is_deleted
  for update;

  if not found then
    return jsonb_build_object(
      'carId',p_car_id,
      'carExists',false,
      'linksRefreshed',true
    );
  end if;

  select coalesce(t.data->>'toWarehouseId',t.data->>'to_warehouse_id')
  into v_latest_transfer_warehouse
  from public.erp_car_warehouse_transfers as t
  where t.company_id=p_company_id
    and not t.is_deleted
    and coalesce(t.data->>'carId',t.data->>'car_id')=p_car_id
  order by public.erp_try_timestamptz(
    coalesce(t.data->>'transferDate',t.data->>'transfer_date'),t.created_at
  ) desc,t.created_at desc,t.id desc
  limit 1;

  select d.id,d.parent_id,coalesce(
    nullif(a.warehouse_id,''),nullif(d.warehouse_id,''),p_fallback_warehouse
  )
  into v_purchase_receipt_id,v_purchase_order_id,v_purchase_warehouse
  from public.erp_purchase_order_items_cloud as i
  join public.erp_commercial_workflow_documents as d
    on d.company_id=i.company_id
   and d.parent_id=i.order_id
   and d.module='purchases'
   and d.document_type='receipt'
   and not d.is_deleted
   and d.status='approved'
  left join lateral (
    select coalesce(
      x->>'warehouseId',x->>'warehouse_id'
    ) as warehouse_id
    from jsonb_array_elements(
      case
        when jsonb_typeof(d.payload->'allocations')='array'
          then d.payload->'allocations'
        else '[]'::jsonb
      end
    ) as x
    where coalesce(x->>'itemId',x->>'item_id')=p_car_id
    limit 1
  ) as a on true
  where i.company_id=p_company_id
    and i.item_type='car'
    and i.item_id=p_car_id
    and not i.is_deleted
  order by coalesce(d.effective_at,d.updated_at,d.created_at) desc,d.id desc
  limit 1;

  select d.id,d.parent_id
  into v_sales_delivery_id,v_sales_order_id
  from public.erp_sales_order_items_cloud as i
  join public.erp_commercial_workflow_documents as d
    on d.company_id=i.company_id
   and d.parent_id=i.order_id
   and d.module='sales'
   and d.document_type='delivery'
   and not d.is_deleted
   and d.status='approved'
  where i.company_id=p_company_id
    and i.item_type='car'
    and i.item_id=p_car_id
    and not i.is_deleted
  order by coalesce(d.effective_at,d.updated_at,d.created_at) desc,d.id desc
  limit 1;

  select d.id,d.parent_id
  into v_sales_invoice_id,v_sales_order_id
  from public.erp_sales_order_items_cloud as i
  join public.erp_commercial_workflow_documents as d
    on d.company_id=i.company_id
   and d.parent_id=i.order_id
   and d.module='sales'
   and d.document_type='invoice'
   and not d.is_deleted
   and d.status in ('approved','paid','completed')
  where i.company_id=p_company_id
    and i.item_type='car'
    and i.item_id=p_car_id
    and not i.is_deleted
  order by coalesce(d.effective_at,d.updated_at,d.created_at) desc,d.id desc
  limit 1;

  if v_sales_order_id is null then
    select o.id into v_sales_order_id
    from public.erp_sales_order_items_cloud as i
    join public.erp_sales_orders_cloud as o
      on o.company_id=i.company_id and o.id=i.order_id
    where i.company_id=p_company_id
      and i.item_type='car'
      and i.item_id=p_car_id
      and not i.is_deleted
      and not o.is_deleted
      and o.status not in ('cancelled','reversed','deleted')
    order by o.updated_at desc,o.created_at desc,o.id desc
    limit 1;
  end if;

  if v_purchase_order_id is null then
    select o.id into v_purchase_order_id
    from public.erp_purchase_order_items_cloud as i
    join public.erp_purchase_orders_cloud as o
      on o.company_id=i.company_id and o.id=i.order_id
    where i.company_id=p_company_id
      and i.item_type='car'
      and i.item_id=p_car_id
      and not i.is_deleted
      and not o.is_deleted
      and o.status not in ('cancelled','reversed','deleted')
    order by o.updated_at desc,o.created_at desc,o.id desc
    limit 1;
  end if;

  select s.id into v_legacy_sale_id
  from public.erp_sales as s
  where s.company_id=p_company_id
    and not s.is_deleted
    and coalesce(s.data->>'carId',s.data->>'car_id')=p_car_id
  order by s.updated_at desc,s.created_at desc,s.id desc
  limit 1;

  v_last_warehouse:=coalesce(
    nullif(v_latest_transfer_warehouse,''),
    nullif(v_purchase_warehouse,''),
    nullif(p_fallback_warehouse,''),
    nullif(coalesce(v_car.data->>'warehouseId',v_car.data->>'warehouse_id'),'')
  );

  if v_sales_invoice_id is not null or v_legacy_sale_id is not null then
    v_status_value:='sold';
    v_status_label:='مباعة';
    v_warehouse:=null;
  elsif v_sales_delivery_id is not null then
    v_status_value:='pending_sale';
    v_status_label:='قيد البيع';
    v_warehouse:=null;
  elsif v_sales_order_id is not null then
    v_status_value:='pending_sale';
    v_status_label:='قيد البيع';
    v_warehouse:=v_last_warehouse;
  elsif v_purchase_receipt_id is not null then
    v_status_value:='available';
    v_status_label:='متوفرة';
    v_warehouse:=coalesce(
      nullif(v_latest_transfer_warehouse,''),
      nullif(v_purchase_warehouse,''),
      nullif(p_fallback_warehouse,'')
    );
  elsif v_purchase_order_id is not null then
    v_status_value:='pending_purchase';
    v_status_label:='قيد الشراء';
    v_warehouse:=nullif(v_latest_transfer_warehouse,'');
  elsif v_last_warehouse is not null then
    v_status_value:='available';
    v_status_label:='متوفرة';
    v_warehouse:=v_last_warehouse;
  else
    v_status_value:='known';
    v_status_label:='معرفة';
    v_warehouse:=null;
  end if;

  update public.erp_cars as c
  set data=(
        c.data
        - 'status'
        - 'statusValue'
        - 'status_value'
        - 'warehouseId'
        - 'warehouse_id'
        - 'lastWarehouseId'
        - 'last_warehouse_id'
        - 'purchaseOrderId'
        - 'purchase_order_id'
        - 'purchaseReceiptId'
        - 'purchase_receipt_id'
        - 'salesOrderId'
        - 'sales_order_id'
        - 'salesDeliveryId'
        - 'sales_delivery_id'
        - 'salesInvoiceId'
        - 'sales_invoice_id'
      ) || jsonb_strip_nulls(jsonb_build_object(
        'status',v_status_label,
        'statusValue',v_status_value,
        'status_value',v_status_value,
        'warehouseId',v_warehouse,
        'warehouse_id',v_warehouse,
        'lastWarehouseId',case when v_warehouse is null then v_last_warehouse else null end,
        'last_warehouse_id',case when v_warehouse is null then v_last_warehouse else null end,
        'purchaseOrderId',case when v_purchase_order_id is null then null else v_purchase_order_id::text end,
        'purchase_order_id',case when v_purchase_order_id is null then null else v_purchase_order_id::text end,
        'purchaseReceiptId',case when v_purchase_receipt_id is null then null else v_purchase_receipt_id::text end,
        'purchase_receipt_id',case when v_purchase_receipt_id is null then null else v_purchase_receipt_id::text end,
        'salesOrderId',case when v_sales_order_id is null then null else v_sales_order_id::text end,
        'sales_order_id',case when v_sales_order_id is null then null else v_sales_order_id::text end,
        'salesDeliveryId',case when v_sales_delivery_id is null then null else v_sales_delivery_id::text end,
        'sales_delivery_id',case when v_sales_delivery_id is null then null else v_sales_delivery_id::text end,
        'salesInvoiceId',case when v_sales_invoice_id is null then null else v_sales_invoice_id::text end,
        'sales_invoice_id',case when v_sales_invoice_id is null then null else v_sales_invoice_id::text end,
        'operationalStateRebuiltAt',v_now,
        'updatedAt',v_now
      )),
      updated_at=v_now,
      updated_by=auth.uid()
  where c.company_id=p_company_id and c.id=p_car_id and not c.is_deleted;

  return jsonb_build_object(
    'carId',p_car_id,
    'carExists',true,
    'statusValue',v_status_value,
    'status',v_status_label,
    'warehouseId',v_warehouse,
    'lastWarehouseId',v_last_warehouse,
    'purchaseOrderId',v_purchase_order_id,
    'purchaseReceiptId',v_purchase_receipt_id,
    'salesOrderId',v_sales_order_id,
    'salesDeliveryId',v_sales_delivery_id,
    'salesInvoiceId',v_sales_invoice_id,
    'linksRefreshed',true
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Vehicle transfer deletion now replays the transfer chain and then recomputes
-- status/warehouse from purchase and sales documents.
-- ---------------------------------------------------------------------------
create or replace function public.erp_delete_car_warehouse_transfer(
  p_company_id uuid,
  p_transfer_id text,
  p_user_name text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_transfer public.erp_car_warehouse_transfers%rowtype;
  v_car_id text;
  v_from text;
  v_to text;
  v_base text;
  v_row record;
  v_now timestamptz:=clock_timestamp();
  v_batch uuid:=gen_random_uuid();
  v_sort_time timestamptz;
  v_state jsonb;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['cars.transfer.delete']
  );

  select t.* into v_transfer
  from public.erp_car_warehouse_transfers as t
  where t.company_id=p_company_id
    and t.id=p_transfer_id
    and not t.is_deleted
  for update;
  if not found then return; end if;

  v_car_id:=coalesce(v_transfer.data->>'carId',v_transfer.data->>'car_id');
  v_from:=coalesce(v_transfer.data->>'fromWarehouseId',v_transfer.data->>'from_warehouse_id');
  v_to:=coalesce(v_transfer.data->>'toWarehouseId',v_transfer.data->>'to_warehouse_id');
  v_sort_time:=public.erp_try_timestamptz(
    coalesce(v_transfer.data->>'transferDate',v_transfer.data->>'transfer_date'),
    v_transfer.created_at
  );

  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_car_warehouse_transfers',true);
  perform set_config('qualityline.deletion_root_id',p_transfer_id,true);
  perform set_config('qualityline.deletion_reason','Delete vehicle transfer and replay operational state',true);

  select coalesce(t.data->>'toWarehouseId',t.data->>'to_warehouse_id')
  into v_base
  from public.erp_car_warehouse_transfers as t
  where t.company_id=p_company_id
    and not t.is_deleted
    and t.id<>p_transfer_id
    and coalesce(t.data->>'carId',t.data->>'car_id')=v_car_id
    and public.erp_try_timestamptz(
      coalesce(t.data->>'transferDate',t.data->>'transfer_date'),t.created_at
    )<v_sort_time
  order by public.erp_try_timestamptz(
    coalesce(t.data->>'transferDate',t.data->>'transfer_date'),t.created_at
  ) desc,t.created_at desc,t.id desc
  limit 1;

  v_base:=coalesce(nullif(v_base,''),nullif(v_from,''));

  update public.erp_car_warehouse_transfers as t
  set is_deleted=true,
      deleted_at=v_now,
      updated_at=v_now,
      updated_by=auth.uid(),
      data=t.data||jsonb_build_object(
        'status','reversed',
        'deletedByUserName',coalesce(nullif(p_user_name,''),'system'),
        'deletedAt',v_now,
        'deleteReason','Delete vehicle transfer and replay operational state',
        'linksRebuilt',true
      )
  where t.company_id=p_company_id and t.id=p_transfer_id and not t.is_deleted;

  for v_row in
    select t.id,
           coalesce(t.data->>'toWarehouseId',t.data->>'to_warehouse_id') as to_warehouse
    from public.erp_car_warehouse_transfers as t
    where t.company_id=p_company_id
      and not t.is_deleted
      and coalesce(t.data->>'carId',t.data->>'car_id')=v_car_id
      and public.erp_try_timestamptz(
        coalesce(t.data->>'transferDate',t.data->>'transfer_date'),t.created_at
      )>=v_sort_time
    order by public.erp_try_timestamptz(
      coalesce(t.data->>'transferDate',t.data->>'transfer_date'),t.created_at
    ),t.created_at,t.id
    for update
  loop
    update public.erp_car_warehouse_transfers as t
    set data=(t.data-'fromWarehouseId'-'from_warehouse_id')||jsonb_build_object(
          'fromWarehouseId',v_base,
          'from_warehouse_id',v_base,
          'linksRebuiltAt',v_now
        ),
        updated_at=v_now,
        updated_by=auth.uid()
    where t.company_id=p_company_id and t.id=v_row.id;
    v_base:=coalesce(nullif(v_row.to_warehouse,''),v_base);
  end loop;

  v_state:=public.erp_v732_refresh_car_state(
    p_company_id,v_car_id,coalesce(nullif(v_from,''),nullif(v_to,''))
  );

  if coalesce((v_state->>'carExists')::boolean,false) then
    insert into public.erp_car_history_events(
      company_id,car_id,event_type,warehouse_before,warehouse_after,
      reference_type,reference_id,notes,event_date
    ) values(
      p_company_id,v_car_id,'warehouse_transfer_deleted',
      v_to,v_state->>'warehouseId','car_warehouse_transfer_delete',p_transfer_id,
      concat(
        'Operational state replayed by ',
        coalesce(nullif(p_user_name,''),'system'),
        '; status=',coalesce(v_state->>'statusValue','unknown')
      ),v_now
    );
  end if;

  update public.erp_universal_recycle_bin
  set relation_context=relation_context||jsonb_build_object(
    'warehouseTransferType','vehicle',
    'laterTransferLinksRebased',true,
    'operationalStateReplayed',true,
    'resolvedWarehouseId',v_state->>'warehouseId',
    'resolvedStatusValue',v_state->>'statusValue',
    'vehicleRecordExisted',coalesce((v_state->>'carExists')::boolean,false)
  )
  where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

-- ---------------------------------------------------------------------------
-- Purchase receipt reversal tolerates an already-deleted vehicle, retires the
-- receipt's inventory/accounting postings, and refreshes surviving cars.
-- ---------------------------------------------------------------------------
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
  v_product_id text;
  v_warehouse_id text;
  v_car_id text;
  v_journal record;
  v_now timestamptz:=clock_timestamp();
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
      p_company_id,v_invoice.id,'Reverse invoice before deleting purchase receipt'
    );
  end loop;

  update public.erp_inventory_fifo_consumptions as c
  set status='reversed',reversed_at=v_now
  where c.company_id=p_company_id
    and c.status='active'
    and exists(
      select 1
      from public.erp_inventory_cost_layers as l
      where l.id=c.layer_id
        and l.company_id=p_company_id
        and l.receipt_id=p_receipt_id
    )
    and not exists(
      select 1
      from public.erp_commercial_workflow_documents as d
      where d.company_id=p_company_id
        and d.id=c.delivery_id
        and d.module='sales'
        and d.document_type='delivery'
        and not d.is_deleted
        and d.status='approved'
    );

  if exists(
    select 1
    from public.erp_inventory_fifo_consumptions as c
    join public.erp_inventory_cost_layers as l on l.id=c.layer_id
    join public.erp_commercial_workflow_documents as d
      on d.company_id=c.company_id
     and d.id=c.delivery_id
     and d.module='sales'
     and d.document_type='delivery'
     and not d.is_deleted
     and d.status='approved'
    where l.company_id=p_company_id
      and l.receipt_id=p_receipt_id
      and c.status='active'
  ) then
    raise exception 'purchase_receipt_has_downstream_sales';
  end if;

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

  -- Retire the original receipt movements. Stock is rebuilt from the remaining
  -- active ledger, which also repairs old reversal pairs and stale links.
  update public.erp_inventory_movements as m
  set is_deleted=true,
      deleted_at=v_now,
      updated_at=v_now,
      updated_by=auth.uid(),
      data=m.data||jsonb_build_object(
        'deletedAt',v_now,
        'deleteReason','Purchase receipt deleted',
        'receiptPostingRetired',true
      )
  where m.company_id=p_company_id
    and not m.is_deleted
    and coalesce(m.data->>'referenceId',m.data->>'reference_id')=p_receipt_id::text
    and lower(coalesce(m.data->>'referenceType',m.data->>'reference_type',''))
      in ('purchase_receipt','purchase receipt','purchase_receipt_posting')
    and lower(coalesce(m.data->>'movementType',m.data->>'movement_type',''))
      in ('purchase_in','purchase_receipt','receipt_in','purchase');

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
    v_product_id:=v_allocation."itemId";
    v_warehouse_id:=coalesce(
      nullif(v_allocation."warehouseId",''),nullif(v_doc.warehouse_id,'')
    );

    if v_allocation."itemType"='product' then
      if exists(
        select 1 from public.erp_inventory as i
        where i.company_id=p_company_id
          and i.id=v_product_id
          and not i.is_deleted
      ) and v_warehouse_id is not null then
        perform public.erp_v73_rebuild_product_warehouse_stock(
          p_company_id,v_product_id,v_warehouse_id
        );
      else
        update public.erp_warehouse_stock as ws
        set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid()
        where ws.company_id=p_company_id
          and not ws.is_deleted
          and coalesce(ws.data->>'productId',ws.data->>'product_id')=v_product_id
          and (v_warehouse_id is null or coalesce(ws.data->>'warehouseId',ws.data->>'warehouse_id')=v_warehouse_id);
      end if;
    end if;
  end loop;

  update public.erp_inventory_cost_layers
  set remaining_quantity=0,
      status='reversed',
      updated_at=v_now,
      updated_by=auth.uid()
  where company_id=p_company_id
    and receipt_id=p_receipt_id
    and status<>'reversed';

  for v_journal in
    select je.id
    from public.erp_journal_entries as je
    where je.company_id=p_company_id
      and not je.is_deleted
      and (
        je.id=nullif(v_doc.payload->>'inventoryJournalEntryId','')
        or coalesce(je.data->>'referenceId',je.data->>'reference_id')=p_receipt_id::text
      )
  loop
    perform public.erp_v65_soft_delete_journal(
      p_company_id,v_journal.id,'Reverse purchase receipt accounting posting'
    );
  end loop;

  update public.erp_commercial_workflow_documents as d
  set status='cancelled',
      payload=d.payload||jsonb_build_object(
        'inventoryReversedAt',v_now,
        'accountingReversedAt',v_now,
        'cancelledAt',v_now,
        'linkedReversalComplete',true,
        'missingVehicleTolerated',true,
        'operationalStateReplayed',true
      ),
      updated_at=v_now,
      updated_by=auth.uid()
  where d.company_id=p_company_id and d.id=p_receipt_id;

  for v_car_id in
    select distinct x.item_id
    from public.erp_purchase_order_items_cloud as x
    where x.company_id=p_company_id
      and x.order_id=v_doc.parent_id
      and x.item_type='car'
      and not x.is_deleted
  loop
    perform public.erp_v732_refresh_car_state(
      p_company_id,v_car_id,v_doc.warehouse_id
    );
  end loop;

  perform public.erp_commercial_audit(
    p_company_id,'purchases',v_doc.parent_id,v_doc.id,v_doc.document_number,
    'cancel_receipt',v_doc.status,'cancelled',
    'Inventory/accounting links reversed; missing vehicle records tolerated'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Sales order cascade keeps payments and replays every surviving vehicle after
-- the order, delivery, invoice, and journal links are retired.
-- ---------------------------------------------------------------------------
create or replace function public.erp_delete_cloud_sales_order_v3(
  p_company_id uuid,
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_result jsonb;
  v_normalized integer;
  v_car_ids text[]:=array[]::text[];
  v_car_id text;
begin
  select coalesce(array_agg(distinct i.item_id),array[]::text[])
  into v_car_ids
  from public.erp_sales_order_items_cloud as i
  where i.company_id=p_company_id
    and i.order_id=p_order_id
    and i.item_type='car';

  perform public.erp_v731_release_advance_allocations(
    p_company_id,'sales',p_order_id,null,'Sales order deleted'
  );

  v_result:=public.erp_delete_cloud_sales_order_v2(p_company_id,p_order_id);

  foreach v_car_id in array v_car_ids
  loop
    perform public.erp_v732_refresh_car_state(p_company_id,v_car_id,null);
  end loop;

  v_normalized:=public.erp_v731_normalize_order_advances(p_company_id,p_order_id);
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'paymentPolicy','partner_balance_preserved',
    'paymentsRequiredDeleted',false,
    'paymentsPreserved',true,
    'normalizedAdvances',v_normalized,
    'futureAllocation','same_partner_same_currency',
    'vehicleStatesReplayed',coalesce(array_length(v_car_ids,1),0)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Purchase order cascade keeps payments, removes orphan vehicle transfers, and
-- refreshes every surviving vehicle after the order is retired.
-- ---------------------------------------------------------------------------
create or replace function public.erp_delete_cloud_purchase_order_v3(
  p_company_id uuid,
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_transfer record;
  v_result jsonb;
  v_normalized integer;
  v_car_ids text[]:=array[]::text[];
  v_car_id text;
begin
  select coalesce(array_agg(distinct i.item_id),array[]::text[])
  into v_car_ids
  from public.erp_purchase_order_items_cloud as i
  where i.company_id=p_company_id
    and i.order_id=p_order_id
    and i.item_type='car';

  perform public.erp_v731_release_advance_allocations(
    p_company_id,'purchases',p_order_id,null,'Purchase order deleted'
  );

  for v_transfer in
    select distinct t.id
    from public.erp_car_warehouse_transfers as t
    where t.company_id=p_company_id
      and not t.is_deleted
      and coalesce(t.data->>'carId',t.data->>'car_id')=any(v_car_ids)
    order by t.id
  loop
    perform public.erp_delete_car_warehouse_transfer(
      p_company_id,v_transfer.id,'Purchase order linked cleanup'
    );
  end loop;

  v_result:=public.erp_delete_cloud_purchase_order_v2(p_company_id,p_order_id);

  foreach v_car_id in array v_car_ids
  loop
    perform public.erp_v732_refresh_car_state(p_company_id,v_car_id,null);
  end loop;

  v_normalized:=public.erp_v731_normalize_order_advances(p_company_id,p_order_id);
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'paymentPolicy','partner_balance_preserved',
    'paymentsRequiredDeleted',false,
    'paymentsPreserved',true,
    'normalizedAdvances',v_normalized,
    'futureAllocation','same_partner_same_currency',
    'orphanVehicleTransfersCleaned',true,
    'vehicleStatesReplayed',coalesce(array_length(v_car_ids,1),0)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Independent component management with robust receipt deletion.
-- ---------------------------------------------------------------------------
create or replace function public.erp_manage_commercial_order_component(
  p_company_id uuid,
  p_module text,
  p_order_id uuid,
  p_component_type text,
  p_component_id uuid,
  p_action text,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_status text;
  v_reason text:=coalesce(nullif(btrim(p_reason),''),'Component action from order details');
  v_detached jsonb;
  v_released numeric:=0;
  v_car_id text;
begin
  if p_module not in ('sales','purchases') then
    raise exception 'invalid_workflow_module';
  end if;
  if p_component_type not in ('order','logistics','invoice','payment') then
    raise exception 'invalid_component_type';
  end if;
  if p_action not in ('approve','delete') then
    raise exception 'invalid_component_action';
  end if;

  if p_component_type='payment' then
    raise exception 'payment_is_cashbox_owned';
  end if;

  if p_component_type='order' then
    if p_action='approve' then
      if p_module='sales' then
        perform public.erp_approve_cloud_sales_order(p_company_id,p_order_id);
      else
        perform public.erp_approve_cloud_purchase_order(p_company_id,p_order_id);
      end if;
      return jsonb_build_object(
        'ok',true,'componentType','order','action','approve','status','approved'
      );
    end if;
    if p_module='sales' then
      return public.erp_delete_cloud_sales_order_v3(p_company_id,p_order_id);
    end if;
    return public.erp_delete_cloud_purchase_order_v3(p_company_id,p_order_id);
  end if;

  select d.* into v_doc
  from public.erp_commercial_workflow_documents as d
  where d.company_id=p_company_id
    and d.id=p_component_id
    and d.parent_id=p_order_id
    and d.module=p_module
    and not d.is_deleted
  for update;
  if not found then raise exception 'workflow_component_not_found'; end if;

  if p_component_type='logistics' then
    if v_doc.document_type<>(
      case when p_module='sales' then 'delivery' else 'receipt' end
    ) then
      raise exception 'workflow_component_type_mismatch';
    end if;

    if p_action='approve' then
      if p_module='sales' then
        perform public.erp_phase2_approve_sales_delivery(p_company_id,p_component_id);
      else
        perform public.erp_phase2_approve_purchase_receipt(p_company_id,p_component_id);
      end if;
    else
      if p_module='sales' then
        perform public.erp_cancel_cloud_sales_delivery(p_company_id,p_component_id);
      else
        perform public.erp_cancel_cloud_purchase_receipt(p_company_id,p_component_id);
      end if;
      update public.erp_commercial_workflow_documents
      set is_deleted=true,
          deleted_at=now(),
          updated_at=now(),
          updated_by=auth.uid(),
          payload=payload||jsonb_build_object(
            'deletedFromOrderDetails',true,
            'deleteReason',v_reason,
            'linksUpdated',true
          )
      where company_id=p_company_id and id=p_component_id;
    end if;
  elsif p_component_type='invoice' then
    if v_doc.document_type<>'invoice' then
      raise exception 'workflow_component_type_mismatch';
    end if;
    if p_action='approve' then
      if p_module='sales' then
        perform public.erp_approve_cloud_sales_workflow_invoice(p_company_id,p_component_id);
      else
        perform public.erp_approve_cloud_purchase_workflow_invoice(p_company_id,p_component_id);
      end if;
    else
      v_released:=public.erp_v731_release_advance_allocations(
        p_company_id,p_module,p_order_id,p_component_id,v_reason
      );
      v_detached:=public.erp_detach_cloud_workflow_invoice_payments(
        p_company_id,p_component_id,v_reason
      );
      perform public.erp_v731_normalize_order_advances(p_company_id,p_order_id);
      if p_module='sales' then
        perform public.erp_cancel_cloud_sales_workflow_invoice(
          p_company_id,p_component_id,v_reason
        );
      else
        perform public.erp_cancel_cloud_purchase_workflow_invoice(
          p_company_id,p_component_id,v_reason
        );
      end if;
      update public.erp_commercial_workflow_documents
      set is_deleted=true,
          deleted_at=now(),
          updated_at=now(),
          updated_by=auth.uid(),
          payload=payload||jsonb_build_object(
            'deletedFromOrderDetails',true,
            'deleteReason',v_reason,
            'paymentsPreserved',true,
            'releasedAdvanceAmount',v_released,
            'detachedPayments',coalesce(v_detached,'[]'::jsonb)
          )
      where company_id=p_company_id and id=p_component_id;
    end if;
  end if;

  if p_module='sales' then
    for v_car_id in
      select distinct i.item_id
      from public.erp_sales_order_items_cloud as i
      where i.company_id=p_company_id
        and i.order_id=p_order_id
        and i.item_type='car'
    loop
      perform public.erp_v732_refresh_car_state(p_company_id,v_car_id,null);
    end loop;
  else
    for v_car_id in
      select distinct i.item_id
      from public.erp_purchase_order_items_cloud as i
      where i.company_id=p_company_id
        and i.order_id=p_order_id
        and i.item_type='car'
    loop
      perform public.erp_v732_refresh_car_state(
        p_company_id,v_car_id,v_doc.warehouse_id
      );
    end loop;
  end if;

  v_status:=public.erp_v73_recompute_commercial_order_status(
    p_company_id,p_module,p_order_id
  );
  return jsonb_build_object(
    'ok',true,
    'module',p_module,
    'orderId',p_order_id,
    'componentType',p_component_type,
    'componentId',p_component_id,
    'action',p_action,
    'orderStatus',v_status,
    'linksUpdated',true,
    'missingVehicleTolerated',p_module='purchases' and p_component_type='logistics',
    'paymentsPreserved',p_component_type='invoice' and p_action='delete'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- A product may be deleted with a non-zero opening quantity when every active
-- business link has been removed and each warehouse is back to opening state.
-- ---------------------------------------------------------------------------
create or replace function public.erp_inventory_product_delete_impact(
  p_company_id uuid,
  p_product_id text
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_stock numeric:=0;
  v_opening numeric:=0;
  v_sales bigint:=0;
  v_purchases bigint:=0;
  v_transfers bigint:=0;
  v_fifo bigint:=0;
  v_non_opening bigint:=0;
  v_orphan_movements bigint:=0;
  v_warehouse_mismatches bigint:=0;
  v_returned boolean:=false;
  v_can_delete boolean:=false;
begin
  perform public.erp_active_company_context(p_company_id);

  select coalesce(sum(public.erp_try_numeric(
    coalesce(ws.data->>'quantity',ws.data->>'onHand'),0
  )),0)
  into v_stock
  from public.erp_warehouse_stock as ws
  where ws.company_id=p_company_id
    and not ws.is_deleted
    and coalesce(ws.data->>'productId',ws.data->>'product_id')=p_product_id;

  select coalesce(sum(public.erp_try_numeric(m.data->>'quantity',0)),0)
  into v_opening
  from public.erp_inventory_movements as m
  where m.company_id=p_company_id
    and not m.is_deleted
    and coalesce(m.data->>'productId',m.data->>'product_id')=p_product_id
    and lower(coalesce(m.data->>'movementType',m.data->>'movement_type','')) in (
      'opening','opening_balance','initial','initial_balance',
      'opening_adjustment','initial_stock'
    );

  select count(*) into v_sales
  from public.erp_sales_order_items_cloud as i
  join public.erp_sales_orders_cloud as o
    on o.company_id=i.company_id and o.id=i.order_id
  where i.company_id=p_company_id
    and i.item_type='product'
    and i.item_id=p_product_id
    and not i.is_deleted
    and not o.is_deleted
    and o.status not in ('cancelled','reversed','deleted');

  select count(*) into v_purchases
  from public.erp_purchase_order_items_cloud as i
  join public.erp_purchase_orders_cloud as o
    on o.company_id=i.company_id and o.id=i.order_id
  where i.company_id=p_company_id
    and i.item_type='product'
    and i.item_id=p_product_id
    and not i.is_deleted
    and not o.is_deleted
    and o.status not in ('cancelled','reversed','deleted');

  select count(*) into v_transfers
  from public.erp_warehouse_transfer_items as i
  join public.erp_warehouse_transfers as t
    on t.company_id=i.company_id
   and t.id=coalesce(i.data->>'transferId',i.data->>'transfer_id')
   and not t.is_deleted
   and lower(coalesce(t.data->>'status','approved')) not in (
     'cancelled','reversed','deleted'
   )
  where i.company_id=p_company_id
    and not i.is_deleted
    and coalesce(i.data->>'productId',i.data->>'product_id')=p_product_id;

  select count(*) into v_fifo
  from public.erp_inventory_fifo_consumptions as c
  join public.erp_commercial_workflow_documents as d
    on d.company_id=c.company_id
   and d.id=c.delivery_id
   and d.module='sales'
   and d.document_type='delivery'
   and not d.is_deleted
   and d.status='approved'
  where c.company_id=p_company_id
    and c.item_type='product'
    and c.item_id=p_product_id
    and c.status='active';

  select count(*) into v_non_opening
  from public.erp_inventory_movements as m
  where m.company_id=p_company_id
    and not m.is_deleted
    and coalesce(m.data->>'productId',m.data->>'product_id')=p_product_id
    and lower(coalesce(m.data->>'movementType',m.data->>'movement_type','')) not in (
      'opening','opening_balance','initial','initial_balance',
      'opening_adjustment','initial_stock'
    );

  select count(*) into v_orphan_movements
  from public.erp_inventory_movements as m
  where m.company_id=p_company_id
    and not m.is_deleted
    and coalesce(m.data->>'productId',m.data->>'product_id')=p_product_id
    and lower(coalesce(m.data->>'movementType',m.data->>'movement_type','')) not in (
      'opening','opening_balance','initial','initial_balance',
      'opening_adjustment','initial_stock'
    )
    and not exists(
      select 1
      from public.erp_warehouse_transfers as t
      where t.company_id=p_company_id
        and not t.is_deleted
        and t.id=coalesce(m.data->>'referenceId',m.data->>'reference_id')
    )
    and not exists(
      select 1
      from public.erp_commercial_workflow_documents as d
      where d.company_id=p_company_id
        and not d.is_deleted
        and d.id::text=coalesce(m.data->>'referenceId',m.data->>'reference_id')
        and d.status not in ('cancelled','reversed')
    )
    and not exists(
      select 1
      from public.erp_maintenance_orders as mo
      where mo.company_id=p_company_id
        and not mo.is_deleted
        and mo.id::text=coalesce(m.data->>'referenceId',m.data->>'reference_id')
        and mo.workflow_stage<>'cancelled'
    );

  with warehouse_ids as (
    select coalesce(ws.data->>'warehouseId',ws.data->>'warehouse_id') as warehouse_id
    from public.erp_warehouse_stock as ws
    where ws.company_id=p_company_id
      and not ws.is_deleted
      and coalesce(ws.data->>'productId',ws.data->>'product_id')=p_product_id
    union
    select coalesce(m.data->>'warehouseId',m.data->>'warehouse_id')
    from public.erp_inventory_movements as m
    where m.company_id=p_company_id
      and not m.is_deleted
      and coalesce(m.data->>'productId',m.data->>'product_id')=p_product_id
      and lower(coalesce(m.data->>'movementType',m.data->>'movement_type','')) in (
        'opening','opening_balance','initial','initial_balance',
        'opening_adjustment','initial_stock'
      )
  ), balances as (
    select w.warehouse_id,
      coalesce((
        select sum(public.erp_try_numeric(coalesce(ws.data->>'quantity',ws.data->>'onHand'),0))
        from public.erp_warehouse_stock as ws
        where ws.company_id=p_company_id
          and not ws.is_deleted
          and coalesce(ws.data->>'productId',ws.data->>'product_id')=p_product_id
          and coalesce(ws.data->>'warehouseId',ws.data->>'warehouse_id')=w.warehouse_id
      ),0) as current_quantity,
      coalesce((
        select sum(public.erp_try_numeric(m.data->>'quantity',0))
        from public.erp_inventory_movements as m
        where m.company_id=p_company_id
          and not m.is_deleted
          and coalesce(m.data->>'productId',m.data->>'product_id')=p_product_id
          and coalesce(m.data->>'warehouseId',m.data->>'warehouse_id')=w.warehouse_id
          and lower(coalesce(m.data->>'movementType',m.data->>'movement_type','')) in (
            'opening','opening_balance','initial','initial_balance',
            'opening_adjustment','initial_stock'
          )
      ),0) as opening_quantity
    from warehouse_ids as w
    where nullif(w.warehouse_id,'') is not null
  )
  select count(*) into v_warehouse_mismatches
  from balances
  where abs(current_quantity-opening_quantity)>0.0001;

  v_returned:=v_warehouse_mismatches=0;
  v_can_delete:=v_sales=0
    and v_purchases=0
    and v_transfers=0
    and v_fifo=0
    and v_returned;

  return jsonb_build_object(
    'stockQuantity',v_stock,
    'openingQuantity',v_opening,
    'salesOrderLinks',v_sales,
    'purchaseOrderLinks',v_purchases,
    'transferLinks',v_transfers,
    'activeFifoConsumptions',v_fifo,
    'nonOpeningMovementCount',v_non_opening,
    'orphanMovementCount',v_orphan_movements,
    'warehouseOpeningMismatches',v_warehouse_mismatches,
    'returnedToOpeningState',v_returned,
    'openingOnly',v_returned and abs(v_stock)>0.0001,
    'canDelete',v_can_delete,
    'deletePolicy','active_links_removed_and_each_warehouse_back_to_opening_state'
  );
end;
$$;

create or replace function public.erp_delete_inventory_product(
  p_company_id uuid,
  p_product_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_batch uuid:=gen_random_uuid();
  v_impact jsonb;
  v_now timestamptz:=clock_timestamp();
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['inventory.delete']
  );

  perform 1
  from public.erp_inventory
  where company_id=p_company_id and id=p_product_id and not is_deleted
  for update;
  if not found then raise exception 'inventory_product_not_found'; end if;

  v_impact:=public.erp_inventory_product_delete_impact(
    p_company_id,p_product_id
  );
  if not coalesce((v_impact->>'canDelete')::boolean,false) then
    raise exception 'inventory_product_not_back_to_opening_state:%',v_impact::text;
  end if;

  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_inventory',true);
  perform set_config('qualityline.deletion_root_id',p_product_id,true);
  perform set_config(
    'qualityline.deletion_reason',
    'Delete inventory product after active links were removed and warehouses returned to opening state',
    true
  );

  delete from public.erp_inventory_fifo_consumptions
  where company_id=p_company_id
    and item_type='product'
    and item_id=p_product_id;

  delete from public.erp_inventory_cost_layers
  where company_id=p_company_id
    and item_type='product'
    and item_id=p_product_id;

  update public.erp_inventory_movements
  set is_deleted=true,
      deleted_at=v_now,
      updated_at=v_now,
      updated_by=auth.uid(),
      data=data||jsonb_build_object(
        'deletedWithProduct',true,
        'openingBalanceRetired',true,
        'staleOperationalMovementsRetired',true
      )
  where company_id=p_company_id
    and not is_deleted
    and coalesce(data->>'productId',data->>'product_id')=p_product_id;

  update public.erp_warehouse_transfer_items as wi
  set is_deleted=true,
      deleted_at=v_now,
      updated_at=v_now,
      updated_by=auth.uid(),
      data=wi.data||jsonb_build_object(
        'deletedWithProduct',true,
        'staleLinkRetired',true
      )
  where wi.company_id=p_company_id
    and not wi.is_deleted
    and coalesce(wi.data->>'productId',wi.data->>'product_id')=p_product_id
    and not exists(
      select 1
      from public.erp_warehouse_transfers as t
      where t.company_id=p_company_id
        and not t.is_deleted
        and t.id=coalesce(
          wi.data->>'transferId',wi.data->>'transfer_id'
        )
    );

  update public.erp_product_images
  set is_deleted=true,deleted_at=v_now,updated_at=v_now
  where company_id=p_company_id
    and coalesce(data->>'productId',data->>'product_id')=p_product_id
    and not is_deleted;

  update public.erp_warehouse_stock
  set is_deleted=true,
      deleted_at=v_now,
      updated_at=v_now,
      updated_by=auth.uid(),
      data=data||jsonb_build_object(
        'deletedWithProduct',true,
        'openingBalanceRetired',true
      )
  where company_id=p_company_id
    and coalesce(data->>'productId',data->>'product_id')=p_product_id
    and not is_deleted;

  update public.erp_inventory_product_sales
  set is_deleted=true,deleted_at=v_now,updated_at=v_now
  where company_id=p_company_id
    and not is_deleted
    and coalesce(data->>'productId',data->>'product_id')=p_product_id;

  update public.erp_inventory
  set is_deleted=true,
      deleted_at=v_now,
      updated_at=v_now,
      updated_by=auth.uid(),
      data=data||jsonb_build_object(
        'openingBalanceRetired',true,
        'deletedAfterLinksReturnedToOpeningState',true,
        'deleteImpact',v_impact
      )
  where company_id=p_company_id and id=p_product_id and not is_deleted;

  update public.erp_universal_recycle_bin
  set relation_context=relation_context||jsonb_build_object(
    'inventoryDeleteImpact',v_impact,
    'openingBalanceRetired',true,
    'staleOperationalMovementsRetired',true
  )
  where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

revoke all on function public.erp_v732_refresh_car_state(uuid,text,text) from public,anon;
revoke all on function public.erp_delete_car_warehouse_transfer(uuid,text,text) from public,anon;
revoke all on function public.erp_cancel_cloud_purchase_receipt(uuid,uuid) from public,anon;
revoke all on function public.erp_delete_cloud_sales_order_v3(uuid,uuid) from public,anon;
revoke all on function public.erp_delete_cloud_purchase_order_v3(uuid,uuid) from public,anon;
revoke all on function public.erp_manage_commercial_order_component(uuid,text,uuid,text,uuid,text,text) from public,anon;
revoke all on function public.erp_inventory_product_delete_impact(uuid,text) from public,anon;
revoke all on function public.erp_delete_inventory_product(uuid,text) from public,anon;

grant execute on function public.erp_v732_refresh_car_state(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_delete_car_warehouse_transfer(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_cancel_cloud_purchase_receipt(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_sales_order_v3(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_purchase_order_v3(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_manage_commercial_order_component(uuid,text,uuid,text,uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_inventory_product_delete_impact(uuid,text) to authenticated,service_role;
grant execute on function public.erp_delete_inventory_product(uuid,text) to authenticated,service_role;

commit;
