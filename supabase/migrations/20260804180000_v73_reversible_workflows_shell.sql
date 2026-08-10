-- Quality Line ERP 18.9 / V7.3
-- Reversible warehouse/commercial/accounting workflows and complete recycle metadata.
begin;

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

create or replace function public.erp_v73_active_order_payment_count(
  p_company_id uuid,
  p_module text,
  p_order_id uuid,
  p_invoice_id uuid default null
) returns integer
language plpgsql
security definer
set search_path=public
as $$
declare
  v_count integer:=0;
begin
  select count(*)::integer into v_count
  from public.erp_cash_transactions as ct
  where ct.company_id=p_company_id
    and not ct.is_deleted
    and (
      (p_invoice_id is not null and coalesce(
        ct.data->>'invoiceId',ct.data->>'invoice_id',
        ct.data->>'referenceId',ct.data->>'reference_id'
      )=p_invoice_id::text)
      or coalesce(
        ct.data->>'orderId',ct.data->>'order_id',
        ct.data->>'salesOrderId',ct.data->>'sales_order_id',
        ct.data->>'purchaseOrderId',ct.data->>'purchase_order_id',
        ct.data->>'maintenanceOrderId',ct.data->>'maintenance_order_id'
      )=p_order_id::text
      or exists(
        select 1
        from public.erp_commercial_workflow_documents as d
        where d.company_id=p_company_id
          and d.parent_id=p_order_id
          and d.module=p_module
          and not d.is_deleted
          and coalesce(
            ct.data->>'invoiceId',ct.data->>'invoice_id',
            ct.data->>'referenceId',ct.data->>'reference_id'
          )=d.id::text
      )
    );

  if p_module='maintenance' then
    v_count:=v_count+(
      select count(*)::integer
      from public.erp_maintenance_payments as mp
      where mp.company_id=p_company_id
        and mp.maintenance_order_id=p_order_id
        and not mp.is_deleted
    );
  end if;

  return v_count;
end;
$$;

create or replace function public.erp_v73_recompute_commercial_order_status(
  p_company_id uuid,
  p_module text,
  p_order_id uuid
) returns text
language plpgsql
security definer
set search_path=public
as $$
declare
  v_status text;
  v_logistics integer;
  v_invoices integer;
begin
  select count(*)::integer into v_logistics
  from public.erp_commercial_workflow_documents as d
  where d.company_id=p_company_id
    and d.module=p_module
    and d.parent_id=p_order_id
    and d.document_type=case when p_module='sales' then 'delivery' else 'receipt' end
    and not d.is_deleted
    and d.status not in ('cancelled','reversed');

  select count(*)::integer into v_invoices
  from public.erp_commercial_workflow_documents as d
  where d.company_id=p_company_id
    and d.module=p_module
    and d.parent_id=p_order_id
    and d.document_type='invoice'
    and not d.is_deleted
    and d.status not in ('cancelled','reversed');

  v_status:=case
    when v_invoices>0 then 'completed'
    when v_logistics>0 then 'partially_executed'
    else 'approved'
  end;

  if p_module='sales' then
    update public.erp_sales_orders_cloud
    set status=v_status,updated_at=now()
    where company_id=p_company_id and id=p_order_id and not is_deleted;
  elsif p_module='purchases' then
    update public.erp_purchase_orders_cloud
    set status=v_status,updated_at=now()
    where company_id=p_company_id and id=p_order_id and not is_deleted;
  else
    raise exception 'invalid_workflow_module';
  end if;

  return v_status;
end;
$$;

-- ---------------------------------------------------------------------------
-- Product warehouse transfers: one document, reversible by ledger replay.
-- ---------------------------------------------------------------------------

create or replace function public.erp_v73_rebuild_product_warehouse_stock(
  p_company_id uuid,
  p_product_id text,
  p_warehouse_id text
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_stock public.erp_warehouse_stock%rowtype;
  v_qty numeric;
  v_value numeric;
  v_avg numeric;
  v_reserved numeric;
begin
  select
    coalesce(sum(public.erp_try_numeric(m.data->>'quantity',0)),0),
    coalesce(sum(
      public.erp_try_numeric(m.data->>'quantity',0) *
      public.erp_try_numeric(coalesce(m.data->>'unitCost',m.data->>'unit_cost'),0)
    ),0)
  into v_qty,v_value
  from public.erp_inventory_movements as m
  where m.company_id=p_company_id
    and not m.is_deleted
    and coalesce(m.data->>'productId',m.data->>'product_id')=p_product_id
    and coalesce(m.data->>'warehouseId',m.data->>'warehouse_id')=p_warehouse_id;

  if v_qty<0 then
    raise exception 'warehouse_history_would_be_negative:%:%:%',
      p_product_id,p_warehouse_id,v_qty;
  end if;

  v_stock:=public.erp_inventory_ensure_stock(
    p_company_id,p_warehouse_id,p_product_id
  );
  v_reserved:=public.erp_try_numeric(v_stock.data->>'reservedQuantity',0);
  if v_qty<v_reserved then
    raise exception 'warehouse_history_below_reserved_quantity:%:%',
      p_product_id,p_warehouse_id;
  end if;

  v_avg:=case when v_qty>0 then greatest(v_value,0)/v_qty else 0 end;

  update public.erp_warehouse_stock as ws
  set data=ws.data||jsonb_build_object(
        'quantity',trunc(v_qty)::int,
        'averageUnitCost',round(v_avg,4),
        'updatedAt',now(),
        'rebuiltFromMovementLedger',true
      ),
      updated_at=now(),
      updated_by=auth.uid()
  where ws.company_id=p_company_id and ws.id=v_stock.id;

  perform public.erp_inventory_refresh_product(p_company_id,p_product_id);
  return jsonb_build_object(
    'productId',p_product_id,
    'warehouseId',p_warehouse_id,
    'quantity',v_qty,
    'averageUnitCost',v_avg
  );
end;
$$;

create or replace function public.erp_delete_inventory_warehouse_transfer(
  p_company_id uuid,
  p_transfer_id text,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_transfer public.erp_warehouse_transfers%rowtype;
  v_item record;
  v_reason text:=coalesce(nullif(btrim(p_reason),''),'Delete product warehouse transfer and rebuild all links');
  v_now timestamptz:=now();
  v_batch uuid:=gen_random_uuid();
  v_source_id text;
  v_target_id text;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['inventory.transfer.delete']
  );

  select wt.* into v_transfer
  from public.erp_warehouse_transfers as wt
  where wt.company_id=p_company_id and wt.id=p_transfer_id
  for update;
  if not found or v_transfer.is_deleted then return; end if;

  v_source_id:=coalesce(
    v_transfer.data->>'fromWarehouseId',v_transfer.data->>'from_warehouse_id'
  );
  v_target_id:=coalesce(
    v_transfer.data->>'toWarehouseId',v_transfer.data->>'to_warehouse_id'
  );
  if nullif(v_source_id,'') is null
     or nullif(v_target_id,'') is null
     or v_source_id=v_target_id then
    raise exception 'warehouse_transfer_invalid_warehouse_link';
  end if;

  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_warehouse_transfers',true);
  perform set_config('qualityline.deletion_root_id',p_transfer_id,true);
  perform set_config('qualityline.deletion_reason',v_reason,true);

  -- Retire the two original ledger movements first. Stock is then reconstructed
  -- from every remaining active movement, so later valid operations remain valid.
  perform public.erp_v67_retire_transfer_movements(
    p_company_id,p_transfer_id,v_reason
  );

  update public.erp_warehouse_transfer_items as wi
  set is_deleted=true,
      deleted_at=v_now,
      updated_at=v_now,
      updated_by=auth.uid(),
      data=wi.data||jsonb_build_object(
        'deletedAt',v_now,'deleteReason',v_reason,'linksRebuilt',true
      )
  where wi.company_id=p_company_id
    and not wi.is_deleted
    and coalesce(wi.data->>'transferId',wi.data->>'transfer_id')=p_transfer_id;

  update public.erp_warehouse_transfers as wt
  set is_deleted=true,
      deleted_at=v_now,
      updated_at=v_now,
      updated_by=auth.uid(),
      data=wt.data||jsonb_build_object(
        'status','reversed',
        'deletedAt',v_now,
        'deleteReason',v_reason,
        'sourceAndDestinationInOneDocument',true,
        'linksRebuilt',true
      )
  where wt.company_id=p_company_id and wt.id=p_transfer_id and not wt.is_deleted;

  for v_item in
    select distinct coalesce(i.data->>'productId',i.data->>'product_id') as product_id
    from public.erp_warehouse_transfer_items as i
    where i.company_id=p_company_id
      and coalesce(i.data->>'transferId',i.data->>'transfer_id')=p_transfer_id
      and nullif(coalesce(i.data->>'productId',i.data->>'product_id'),'') is not null
  loop
    perform public.erp_v73_rebuild_product_warehouse_stock(
      p_company_id,v_item.product_id,v_source_id
    );
    perform public.erp_v73_rebuild_product_warehouse_stock(
      p_company_id,v_item.product_id,v_target_id
    );
  end loop;

  update public.erp_universal_recycle_bin
  set relation_context=relation_context||jsonb_build_object(
    'warehouseTransferType','product',
    'movementLinksRetired',true,
    'stockRebuiltFromLedger',true,
    'sourceAndDestinationInOneDocument',true
  )
  where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

-- ---------------------------------------------------------------------------
-- Vehicle warehouse transfers: delete orphans and rebase later transfer links.
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
  v_current text;
  v_row record;
  v_now timestamptz:=clock_timestamp();
  v_batch uuid:=gen_random_uuid();
  v_sort_time timestamptz;
  v_car_exists boolean:=false;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['cars.transfer.delete']
  );

  select t.* into v_transfer
  from public.erp_car_warehouse_transfers as t
  where t.company_id=p_company_id and t.id=p_transfer_id and not t.is_deleted
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
  perform set_config('qualityline.deletion_reason','Delete vehicle warehouse transfer and rebuild links',true);

  -- The car may already have been deleted by an old purchase-order error. The
  -- transfer must still be removable, so car existence is not a precondition.
  select exists(
    select 1 from public.erp_cars as c
    where c.company_id=p_company_id and c.id=v_car_id and not c.is_deleted
  ) into v_car_exists;

  select coalesce(
    t.data->>'toWarehouseId',t.data->>'to_warehouse_id'
  ) into v_base
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

  v_base:=coalesce(nullif(v_base,''),v_from);

  update public.erp_car_warehouse_transfers as t
  set is_deleted=true,
      deleted_at=v_now,
      updated_at=v_now,
      updated_by=auth.uid(),
      data=t.data||jsonb_build_object(
        'status','reversed',
        'deletedByUserName',coalesce(nullif(p_user_name,''),'system'),
        'deletedAt',v_now,
        'deleteReason','Delete vehicle warehouse transfer and rebuild links',
        'linksRebuilt',true
      )
  where t.company_id=p_company_id and t.id=p_transfer_id and not t.is_deleted;

  -- Rebase every later transfer so its source follows the previous active
  -- destination. This repairs historical chains after a middle transfer is gone.
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

  select coalesce(
    t.data->>'toWarehouseId',t.data->>'to_warehouse_id'
  ) into v_current
  from public.erp_car_warehouse_transfers as t
  where t.company_id=p_company_id
    and not t.is_deleted
    and coalesce(t.data->>'carId',t.data->>'car_id')=v_car_id
  order by public.erp_try_timestamptz(
    coalesce(t.data->>'transferDate',t.data->>'transfer_date'),t.created_at
  ) desc,t.created_at desc,t.id desc
  limit 1;

  v_current:=coalesce(nullif(v_current,''),v_from);

  if v_car_exists then
    update public.erp_cars as c
    set data=(c.data-'warehouseId'-'warehouse_id')||jsonb_build_object(
          'warehouseId',v_current,
          'warehouse_id',v_current,
          'updatedAt',v_now,
          'warehouseLinksRebuiltAt',v_now
        ),
        updated_at=v_now,
        updated_by=auth.uid()
    where c.company_id=p_company_id and c.id=v_car_id and not c.is_deleted;

    insert into public.erp_car_history_events(
      company_id,car_id,event_type,warehouse_before,warehouse_after,
      reference_type,reference_id,notes,event_date
    ) values(
      p_company_id,v_car_id,'warehouse_transfer_deleted',
      v_to,v_current,'car_warehouse_transfer_delete',p_transfer_id,
      concat('Links rebuilt by ',coalesce(nullif(p_user_name,''),'system')),v_now
    );
  end if;

  update public.erp_universal_recycle_bin
  set relation_context=relation_context||jsonb_build_object(
    'warehouseTransferType','vehicle',
    'vehicleRecordExisted',v_car_exists,
    'laterTransferLinksRebased',true,
    'resolvedWarehouseId',v_current
  )
  where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

-- ---------------------------------------------------------------------------
-- Commercial and maintenance deletion: payments are owned by the cashbox.
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
  v_payments integer;
  v_result jsonb;
begin
  v_payments:=public.erp_v73_active_order_payment_count(
    p_company_id,'sales',p_order_id,null
  );
  if v_payments>0 then
    raise exception 'delete_payment_from_cashbox_first:%',v_payments;
  end if;
  v_result:=public.erp_delete_cloud_sales_order_v2(p_company_id,p_order_id);
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'paymentPolicy','cashbox_owned','paymentsRequiredDeleted',true
  );
end;
$$;

create or replace function public.erp_delete_cloud_purchase_order_v3(
  p_company_id uuid,
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_payments integer;
  v_transfer record;
  v_result jsonb;
begin
  v_payments:=public.erp_v73_active_order_payment_count(
    p_company_id,'purchases',p_order_id,null
  );
  if v_payments>0 then
    raise exception 'delete_payment_from_cashbox_first:%',v_payments;
  end if;

  -- Repair old records where a purchased car was deleted before its warehouse
  -- transfer and purchase order. The transfer delete now tolerates a missing car.
  for v_transfer in
    select distinct t.id
    from public.erp_car_warehouse_transfers as t
    where t.company_id=p_company_id
      and not t.is_deleted
      and coalesce(t.data->>'carId',t.data->>'car_id') in (
        select i.item_id
        from public.erp_purchase_order_items_cloud as i
        where i.company_id=p_company_id
          and i.order_id=p_order_id
          and i.item_type='car'
      )
    order by t.id
  loop
    perform public.erp_delete_car_warehouse_transfer(
      p_company_id,v_transfer.id,'Purchase order linked cleanup'
    );
  end loop;

  v_result:=public.erp_delete_cloud_purchase_order_v2(p_company_id,p_order_id);
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'paymentPolicy','cashbox_owned',
    'paymentsRequiredDeleted',true,
    'orphanVehicleTransfersCleaned',true
  );
end;
$$;

create or replace function public.erp_delete_cloud_maintenance_order_v3(
  p_company_id uuid,
  p_order_id uuid,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_payments integer;
  v_result jsonb;
begin
  v_payments:=public.erp_v73_active_order_payment_count(
    p_company_id,'maintenance',p_order_id,null
  );
  if v_payments>0 then
    raise exception 'delete_payment_from_cashbox_first:%',v_payments;
  end if;
  v_result:=public.erp_delete_cloud_maintenance_order_v2(
    p_company_id,p_order_id,p_reason
  );
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'paymentPolicy','cashbox_owned','paymentsRequiredDeleted',true
  );
end;
$$;

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
  v_payment_count integer;
  v_reason text:=coalesce(nullif(btrim(p_reason),''),'Component action from order details');
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
    raise exception 'delete_payment_from_cashbox_first';
  end if;

  if p_component_type='order' then
    if p_action='approve' then
      if p_module='sales' then
        perform public.erp_approve_cloud_sales_order(p_company_id,p_order_id);
      else
        perform public.erp_approve_cloud_purchase_order(p_company_id,p_order_id);
      end if;
      v_status:='approved';
      return jsonb_build_object(
        'ok',true,'componentType','order','action','approve','status',v_status
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
    if v_doc.document_type<>(case when p_module='sales' then 'delivery' else 'receipt' end) then
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
            'deletedFromOrderDetails',true,'deleteReason',v_reason
          )
      where company_id=p_company_id and id=p_component_id;
    end if;
  elsif p_component_type='invoice' then
    if v_doc.document_type<>'invoice' then
      raise exception 'workflow_component_type_mismatch';
    end if;

    if p_action='approve' then
      if p_module='sales' then
        perform public.erp_approve_cloud_sales_workflow_invoice(
          p_company_id,p_component_id
        );
      else
        perform public.erp_approve_cloud_purchase_workflow_invoice(
          p_company_id,p_component_id
        );
      end if;
    else
      v_payment_count:=public.erp_v73_active_order_payment_count(
        p_company_id,p_module,p_order_id,p_component_id
      );
      if v_payment_count>0 then
        raise exception 'delete_payment_from_cashbox_first:%',v_payment_count;
      end if;

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
            'deletedFromOrderDetails',true,'deleteReason',v_reason
          )
      where company_id=p_company_id and id=p_component_id;
    end if;
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
    'linksUpdated',true
  );
end;
$$;


-- Maintenance payments are true cashbox documents. They stay independently
-- deletable from the cashbox and automatically update the linked order.
alter table public.erp_maintenance_payments
  add column if not exists cash_transaction_id text,
  add column if not exists journal_entry_id text,
  add column if not exists updated_at timestamptz not null default now(),
  add column if not exists updated_by uuid;

create index if not exists erp_maintenance_payments_cash_transaction_idx
  on public.erp_maintenance_payments(company_id,cash_transaction_id)
  where not is_deleted and cash_transaction_id is not null;

create or replace function public.erp_record_cloud_maintenance_payment(
  p_company_id uuid,p_order_id uuid,p_amount numeric,
  p_currency_code text default null,p_exchange_rate numeric default null,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  o public.erp_maintenance_orders%rowtype;
  v_rate numeric;
  v_currency text;
  v_converted numeric;
  v_next numeric;
  v_id uuid:=gen_random_uuid();
  v_cash_transaction_id text:=gen_random_uuid()::text;
  v_cash_account_id text;
  v_cash_ledger_id text;
  v_partner_account_id text;
  v_journal_id text:=gen_random_uuid()::text;
  v_voucher text;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['cashbox.receipt']
  );
  if p_amount<=0 then raise exception 'maintenance_invalid_payment_amount'; end if;

  select * into o
  from public.erp_maintenance_orders
  where id=p_order_id and company_id=p_company_id and not is_deleted
  for update;
  if not found or o.workflow_stage<>'invoice_approved' then
    raise exception 'maintenance_approved_invoice_required';
  end if;

  v_currency:=upper(coalesce(nullif(p_currency_code,''),o.currency_code));
  v_rate:=coalesce(p_exchange_rate,o.exchange_rate);
  if v_rate<=0 then raise exception 'maintenance_invalid_exchange_rate'; end if;
  v_converted:=case
    when v_currency=upper(o.currency_code) then p_amount
    when v_currency='IQD' and upper(o.currency_code)='USD' then p_amount/v_rate
    else p_amount*v_rate
  end;
  v_next:=o.paid_amount+v_converted;
  if v_next>o.sale_price+0.001 then
    raise exception 'maintenance_payment_exceeds_balance';
  end if;

  select ca.id,coalesce(ca.data->>'accountId',ca.data->>'account_id')
  into v_cash_account_id,v_cash_ledger_id
  from public.erp_cash_accounts as ca
  where ca.company_id=p_company_id
    and not ca.is_deleted
    and public.erp_try_boolean(ca.data->>'isActive',true)
    and upper(coalesce(ca.data->>'currency',''))=v_currency
    and nullif(coalesce(ca.data->>'accountId',ca.data->>'account_id'),'') is not null
  order by
    public.erp_try_boolean(coalesce(ca.data->>'isDefault',ca.data->>'is_default'),false) desc,
    ca.created_at
  limit 1;
  if v_cash_account_id is null then
    raise exception 'maintenance_cash_account_required:%',v_currency;
  end if;

  if o.customer_id is null then
    raise exception 'maintenance_customer_required_for_payment';
  end if;
  v_partner_account_id:=public.erp_workflow_partner_account(
    p_company_id,'customer',o.customer_id::text,v_currency
  );
  v_voucher:='MRC-'||upper(substr(replace(v_id::text,'-',''),1,14));

  insert into public.erp_maintenance_payments(
    id,company_id,maintenance_order_id,amount,currency_code,exchange_rate,
    amount_in_order_currency,notes,cash_transaction_id,updated_at,updated_by
  ) values(
    v_id,p_company_id,o.id,p_amount,v_currency,v_rate,v_converted,p_notes,
    v_cash_transaction_id,now(),auth.uid()
  );

  insert into public.erp_cash_transactions(
    company_id,id,data,created_by,updated_by
  ) values(
    p_company_id,
    v_cash_transaction_id,
    jsonb_build_object(
      'id',v_cash_transaction_id,
      'cashAccountId',v_cash_account_id,
      'counterAccountId',v_partner_account_id,
      'voucherNumber',v_voucher,
      'type','receipt',
      'currency',v_currency,
      'amount',p_amount,
      'transactionDate',now(),
      'category','maintenance_payment',
      'referenceType','maintenance_payment',
      'referenceId',v_id::text,
      'maintenanceOrderId',o.id::text,
      'invoiceNumber',o.invoice_number,
      'journalEntryId',v_journal_id,
      'notes',coalesce(p_notes,'Maintenance payment '||o.order_number)
    ),
    auth.uid(),auth.uid()
  );

  insert into public.erp_journal_entries(
    company_id,id,data,created_by,updated_by
  ) values(
    p_company_id,
    v_journal_id,
    jsonb_build_object(
      'id',v_journal_id,
      'entryNumber','MPAY-'||upper(substr(replace(v_id::text,'-',''),1,12)),
      'entryDate',now(),
      'description','Maintenance receipt '||o.order_number,
      'currency',v_currency,
      'referenceType','maintenance_payment',
      'referenceId',v_id::text,
      'maintenanceOrderId',o.id::text,
      'cashTransactionId',v_cash_transaction_id,
      'totalDebit',p_amount,
      'totalCredit',p_amount,
      'status','posted',
      'createdAt',now()
    ),
    auth.uid(),auth.uid()
  );

  insert into public.erp_journal_lines(
    company_id,id,data,created_by,updated_by
  ) values
  (
    p_company_id,gen_random_uuid()::text,
    jsonb_build_object(
      'entryId',v_journal_id,'accountId',v_cash_ledger_id,
      'currency',v_currency,'referenceType','maintenance_payment',
      'referenceId',v_id::text,'cashTransactionId',v_cash_transaction_id,
      'debit',p_amount,'credit',0,'description','Maintenance cash receipt'
    ),
    auth.uid(),auth.uid()
  ),
  (
    p_company_id,gen_random_uuid()::text,
    jsonb_build_object(
      'entryId',v_journal_id,'accountId',v_partner_account_id,
      'currency',v_currency,'referenceType','maintenance_payment',
      'referenceId',v_id::text,'cashTransactionId',v_cash_transaction_id,
      'debit',0,'credit',p_amount,'description','Customer maintenance settlement'
    ),
    auth.uid(),auth.uid()
  );

  update public.erp_maintenance_payments
  set journal_entry_id=v_journal_id,updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=v_id;

  update public.erp_maintenance_orders
  set paid_amount=v_next,
      workflow_stage=case
        when v_next+0.001>=sale_price then 'paid' else 'invoice_approved'
      end,
      status=case
        when v_next+0.001>=sale_price then 'completed' else 'approved'
      end,
      updated_at=now()
  where id=o.id;

  return v_id;
end;
$$;

create or replace function public.erp_v73_sync_deleted_maintenance_cash_payment()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_payment_id uuid;
  v_order_id uuid;
  v_paid numeric:=0;
  v_total numeric:=0;
begin
  if not old.is_deleted and new.is_deleted and lower(coalesce(
    new.data->>'referenceType',new.data->>'reference_type',''
  ))='maintenance_payment' then
    begin
      v_payment_id:=coalesce(
        new.data->>'referenceId',new.data->>'reference_id'
      )::uuid;
    exception when invalid_text_representation then
      v_payment_id:=null;
    end;

    update public.erp_maintenance_payments as p
    set is_deleted=true,deleted_at=coalesce(new.deleted_at,now()),
        updated_at=now(),updated_by=coalesce(new.updated_by,auth.uid())
    where p.company_id=new.company_id
      and not p.is_deleted
      and (
        p.id=v_payment_id
        or p.cash_transaction_id=new.id
      )
    returning p.maintenance_order_id into v_order_id;

    if v_order_id is not null then
      select coalesce(sum(p.amount_in_order_currency),0) into v_paid
      from public.erp_maintenance_payments as p
      where p.company_id=new.company_id
        and p.maintenance_order_id=v_order_id
        and not p.is_deleted;

      select o.sale_price into v_total
      from public.erp_maintenance_orders as o
      where o.company_id=new.company_id and o.id=v_order_id and not o.is_deleted
      for update;

      update public.erp_maintenance_orders
      set paid_amount=v_paid,
          workflow_stage=case
            when v_paid+0.001>=v_total and v_total>0 then 'paid'
            else 'invoice_approved'
          end,
          status=case
            when v_paid+0.001>=v_total and v_total>0 then 'completed'
            else 'approved'
          end,
          updated_at=now()
      where company_id=new.company_id and id=v_order_id and not is_deleted;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists erp_v73_sync_deleted_maintenance_cash_payment
  on public.erp_cash_transactions;
create trigger erp_v73_sync_deleted_maintenance_cash_payment
after update of is_deleted on public.erp_cash_transactions
for each row execute function public.erp_v73_sync_deleted_maintenance_cash_payment();

-- Maintenance stages are independent but remain under one maintenance order.
create or replace function public.erp_manage_maintenance_order_component(
  p_company_id uuid,
  p_order_id uuid,
  p_component_type text,
  p_action text,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.erp_maintenance_orders%rowtype;
  v_payment_count integer;
  v_target_stage text;
  v_reason text:=coalesce(nullif(btrim(p_reason),''),'Maintenance component action');
  v_journal record;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['maintenance.update','maintenance.delete']
  );

  select o.* into v_order
  from public.erp_maintenance_orders as o
  where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted
  for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;

  if p_component_type='payment' then
    raise exception 'delete_payment_from_cashbox_first';
  end if;

  if p_component_type='order' and p_action='delete' then
    return public.erp_delete_cloud_maintenance_order_v3(
      p_company_id,p_order_id,v_reason
    );
  end if;

  if p_action='approve' then
    perform public.erp_advance_cloud_maintenance_workflow(
      p_company_id,p_order_id
    );
    return jsonb_build_object(
      'ok',true,'action','approve','componentType',p_component_type,
      'linksUpdated',true
    );
  end if;

  if p_action<>'delete' then raise exception 'invalid_component_action'; end if;

  if p_component_type='invoice' then
    v_payment_count:=public.erp_v73_active_order_payment_count(
      p_company_id,'maintenance',p_order_id,null
    );
    if v_payment_count>0 then
      raise exception 'delete_payment_from_cashbox_first:%',v_payment_count;
    end if;
    v_target_stage:='stock_issue_approved';
    for v_journal in
      select je.id
      from public.erp_journal_entries as je
      where je.company_id=p_company_id
        and not je.is_deleted
        and (
          coalesce(
            je.data->>'maintenanceOrderId',
            je.data->>'maintenance_order_id',
            je.data->>'orderId',
            je.data->>'order_id'
          )=p_order_id::text
          or (
            nullif(v_order.invoice_number,'') is not null
            and coalesce(
              je.data->>'invoiceNumber',
              je.data->>'invoice_number',
              je.data->>'referenceId',
              je.data->>'reference_id'
            )=v_order.invoice_number
          )
        )
    loop
      perform public.erp_v65_soft_delete_journal(
        p_company_id,v_journal.id,v_reason
      );
    end loop;
    update public.erp_maintenance_orders
    set invoice_number=null,
        paid_amount=0,
        workflow_stage=v_target_stage,
        status='in_progress',
        updated_at=now()
    where company_id=p_company_id and id=p_order_id;
  elsif p_component_type='stock' then
    if v_order.workflow_stage in ('invoice_draft','invoice_approved','paid','closed') then
      raise exception 'delete_invoice_component_first';
    end if;
    perform public.erp_v66_reverse_maintenance_stock(
      p_company_id,p_order_id,v_reason
    );
    update public.erp_maintenance_orders
    set stock_issue_number=null,
        workflow_stage='order_approved',
        status='approved',
        updated_at=now()
    where company_id=p_company_id and id=p_order_id;
  elsif p_component_type='order_approval' then
    if v_order.workflow_stage not in ('order_approved','order_draft') then
      raise exception 'delete_downstream_components_first';
    end if;
    update public.erp_maintenance_orders
    set workflow_stage='order_draft',
        status='draft',
        updated_at=now()
    where company_id=p_company_id and id=p_order_id;
  else
    raise exception 'invalid_component_type';
  end if;

  return jsonb_build_object(
    'ok',true,'action','delete','componentType',p_component_type,
    'orderId',p_order_id,'workflowStage',v_target_stage,'linksUpdated',true
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Products can be deleted when only their original/opening balance remains.
-- ---------------------------------------------------------------------------

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
  v_sales bigint;
  v_purchases bigint;
  v_transfers bigint;
  v_non_opening bigint;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['inventory.delete']
  );

  perform 1
  from public.erp_inventory
  where company_id=p_company_id and id=p_product_id and not is_deleted
  for update;
  if not found then raise exception 'inventory_product_not_found'; end if;

  select count(*) into v_sales
  from public.erp_sales_order_items_cloud as i
  join public.erp_sales_orders_cloud as o on o.id=i.order_id
  where i.company_id=p_company_id
    and i.item_type='product'
    and i.item_id=p_product_id
    and not i.is_deleted
    and not o.is_deleted;

  select count(*) into v_purchases
  from public.erp_purchase_order_items_cloud as i
  join public.erp_purchase_orders_cloud as o on o.id=i.order_id
  where i.company_id=p_company_id
    and i.item_type='product'
    and i.item_id=p_product_id
    and not i.is_deleted
    and not o.is_deleted;

  select count(*) into v_transfers
  from public.erp_warehouse_transfer_items as i
  join public.erp_warehouse_transfers as t
    on t.company_id=i.company_id
   and t.id=coalesce(i.data->>'transferId',i.data->>'transfer_id')
  where i.company_id=p_company_id
    and not i.is_deleted
    and not t.is_deleted
    and coalesce(i.data->>'productId',i.data->>'product_id')=p_product_id;

  if v_sales+v_purchases+v_transfers>0 then
    raise exception 'delete_active_inventory_links_first:sales=%:purchases=%:transfers=%',
      v_sales,v_purchases,v_transfers;
  end if;

  if exists(
    select 1
    from public.erp_inventory_fifo_consumptions
    where company_id=p_company_id
      and item_type='product'
      and item_id=p_product_id
      and status='active'
  ) then
    raise exception 'delete_consuming_sales_documents_first';
  end if;

  select count(*) into v_non_opening
  from public.erp_inventory_movements as m
  where m.company_id=p_company_id
    and not m.is_deleted
    and coalesce(m.data->>'productId',m.data->>'product_id')=p_product_id
    and lower(coalesce(
      m.data->>'movementType',m.data->>'movement_type',''
    )) not in (
      'opening','opening_balance','initial','initial_balance',
      'opening_adjustment','initial_stock'
    );

  if v_non_opening>0 then
    raise exception 'inventory_history_not_back_to_original:%',v_non_opening;
  end if;

  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_inventory',true);
  perform set_config('qualityline.deletion_root_id',p_product_id,true);
  perform set_config(
    'qualityline.deletion_reason',
    'Delete inventory product after links returned to original/opening state',
    true
  );

  delete from public.erp_inventory_fifo_consumptions
  where company_id=p_company_id and item_type='product' and item_id=p_product_id;

  delete from public.erp_inventory_cost_layers
  where company_id=p_company_id and item_type='product' and item_id=p_product_id;

  update public.erp_inventory_movements
  set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid(),
      data=data||jsonb_build_object(
        'deletedWithProduct',true,'openingBalanceRetired',true
      )
  where company_id=p_company_id
    and not is_deleted
    and coalesce(data->>'productId',data->>'product_id')=p_product_id;

  update public.erp_product_images
  set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=p_company_id
    and coalesce(data->>'productId',data->>'product_id')=p_product_id
    and not is_deleted;

  update public.erp_warehouse_stock
  set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid(),
      data=data||jsonb_build_object(
        'deletedWithProduct',true,'openingBalanceRetired',true
      )
  where company_id=p_company_id
    and coalesce(data->>'productId',data->>'product_id')=p_product_id
    and not is_deleted;

  update public.erp_inventory_product_sales
  set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=p_company_id
    and not is_deleted
    and coalesce(data->>'productId',data->>'product_id')=p_product_id;

  update public.erp_inventory
  set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid(),
      data=data||jsonb_build_object(
        'openingBalanceRetired',true,
        'deletedAfterLinksReturnedToOriginal',true
      )
  where company_id=p_company_id and id=p_product_id and not is_deleted;
end;
$$;

-- ---------------------------------------------------------------------------
-- Accounting entries: always route to the owner or retire an orphaned journal.
-- ---------------------------------------------------------------------------

create or replace function public.erp_delete_cloud_accounting_entry(
  p_company_id uuid,
  p_entry_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_entry public.erp_journal_entries%rowtype;
  v_cash_id text;
  v_ref text;
  v_reference_id text;
  v_order_id text;
  v_reference_uuid uuid;
  v_order_uuid uuid;
  v_doc record;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['accounting.delete']
  );

  select * into v_entry
  from public.erp_journal_entries
  where company_id=p_company_id and id=p_entry_id and not is_deleted
  for update;
  if not found then return; end if;

  select ct.id into v_cash_id
  from public.erp_cash_transactions as ct
  where ct.company_id=p_company_id
    and not ct.is_deleted
    and coalesce(
      ct.data->>'journalEntryId',ct.data->>'journal_entry_id',
      ct.data->>'entryId',ct.data->>'entry_id'
    )=p_entry_id
  limit 1;
  if found then
    perform public.erp_delete_cloud_cash_transaction(p_company_id,v_cash_id);
    return;
  end if;

  v_ref:=lower(btrim(coalesce(
    nullif(v_entry.data->>'referenceType',''),
    nullif(v_entry.data->>'reference_type',''),
    'manual'
  )));
  v_reference_id:=coalesce(
    nullif(v_entry.data->>'referenceId',''),
    nullif(v_entry.data->>'reference_id',''),
    nullif(v_entry.data->>'maintenanceOrderId',''),
    nullif(v_entry.data->>'maintenance_order_id','')
  );
  v_order_id:=coalesce(
    nullif(v_entry.data->>'orderId',''),
    nullif(v_entry.data->>'order_id','')
  );

  if v_ref in ('manual','manual_journal','manual journal','قيد يدوي','') then
    perform public.erp_v65_soft_delete_journal(
      p_company_id,p_entry_id,'Delete manual accounting entry'
    );
    return;
  end if;

  if v_ref='expense' and v_reference_id is not null then
    perform public.erp_delete_cloud_expense(p_company_id,v_reference_id);
    return;
  end if;

  if v_ref in (
    'manual_cash_transaction','cash_transaction','cash receipt','cash payment',
    'receipt','payment','سند قبض','سند صرف'
  ) and v_reference_id is not null then
    perform public.erp_delete_cloud_cash_transaction(
      p_company_id,v_reference_id
    );
    return;
  end if;

  begin v_reference_uuid:=v_reference_id::uuid;
  exception when invalid_text_representation then v_reference_uuid:=null; end;
  begin v_order_uuid:=v_order_id::uuid;
  exception when invalid_text_representation then v_order_uuid:=null; end;

  if v_reference_uuid is not null then
    select d.module,d.parent_id,d.document_type into v_doc
    from public.erp_commercial_workflow_documents as d
    where d.company_id=p_company_id and d.id=v_reference_uuid and not d.is_deleted
    limit 1;

    if found then
      if public.erp_v73_active_order_payment_count(
        p_company_id,v_doc.module,v_doc.parent_id,v_reference_uuid
      )>0 then
        raise exception 'delete_payment_from_cashbox_first';
      end if;
      perform public.erp_manage_commercial_order_component(
        p_company_id,v_doc.module,v_doc.parent_id,
        case when v_doc.document_type='invoice' then 'invoice' else 'logistics' end,
        v_reference_uuid,'delete','Delete from linked accounting entry'
      );
      return;
    end if;
  end if;

  if coalesce(v_order_uuid,v_reference_uuid) is not null
     and exists(
       select 1 from public.erp_sales_orders_cloud
       where company_id=p_company_id
         and id=coalesce(v_order_uuid,v_reference_uuid)
         and not is_deleted
     ) then
    perform public.erp_delete_cloud_sales_order_v3(
      p_company_id,coalesce(v_order_uuid,v_reference_uuid)
    );
    return;
  end if;

  if coalesce(v_order_uuid,v_reference_uuid) is not null
     and exists(
       select 1 from public.erp_purchase_orders_cloud
       where company_id=p_company_id
         and id=coalesce(v_order_uuid,v_reference_uuid)
         and not is_deleted
     ) then
    perform public.erp_delete_cloud_purchase_order_v3(
      p_company_id,coalesce(v_order_uuid,v_reference_uuid)
    );
    return;
  end if;

  if coalesce(v_order_uuid,v_reference_uuid) is not null
     and exists(
       select 1 from public.erp_maintenance_orders
       where company_id=p_company_id
         and id=coalesce(v_order_uuid,v_reference_uuid)
         and not is_deleted
     ) then
    perform public.erp_delete_cloud_maintenance_order_v3(
      p_company_id,coalesce(v_order_uuid,v_reference_uuid),
      'Delete from linked accounting entry'
    );
    return;
  end if;

  -- Legacy and orphaned generated journals remain deletable after their source
  -- has already disappeared.
  perform public.erp_v65_soft_delete_journal(
    p_company_id,p_entry_id,'Delete orphaned accounting entry'
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Recycle bin: exact archive id, deleting user display name, purge fallback.
-- ---------------------------------------------------------------------------


-- Backfill legacy soft-deleted records so every visible recycle row has an
-- exact archive id and can be purged through the same implementation.
insert into public.erp_universal_recycle_bin(
  company_id,source_table,record_id,payload,deletion_mode,deleted_at,deleted_by,
  deletion_batch_id,root_source_table,root_record_id,relation_context
)
select
  case
    when r.company_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then r.company_id::uuid
    else null
  end,
  r.entity_type,
  r.record_id,
  r.payload,
  'soft',
  r.deleted_at,
  case
    when coalesce(r.payload->>'deletedBy',r.payload->>'deleted_by','')
      ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then coalesce(r.payload->>'deletedBy',r.payload->>'deleted_by')::uuid
    else null
  end,
  gen_random_uuid(),
  r.entity_type,
  r.record_id,
  jsonb_build_object(
    'legacyErpRecord',true,
    'deleteReason',coalesce(r.payload->>'deleteReason',r.payload->>'deletedReason')
  )
from public.erp_records as r
where r.deleted_at is not null
  and not exists(
    select 1
    from public.erp_universal_recycle_bin as u
    where u.source_table=r.entity_type
      and u.record_id=r.record_id
      and u.deleted_at=r.deleted_at
  );

drop function if exists public.erp_recycle_bin_list(uuid,text,text);

create function public.erp_recycle_bin_list(
  p_company_id uuid,
  p_query text default '',
  p_entity_type text default ''
)
returns table(
  archive_id text,
  entity_type text,
  record_id text,
  payload jsonb,
  deleted_at timestamptz,
  deleted_by text,
  source_table text,
  deletion_mode text,
  deletion_batch_id text,
  root_source_table text,
  root_record_id text,
  delete_reason text,
  related_count integer
)
language sql
stable
security definer
set search_path=public
as $$
  with rows as (
    select
      null::text as archive_id,
      r.entity_type,
      r.record_id,
      r.payload,
      r.deleted_at,
      coalesce(
        nullif(r.payload->>'deletedByUserName',''),
        nullif(r.payload->>'deletedBy',''),
        ''
      ) as deleted_by,
      r.entity_type as source_table,
      'soft'::text as deletion_mode,
      null::text as deletion_batch_id,
      r.entity_type as root_source_table,
      r.record_id as root_record_id,
      coalesce(r.payload->>'deleteReason',r.payload->>'deletedReason') as delete_reason,
      1::integer as related_count
    from public.erp_records as r
    where r.company_id=p_company_id::text
      and r.deleted_at is not null
      and not exists(
        select 1
        from public.erp_universal_recycle_bin as u
        where u.source_table=r.entity_type
          and u.record_id=r.record_id
          and u.deleted_at=r.deleted_at
          and u.restored_at is null
          and u.purged_at is null
      )

    union all

    select
      u.id::text as archive_id,
      u.source_table as entity_type,
      u.record_id,
      u.payload,
      u.deleted_at,
      coalesce(
        nullif(p.full_name,''),
        nullif(a.email,''),
        nullif(u.payload->>'deletedByUserName',''),
        u.deleted_by::text,
        'system'
      ) as deleted_by,
      u.source_table,
      u.deletion_mode,
      u.deletion_batch_id::text,
      coalesce(u.root_source_table,u.source_table),
      coalesce(u.root_record_id,u.record_id),
      coalesce(
        nullif(u.relation_context->>'deleteReason',''),
        nullif(u.payload->>'deleteReason',''),
        nullif(u.payload->>'deletedReason','')
      ) as delete_reason,
      case
        when u.deletion_batch_id is null then 1
        else count(*) over(partition by u.deletion_batch_id)::integer
      end as related_count
    from public.erp_universal_recycle_bin as u
    left join public.profiles as p on p.id=u.deleted_by
    left join auth.users as a on a.id=u.deleted_by
    where (u.company_id=p_company_id or u.company_id is null)
      and u.restored_at is null
      and u.purged_at is null
  )
  select
    x.archive_id,x.entity_type,x.record_id,x.payload,x.deleted_at,x.deleted_by,
    x.source_table,x.deletion_mode,x.deletion_batch_id,x.root_source_table,
    x.root_record_id,x.delete_reason,x.related_count
  from rows as x
  where public.is_company_member(p_company_id)
    and (
      coalesce(trim(p_entity_type),'')=''
      or x.entity_type=trim(p_entity_type)
    )
    and (
      coalesce(trim(p_query),'')=''
      or x.record_id ilike '%'||trim(p_query)||'%'
      or x.entity_type ilike '%'||trim(p_query)||'%'
      or x.deleted_by ilike '%'||trim(p_query)||'%'
      or x.payload::text ilike '%'||trim(p_query)||'%'
    )
  order by x.deleted_at desc;
$$;

create or replace function public.erp_recycle_bin_purge_by_archive(
  p_company_id uuid,
  p_archive_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_archive public.erp_universal_recycle_bin%rowtype;
  v_batch uuid;
  v_row record;
  v_pk text;
  v_has_company_id boolean;
  v_has_company_camel boolean;
  v_deleted integer:=0;
  v_processed integer:=0;
  v_blocked integer:=0;
  v_archives integer:=0;
begin
  if not public.is_company_member(p_company_id) then
    raise exception 'access_denied';
  end if;
  if not public.erp_cloud_user_has_permission(
    p_company_id,'settings.recycle_bin.purge'
  ) then
    raise exception 'permanent_delete_permission_required';
  end if;

  select u.* into v_archive
  from public.erp_universal_recycle_bin as u
  where u.id=p_archive_id
    and (u.company_id=p_company_id or u.company_id is null)
    and u.restored_at is null
    and u.purged_at is null
  for update;
  if not found then raise exception 'deleted_record_not_found'; end if;

  v_batch:=v_archive.deletion_batch_id;
  perform set_config('qualityline.recycle_purge','on',true);

  for v_row in
    select u.id,u.source_table,u.record_id
    from public.erp_universal_recycle_bin as u
    where (u.company_id=p_company_id or u.company_id is null)
      and u.restored_at is null
      and u.purged_at is null
      and (
        u.id=v_archive.id
        or (v_batch is not null and u.deletion_batch_id=v_batch)
      )
    order by case
      when u.source_table in (
        'erp_journal_lines','erp_inventory_fifo_consumptions'
      ) then 10
      when u.source_table in (
        'erp_maintenance_payments','erp_maintenance_parts',
        'erp_sales_order_items_cloud','erp_purchase_order_items_cloud',
        'erp_warehouse_transfer_items'
      ) then 20
      when u.source_table in (
        'erp_inventory_movements','erp_cash_transactions'
      ) then 30
      when u.source_table in (
        'erp_commercial_workflow_documents','erp_journal_entries'
      ) then 40
      else 50
    end,u.deleted_at,u.id
  loop
    begin
      v_deleted:=0;
      if to_regclass(format('public.%I',v_row.source_table)) is not null then
        select case
          when exists(
            select 1 from information_schema.columns
            where table_schema='public'
              and table_name=v_row.source_table
              and column_name='id'
          ) then 'id'
          when exists(
            select 1 from information_schema.columns
            where table_schema='public'
              and table_name=v_row.source_table
              and column_name='record_id'
          ) then 'record_id'
          else null
        end into v_pk;

        if v_pk is not null then
          select exists(
            select 1 from information_schema.columns
            where table_schema='public'
              and table_name=v_row.source_table
              and column_name='company_id'
          ) into v_has_company_id;
          select exists(
            select 1 from information_schema.columns
            where table_schema='public'
              and table_name=v_row.source_table
              and column_name='companyId'
          ) into v_has_company_camel;

          if v_has_company_id then
            execute format(
              'delete from public.%I where %I::text=$1 and company_id::text=$2',
              v_row.source_table,v_pk
            ) using v_row.record_id,p_company_id::text;
          elsif v_has_company_camel then
            execute format(
              'delete from public.%I where %I::text=$1 and "companyId"::text=$2',
              v_row.source_table,v_pk
            ) using v_row.record_id,p_company_id::text;
          else
            execute format(
              'delete from public.%I where %I::text=$1',
              v_row.source_table,v_pk
            ) using v_row.record_id;
          end if;
          get diagnostics v_deleted=row_count;
        end if;
      end if;
      v_processed:=v_processed+v_deleted;
    exception
      when foreign_key_violation then
        -- Keep referential integrity but remove the recycle payload permanently.
        -- The source row is already soft-deleted and therefore cannot return to
        -- operational screens. This is a deliberate tombstone fallback.
        v_blocked:=v_blocked+1;
    end;
  end loop;

  delete from public.erp_universal_recycle_bin as u
  where (u.company_id=p_company_id or u.company_id is null)
    and u.restored_at is null
    and u.purged_at is null
    and (
      u.id=v_archive.id
      or (v_batch is not null and u.deletion_batch_id=v_batch)
    );
  get diagnostics v_archives=row_count;

  return jsonb_build_object(
    'purged',v_archives>0,
    'archiveId',p_archive_id,
    'deletionBatchId',v_batch,
    'archiveRowsRemoved',v_archives,
    'sourceRowsDeleted',v_processed,
    'integrityTombstonesRetained',v_blocked,
    'batchPurged',v_batch is not null
  );
end;
$$;

-- Security boundaries.
revoke all on function public.erp_v73_active_order_payment_count(uuid,text,uuid,uuid) from public,anon;
revoke all on function public.erp_v73_recompute_commercial_order_status(uuid,text,uuid) from public,anon;
revoke all on function public.erp_v73_rebuild_product_warehouse_stock(uuid,text,text) from public,anon;
revoke all on function public.erp_delete_inventory_warehouse_transfer(uuid,text,text) from public,anon;
revoke all on function public.erp_delete_car_warehouse_transfer(uuid,text,text) from public,anon;
revoke all on function public.erp_delete_cloud_sales_order_v3(uuid,uuid) from public,anon;
revoke all on function public.erp_delete_cloud_purchase_order_v3(uuid,uuid) from public,anon;
revoke all on function public.erp_delete_cloud_maintenance_order_v3(uuid,uuid,text) from public,anon;
revoke all on function public.erp_manage_commercial_order_component(uuid,text,uuid,text,uuid,text,text) from public,anon;
revoke all on function public.erp_manage_maintenance_order_component(uuid,uuid,text,text,text) from public,anon;
revoke all on function public.erp_delete_inventory_product(uuid,text) from public,anon;
revoke all on function public.erp_delete_cloud_accounting_entry(uuid,text) from public,anon;
revoke all on function public.erp_recycle_bin_list(uuid,text,text) from public,anon;
revoke all on function public.erp_recycle_bin_purge_by_archive(uuid,uuid) from public,anon;

grant execute on function public.erp_v73_active_order_payment_count(uuid,text,uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_v73_recompute_commercial_order_status(uuid,text,uuid) to authenticated,service_role;
grant execute on function public.erp_v73_rebuild_product_warehouse_stock(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_delete_inventory_warehouse_transfer(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_delete_car_warehouse_transfer(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_sales_order_v3(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_purchase_order_v3(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_maintenance_order_v3(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_manage_commercial_order_component(uuid,text,uuid,text,uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_manage_maintenance_order_component(uuid,uuid,text,text,text) to authenticated,service_role;
grant execute on function public.erp_delete_inventory_product(uuid,text) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_accounting_entry(uuid,text) to authenticated,service_role;
grant execute on function public.erp_recycle_bin_list(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_recycle_bin_purge_by_archive(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_record_cloud_maintenance_payment(
  uuid,uuid,numeric,text,numeric,text
) to authenticated,service_role;

commit;
