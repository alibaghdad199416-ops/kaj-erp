begin;

-- R95.1: continue the backend granular-action contract for the active
-- commercial logistics and invoice-draft stages.  The R95 helper is the single
-- authorization decision: unrestricted companies retain the historical broad
-- permissions; restricted companies require the exact document action.

create or replace function public.erp_approve_cloud_purchase_receipt(
  p_company_id uuid,p_receipt_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  a record;
  s public.erp_warehouse_stock%rowtype;
  v_alloc jsonb;
  v_qty numeric;
begin
  if not public.erp_r95_user_can_perform_action(
    p_company_id,
    'purchases.actions.restrict',
    'purchases.receipt.approve',
    array['purchases.approve','purchases.update','purchases.create']
  ) then
    raise exception 'permission_denied:purchases.receipt.approve' using errcode='42501';
  end if;

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
      perform 1 from public.erp_cars
       where company_id=p_company_id and id=a."itemId" and not is_deleted for update;
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
  perform public.erp_commercial_audit(
    p_company_id,'purchases',d.parent_id,d.id,d.document_number,
    'approve_receipt',d.status,'approved','quantity-only; valuation owned by invoice');
end;
$$;

create or replace function public.erp_approve_cloud_sales_delivery(
  p_company_id uuid,p_delivery_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare
  d public.erp_commercial_workflow_documents%rowtype;
  a record;
  s public.erp_warehouse_stock%rowtype;
  v_alloc jsonb;
  v_available numeric;
  v_cost numeric;
begin
  if not public.erp_r95_user_can_perform_action(
    p_company_id,
    'sales.actions.restrict',
    'sales.delivery.approve',
    array['sales.approve','sales.update','sales.create']
  ) then
    raise exception 'permission_denied:sales.delivery.approve' using errcode='42501';
  end if;

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
      v_available:=public.erp_try_numeric(s.data->>'quantity',0)
        -public.erp_try_numeric(s.data->>'reservedQuantity',0);
      if v_available<a.quantity then
        raise exception 'sales_insufficient_stock:%',a."description";
      end if;
      v_cost:=public.erp_try_numeric(
        s.data->>'averageUnitCost',public.erp_try_numeric(s.data->>'unitCost',0));
      update public.erp_warehouse_stock set data=data||jsonb_build_object(
        'quantity',public.erp_try_numeric(data->>'quantity',0)-a.quantity,
        'updatedAt',now()),updated_at=now(),updated_by=auth.uid()
      where id=s.id;
      perform public.erp_inventory_insert_movement(
        p_company_id,a."itemId",a."warehouseId",'sale_out',-a.quantity,v_cost,
        'sales_delivery',d.id::text,d.document_number);
      perform public.erp_inventory_refresh_product(p_company_id,a."itemId");
    else
      perform 1 from public.erp_cars
       where company_id=p_company_id and id=a."itemId" and not is_deleted
         and coalesce(data->>'warehouseId',data->>'warehouse_id')=a."warehouseId"
       for update;
      if not found then raise exception 'sales_car_not_available:%',a."itemId"; end if;
      update public.erp_cars set data=(data-'warehouseId'-'warehouse_id')||jsonb_build_object(
        'status','قيد البيع','salesOrderId',d.parent_id::text,
        'lastWarehouseId',a."warehouseId",'deliveredAt',now(),
        'salesDeliveryId',d.id::text,'sourceSalesOrderId',d.parent_id::text,
        'valuationPendingInvoice',true,'updatedAt',now()),updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=a."itemId";
    end if;
  end loop;

  update public.erp_commercial_workflow_documents set status='approved',
    payload=(payload-'costJournalEntryId'-'fifoCostJournalEntryId')||jsonb_build_object(
      'allocations',v_alloc,'inventoryPostedAt',now(),'inventoryPostedBy',auth.uid(),
      'valuationPendingInvoice',true,'accountingOwner','invoice'),updated_at=now()
  where company_id=p_company_id and id=p_delivery_id;
  perform public.erp_commercial_audit(
    p_company_id,'sales',d.parent_id,d.id,d.document_number,
    'approve_delivery',d.status,'approved','quantity-only; valuation owned by invoice');
end;
$$;

create or replace function public.erp_create_cloud_sales_workflow_invoice(
  p_company_id uuid,p_order_id uuid
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  v_id uuid:=gen_random_uuid();
  v_existing uuid;
  o public.erp_sales_orders_cloud%rowtype;
  l jsonb;
  v_number text;
  v_preflight_warning text;
begin
  if not public.erp_r95_user_can_perform_action(
    p_company_id,
    'sales.actions.restrict',
    'sales.invoice.create',
    array['sales.create','sales.update','sales.approve']
  ) then
    raise exception 'permission_denied:sales.invoice.create' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(
    hashtextextended(p_company_id::text||':sales-invoice:'||p_order_id::text,0));

  select * into o
  from public.erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id
    and lower(coalesce(status,'')) in ('approved','partially_executed','completed','confirmed')
    and not is_deleted
  for update;
  if not found then raise exception 'approved_sales_order_required'; end if;

  select id into v_existing
  from public.erp_commercial_workflow_documents
  where company_id=p_company_id and parent_id=p_order_id
    and module='sales' and document_type='invoice'
    and not is_deleted and lower(coalesce(status,'')) not in ('cancelled','deleted')
  order by created_at desc limit 1;
  if v_existing is not null then return v_existing; end if;

  l:=public.erp_v758_active_logistics(p_company_id,p_order_id,'sales');
  begin
    perform public.erp_v749_prepare_order_invoice_accounts(
      p_company_id,'sales',p_order_id,o.currency);
  exception when others then
    v_preflight_warning:=sqlstate||':'||sqlerrm;
  end;

  v_number:=public.erp_next_document_number(
    p_company_id,'sales_invoice','SI',coalesce(o.effective_at,o.created_at));
  insert into public.erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,payload,effective_at
  ) values(
    v_id,p_company_id,'sales','invoice',p_order_id,v_number,
    jsonb_strip_nulls(jsonb_build_object(
      'currency',upper(o.currency),'totalAmount',o.total,
      'paidAmount',0,'remainingAmount',o.total,'paymentStatus','unpaid',
      'payments','[]'::jsonb,'createdBy',auth.uid(),
      'logisticsDocumentId',l->>'id','logisticsDocumentNumber',l->>'number',
      'allocations',l->'allocations','warehouseIds',l->'warehouseIds',
      'accountingOwner','invoice','currencyPreparedAt',now(),
      'accountPreflightWarning',v_preflight_warning
    )),coalesce(o.effective_at,o.created_at)
  );
  perform public.erp_commercial_audit(
    p_company_id,'sales',p_order_id,v_id,v_number,
    'create_invoice',null,'draft','resilient invoice draft creation');
  return v_id;
end;
$$;

create or replace function public.erp_create_cloud_purchase_workflow_invoice(
  p_company_id uuid,p_order_id uuid
) returns uuid
language plpgsql security definer set search_path=public as $$
declare
  v_id uuid:=gen_random_uuid();
  v_existing uuid;
  o public.erp_purchase_orders_cloud%rowtype;
  l jsonb;
  v_number text;
  v_preflight_warning text;
begin
  if not public.erp_r95_user_can_perform_action(
    p_company_id,
    'purchases.actions.restrict',
    'purchases.invoice.create',
    array['purchases.create','purchases.update','purchases.approve']
  ) then
    raise exception 'permission_denied:purchases.invoice.create' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(
    hashtextextended(p_company_id::text||':purchase-invoice:'||p_order_id::text,0));

  select * into o
  from public.erp_purchase_orders_cloud
  where company_id=p_company_id and id=p_order_id
    and lower(coalesce(status,'')) in ('approved','partially_executed','completed','confirmed')
    and not is_deleted
  for update;
  if not found then raise exception 'approved_purchase_order_required'; end if;

  select id into v_existing
  from public.erp_commercial_workflow_documents
  where company_id=p_company_id and parent_id=p_order_id
    and module='purchases' and document_type='invoice'
    and not is_deleted and lower(coalesce(status,'')) not in ('cancelled','deleted')
  order by created_at desc limit 1;
  if v_existing is not null then return v_existing; end if;

  l:=public.erp_v758_active_logistics(p_company_id,p_order_id,'purchases');
  begin
    perform public.erp_v749_prepare_order_invoice_accounts(
      p_company_id,'purchases',p_order_id,o.currency);
  exception when others then
    v_preflight_warning:=sqlstate||':'||sqlerrm;
  end;

  v_number:=public.erp_next_document_number(
    p_company_id,'purchase_invoice','PI',coalesce(o.effective_at,o.created_at));
  insert into public.erp_commercial_workflow_documents(
    id,company_id,module,document_type,parent_id,document_number,payload,effective_at
  ) values(
    v_id,p_company_id,'purchases','invoice',p_order_id,v_number,
    jsonb_strip_nulls(jsonb_build_object(
      'currency',upper(o.currency),'totalAmount',o.total,
      'paidAmount',0,'remainingAmount',o.total,'paymentStatus','unpaid',
      'payments','[]'::jsonb,'createdBy',auth.uid(),
      'logisticsDocumentId',l->>'id','logisticsDocumentNumber',l->>'number',
      'allocations',l->'allocations','warehouseIds',l->'warehouseIds',
      'accountingOwner','invoice','currencyPreparedAt',now(),
      'accountPreflightWarning',v_preflight_warning
    )),coalesce(o.effective_at,o.created_at)
  );
  perform public.erp_commercial_audit(
    p_company_id,'purchases',p_order_id,v_id,v_number,
    'create_invoice',null,'draft','resilient invoice draft creation');
  return v_id;
end;
$$;

-- Reassert the active browser surfaces after replacement.
revoke all on function public.erp_approve_cloud_purchase_receipt(uuid,uuid) from public,anon;
revoke all on function public.erp_approve_cloud_sales_delivery(uuid,uuid) from public,anon;
revoke all on function public.erp_create_cloud_sales_workflow_invoice(uuid,uuid) from public,anon;
revoke all on function public.erp_create_cloud_purchase_workflow_invoice(uuid,uuid) from public,anon;

grant execute on function public.erp_approve_cloud_purchase_receipt(uuid,uuid)
  to authenticated,service_role;
grant execute on function public.erp_approve_cloud_sales_delivery(uuid,uuid)
  to authenticated,service_role;
grant execute on function public.erp_create_cloud_sales_workflow_invoice(uuid,uuid)
  to authenticated,service_role;
grant execute on function public.erp_create_cloud_purchase_workflow_invoice(uuid,uuid)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
