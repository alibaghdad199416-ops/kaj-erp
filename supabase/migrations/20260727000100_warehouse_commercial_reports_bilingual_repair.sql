begin;

-- ---------------------------------------------------------------------------
-- Canonical, atomic warehouse transfers.
-- ---------------------------------------------------------------------------
create or replace function public.erp_create_car_warehouse_transfer(
  p_company_id uuid, p_car_id text, p_to_warehouse_id text,
  p_user_name text, p_notes text default null
) returns text language plpgsql security definer set search_path=public as $$
declare
  v_car public.erp_cars%rowtype;
  v_wh public.erp_warehouses%rowtype;
  v_id text:=gen_random_uuid()::text;
  v_now timestamptz:=clock_timestamp();
  v_from text;
  v_status text;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  select * into v_car from public.erp_cars
  where company_id=p_company_id and id=p_car_id and not is_deleted for update;
  if not found then raise exception 'السيارة غير موجودة'; end if;
  v_status:=lower(btrim(coalesce(v_car.data->>'status','')));
  if v_status not in ('available','متوفرة','متوفر','متاحة') then
    raise exception 'لا يمكن نقل السيارة إلا عندما تكون متوفرة وغير مرتبطة بأمر بيع';
  end if;
  v_from:=nullif(btrim(coalesce(v_car.data->>'warehouseId',v_car.data->>'warehouse_id','')),'');
  if v_from is null then raise exception 'السيارة غير مرتبطة بمخزن حالي'; end if;
  if v_from=p_to_warehouse_id then raise exception 'يجب اختيار مخزن مختلف'; end if;
  if nullif(btrim(coalesce(v_car.data->>'salesOrderId','')),'') is not null then
    raise exception 'السيارة مرتبطة بأمر بيع ولا يمكن نقلها';
  end if;
  select * into v_wh from public.erp_warehouses
  where company_id=p_company_id and id=p_to_warehouse_id and not is_deleted
    and public.erp_try_boolean(data->>'isActive',true) for share;
  if not found then raise exception 'المخزن الهدف غير موجود أو غير فعال'; end if;

  insert into public.erp_car_warehouse_transfers(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_id,jsonb_build_object(
    'transferNumber','CT-'||to_char(v_now,'YYYYMMDDHH24MISSMS'),
    'carId',p_car_id,'fromWarehouseId',v_from,'toWarehouseId',p_to_warehouse_id,
    'transferDate',v_now,'status','completed','notes',p_notes,'createdAt',v_now,
    'createdByUserId',auth.uid()::text,'createdByUserName',p_user_name
  ),auth.uid(),auth.uid());

  update public.erp_cars
  set data=(data-'warehouseId'-'warehouse_id'-'updated_at')||jsonb_build_object(
        'warehouseId',p_to_warehouse_id,'warehouse_id',p_to_warehouse_id,
        'updatedAt',v_now,'updated_at',v_now),
      updated_at=v_now,updated_by=auth.uid()
  where company_id=p_company_id and id=p_car_id;
  return v_id;
end;
$$;

create or replace function public.erp_update_car_warehouse_transfer(
  p_company_id uuid,p_transfer_id text,p_to_warehouse_id text,
  p_user_name text,p_notes text default null
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_t public.erp_car_warehouse_transfers%rowtype;
  v_car public.erp_cars%rowtype;
  v_now timestamptz:=clock_timestamp();
  v_current text;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  select * into v_t from public.erp_car_warehouse_transfers
  where company_id=p_company_id and id=p_transfer_id and not is_deleted for update;
  if not found then raise exception 'سند النقل غير موجود'; end if;
  if v_t.data->>'status'<>'completed' then raise exception 'لا يمكن تعديل سند مُرجع'; end if;
  select * into v_car from public.erp_cars
  where company_id=p_company_id and id=v_t.data->>'carId' and not is_deleted for update;
  if not found then raise exception 'السيارة غير موجودة'; end if;
  v_current:=nullif(btrim(coalesce(v_car.data->>'warehouseId',v_car.data->>'warehouse_id','')),'');
  if v_current<>v_t.data->>'toWarehouseId' then
    raise exception 'تعذر التعديل لأن السيارة نُقلت بحركة لاحقة';
  end if;
  if lower(btrim(coalesce(v_car.data->>'status',''))) not in
       ('available','متوفرة','متوفر','متاحة')
     or nullif(btrim(coalesce(v_car.data->>'salesOrderId','')),'') is not null then
    raise exception 'لا يمكن تعديل النقل لأن السيارة دخلت في مسار بيع';
  end if;
  if p_to_warehouse_id=v_t.data->>'fromWarehouseId' then
    raise exception 'استخدم إرجاع النقل لإعادة السيارة إلى مخزن المصدر';
  end if;
  perform 1 from public.erp_warehouses
  where company_id=p_company_id and id=p_to_warehouse_id and not is_deleted
    and public.erp_try_boolean(data->>'isActive',true) for share;
  if not found then raise exception 'المخزن الهدف غير موجود أو غير فعال'; end if;

  update public.erp_car_warehouse_transfers
  set data=data||jsonb_build_object(
        'toWarehouseId',p_to_warehouse_id,'notes',p_notes,'updatedAt',v_now,
        'updatedByUserId',auth.uid()::text,'updatedByUserName',p_user_name),
      updated_at=v_now,updated_by=auth.uid()
  where company_id=p_company_id and id=p_transfer_id;
  update public.erp_cars
  set data=(data-'warehouseId'-'warehouse_id')||jsonb_build_object(
        'warehouseId',p_to_warehouse_id,'warehouse_id',p_to_warehouse_id,'updatedAt',v_now),
      updated_at=v_now,updated_by=auth.uid()
  where company_id=p_company_id and id=v_t.data->>'carId';
end;
$$;

create or replace function public.erp_reverse_car_warehouse_transfer(
  p_company_id uuid,p_transfer_id text,p_user_name text
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_t public.erp_car_warehouse_transfers%rowtype;
  v_car public.erp_cars%rowtype;
  v_now timestamptz:=clock_timestamp();
  v_current text;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  select * into v_t from public.erp_car_warehouse_transfers
  where company_id=p_company_id and id=p_transfer_id and not is_deleted for update;
  if not found then raise exception 'سند النقل غير موجود'; end if;
  if v_t.data->>'status'<>'completed' then raise exception 'تم إرجاع هذا النقل مسبقاً'; end if;
  select * into v_car from public.erp_cars
  where company_id=p_company_id and id=v_t.data->>'carId' and not is_deleted for update;
  if not found then raise exception 'السيارة غير موجودة'; end if;
  v_current:=nullif(btrim(coalesce(v_car.data->>'warehouseId',v_car.data->>'warehouse_id','')),'');
  if v_current<>v_t.data->>'toWarehouseId' then
    raise exception 'لا يمكن الإرجاع لوجود حركة مخزنية لاحقة';
  end if;
  if lower(btrim(coalesce(v_car.data->>'status',''))) not in ('available','متوفرة','متوفر','متاحة')
     or nullif(btrim(coalesce(v_car.data->>'salesOrderId','')),'') is not null then
    raise exception 'لا يمكن إرجاع النقل لأن السيارة دخلت في مسار بيع';
  end if;
  update public.erp_cars
  set data=(data-'warehouseId'-'warehouse_id')||jsonb_build_object(
        'warehouseId',v_t.data->>'fromWarehouseId',
        'warehouse_id',v_t.data->>'fromWarehouseId','updatedAt',v_now),
      updated_at=v_now,updated_by=auth.uid()
  where company_id=p_company_id and id=v_t.data->>'carId';
  update public.erp_car_warehouse_transfers
  set data=data||jsonb_build_object(
        'status','reversed','reversedAt',v_now,'reversedByUserId',auth.uid()::text,
        'reversedByUserName',p_user_name),updated_at=v_now,updated_by=auth.uid()
  where company_id=p_company_id and id=p_transfer_id;
end;
$$;

create or replace function public.erp_transfer_inventory_stock(
  p_company_id uuid,p_product_id text,p_from_warehouse_id text,
  p_to_warehouse_id text,p_quantity integer,p_notes text default null
) returns text language plpgsql security definer set search_path=public as $$
declare
  v_from public.erp_warehouse_stock%rowtype;
  v_to public.erp_warehouse_stock%rowtype;
  v_id text:=gen_random_uuid()::text;
  v_item text:=gen_random_uuid()::text;
  v_now timestamptz:=clock_timestamp();
  v_on_hand numeric; v_reserved numeric; v_available numeric;
  v_cost numeric; v_to_qty numeric; v_to_avg numeric; v_new_avg numeric;
begin
  if not public.can_manage_master_data(p_company_id) then raise exception 'access denied'; end if;
  if p_from_warehouse_id=p_to_warehouse_id then raise exception 'يجب اختيار مخزنين مختلفين'; end if;
  if coalesce(p_quantity,0)<=0 then raise exception 'يجب أن تكون الكمية أكبر من صفر'; end if;
  perform 1 from public.erp_inventory
  where company_id=p_company_id and id=p_product_id and not is_deleted
    and public.erp_try_boolean(data->>'isActive',true) for share;
  if not found then raise exception 'المنتج غير موجود أو غير فعال'; end if;
  if (select count(*) from public.erp_warehouses
      where company_id=p_company_id and id in (p_from_warehouse_id,p_to_warehouse_id)
        and not is_deleted and public.erp_try_boolean(data->>'isActive',true))<>2 then
    raise exception 'مخزن المصدر أو الهدف غير موجود أو غير فعال';
  end if;

  select * into v_from from public.erp_warehouse_stock
  where company_id=p_company_id and not is_deleted
    and data->>'warehouseId'=p_from_warehouse_id and data->>'productId'=p_product_id
  order by updated_at desc limit 1;
  if not found then raise exception 'المنتج غير موجود في مخزن المصدر'; end if;

  v_to:=public.erp_inventory_ensure_stock(
    p_company_id,p_to_warehouse_id,p_product_id
  );

  -- Lock both balances in a stable order. This prevents lost updates when two
  -- browsers transfer into the same destination, and minimizes deadlocks for
  -- opposite-direction transfers.
  perform 1 from public.erp_warehouse_stock
  where company_id=p_company_id and id in (v_from.id,v_to.id)
  order by id for update;

  select * into v_from from public.erp_warehouse_stock
  where company_id=p_company_id and id=v_from.id and not is_deleted;
  select * into v_to from public.erp_warehouse_stock
  where company_id=p_company_id and id=v_to.id and not is_deleted;

  v_on_hand:=public.erp_try_numeric(v_from.data->>'quantity',0);
  v_reserved:=public.erp_try_numeric(v_from.data->>'reservedQuantity',0);
  v_available:=greatest(0,v_on_hand-v_reserved);
  if v_available<p_quantity then
    raise exception 'الرصيد القابل للنقل في مخزن المصدر غير كافٍ (المتاح: %)',v_available;
  end if;
  v_cost:=public.erp_try_numeric(v_from.data->>'averageUnitCost',0);
  v_to_qty:=public.erp_try_numeric(v_to.data->>'quantity',0);
  v_to_avg:=public.erp_try_numeric(v_to.data->>'averageUnitCost',0);
  v_new_avg:=case when v_to_qty+p_quantity>0
    then ((v_to_qty*v_to_avg)+(p_quantity*v_cost))/(v_to_qty+p_quantity)
    else v_cost end;

  insert into public.erp_warehouse_transfers(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_id,jsonb_build_object(
    'transferNumber','TR-'||to_char(v_now,'YYYYMMDDHH24MISSMS'),
    'fromWarehouseId',p_from_warehouse_id,'toWarehouseId',p_to_warehouse_id,
    'transferDate',v_now,'status','completed','notes',p_notes,'createdAt',v_now
  ),auth.uid(),auth.uid());
  insert into public.erp_warehouse_transfer_items(company_id,id,data,created_by,updated_by)
  values(p_company_id,v_item,jsonb_build_object(
    'transferId',v_id,'productId',p_product_id,'quantity',p_quantity,'unitCost',v_cost
  ),auth.uid(),auth.uid());
  update public.erp_warehouse_stock
  set data=data||jsonb_build_object('quantity',v_on_hand-p_quantity,'updatedAt',v_now),
      updated_at=v_now,updated_by=auth.uid()
  where company_id=p_company_id and id=v_from.id;
  update public.erp_warehouse_stock
  set data=data||jsonb_build_object(
        'quantity',v_to_qty+p_quantity,'averageUnitCost',round(v_new_avg,4),'updatedAt',v_now),
      updated_at=v_now,updated_by=auth.uid()
  where company_id=p_company_id and id=v_to.id;
  perform public.erp_inventory_insert_movement(p_company_id,p_product_id,p_from_warehouse_id,
    'transfer_out',-p_quantity,v_cost,'warehouse_transfer',v_id,p_notes);
  perform public.erp_inventory_insert_movement(p_company_id,p_product_id,p_to_warehouse_id,
    'transfer_in',p_quantity,v_cost,'warehouse_transfer',v_id,p_notes);
  perform public.erp_inventory_refresh_product(p_company_id,p_product_id);
  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Edit catalogs include the current order's linked rows, even when reserved.
-- ---------------------------------------------------------------------------
create or replace function public.erp_cloud_purchase_order_edit_catalog(
  p_company_id uuid,p_order_id uuid
) returns setof jsonb language sql security definer set search_path=public as $$
  with regular(value) as (
    select value
    from public.erp_cloud_purchase_order_catalog(p_company_id) as catalog(value)
  ), current_rows as (
    select jsonb_build_object(
      'itemType',x.item_type,'id',x.item_id,'description',x.description,
      'baseCost',x.unit_cost,'imagePath',coalesce(c.data->>'imagePath',i.data->>'imagePath'),
      'details',coalesce(c.data,i.data,'{}'::jsonb)||jsonb_build_object(
        'id',x.item_id,'includedByOrderId',p_order_id::text)
    ) value
    from public.erp_purchase_order_items_cloud x
    left join public.erp_cars c on x.item_type='car' and c.company_id=x.company_id and c.id=x.item_id and not c.is_deleted
    left join public.erp_inventory i on x.item_type='product' and i.company_id=x.company_id and i.id=x.item_id and not i.is_deleted
    where x.company_id=p_company_id and x.order_id=p_order_id and not x.is_deleted
      and public.erp_is_company_member(p_company_id)
  )
  select value from current_rows
  union all
  select r.value from regular r
  where not exists(select 1 from current_rows c
    where c.value->>'itemType'=r.value->>'itemType'
      and c.value->>'id'=r.value->>'id');
$$;

create or replace function public.erp_cloud_sales_order_edit_catalog(
  p_company_id uuid,p_order_id uuid
) returns setof jsonb language sql security definer set search_path=public as $$
  with posted as (
    select exists(select 1 from public.erp_commercial_workflow_documents d
      where d.company_id=p_company_id and d.parent_id=p_order_id and d.module='sales'
        and d.document_type='delivery' and not d.is_deleted and d.status<>'cancelled'
        and d.payload ? 'inventoryPostedAt') value
  ), regular(value) as (
    select value
    from public.erp_cloud_sales_order_catalog(p_company_id) as catalog(value)
  ), current_rows as (
    select jsonb_build_object(
      'itemType',x.item_type,'id',x.item_id,'description',x.description,
      'availableQuantity',case when x.item_type='car' then 1 else
        greatest(x.quantity,
          coalesce((select sum(public.erp_try_numeric(ws.data->>'quantity',0)-public.erp_try_numeric(ws.data->>'reservedQuantity',0))
                    from public.erp_warehouse_stock ws
                    where ws.company_id=p_company_id and not ws.is_deleted and ws.data->>'productId'=x.item_id),0)
          +case when (select value from posted) then x.quantity else 0 end)
        end,
      'basePrice',x.unit_price,'imagePath',coalesce(c.data->>'imagePath',i.data->>'imagePath'),
      'details',coalesce(c.data,i.data,'{}'::jsonb)||jsonb_build_object(
        'id',x.item_id,'includedByOrderId',p_order_id::text)
    ) value
    from public.erp_sales_order_items_cloud x
    left join public.erp_cars c on x.item_type='car' and c.company_id=x.company_id and c.id=x.item_id and not c.is_deleted
    left join public.erp_inventory i on x.item_type='product' and i.company_id=x.company_id and i.id=x.item_id and not i.is_deleted
    where x.company_id=p_company_id and x.order_id=p_order_id and not x.is_deleted
      and public.erp_is_company_member(p_company_id)
  )
  select value from current_rows
  union all
  select r.value from regular r
  where not exists(select 1 from current_rows c
    where c.value->>'itemType'=r.value->>'itemType'
      and c.value->>'id'=r.value->>'id');
$$;

-- ---------------------------------------------------------------------------
-- Atomic edit/delete of a commercial order and all linked documents.
-- ---------------------------------------------------------------------------
create or replace function public.erp_reverse_cloud_workflow_invoice_payments(
  p_company_id uuid,p_invoice_id uuid,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_doc public.erp_commercial_workflow_documents%rowtype;
  v_payments jsonb;
  v_payment jsonb;
  v_journal text;
  v_cash text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select * into v_doc from public.erp_commercial_workflow_documents
  where company_id=p_company_id and id=p_invoice_id and document_type='invoice'
    and not is_deleted for update;
  if not found then raise exception 'الفاتورة غير موجودة'; end if;
  v_payments:=coalesce(v_doc.payload->'payments','[]'::jsonb);
  for v_payment in select value from jsonb_array_elements(v_payments) loop
    v_journal:=nullif(v_payment->>'journalEntryId','');
    v_cash:=nullif(v_payment->>'cashTransactionId','');
    if v_journal is not null then
      update public.erp_journal_lines set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and not is_deleted and data->>'entryId'=v_journal;
      update public.erp_journal_entries set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=v_journal and not is_deleted;
    end if;
    if v_cash is not null then
      update public.erp_cash_transactions set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=v_cash and not is_deleted;
    end if;
  end loop;
  update public.erp_commercial_workflow_documents
  set payload=jsonb_set(jsonb_set(jsonb_set(
        payload||jsonb_build_object('paymentsReversedAt',now(),'paymentsReversalReason',p_reason),
        '{payments}','[]'::jsonb),
        '{paidAmount}','0'::jsonb),
        '{remainingAmount}',to_jsonb(public.erp_try_numeric(payload->>'totalAmount',0)))
        ||jsonb_build_object('paymentStatus','unpaid'),
      updated_at=now()
  where company_id=p_company_id and id=p_invoice_id;
  perform public.erp_commercial_audit(p_company_id,v_doc.module,v_doc.parent_id,v_doc.id,
    v_doc.document_number,'reverse_invoice_payments',v_doc.status,v_doc.status,p_reason);
  return v_payments;
end;
$$;

create or replace function public.erp_prepare_commercial_order_change(
  p_company_id uuid,p_order_id uuid,p_module text,p_reason text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_order_status text;
  v_logistics public.erp_commercial_workflow_documents%rowtype;
  v_invoice public.erp_commercial_workflow_documents%rowtype;
  v_payments jsonb:='[]'::jsonb;
  v_result jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied';
  end if;
  if p_module='sales' then
    select status into v_order_status from public.erp_sales_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  elsif p_module='purchases' then
    select status into v_order_status from public.erp_purchase_orders_cloud
    where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  else raise exception 'invalid workflow module';
  end if;
  if not found then raise exception 'الأمر غير موجود'; end if;

  if (select count(*) from public.erp_commercial_workflow_documents
      where company_id=p_company_id and parent_id=p_order_id and module=p_module
        and document_type=case when p_module='sales' then 'delivery' else 'receipt' end
        and not is_deleted and status<>'cancelled')>1 then
    raise exception 'يوجد أكثر من مستند مخزني فعال مرتبط بالأمر؛ يجب معالجة التكرار قبل التعديل أو الحذف';
  end if;
  if (select count(*) from public.erp_commercial_workflow_documents
      where company_id=p_company_id and parent_id=p_order_id and module=p_module
        and document_type='invoice' and not is_deleted and status<>'cancelled')>1 then
    raise exception 'يوجد أكثر من فاتورة فعالة مرتبطة بالأمر؛ يجب معالجة التكرار قبل التعديل أو الحذف';
  end if;

  select * into v_logistics from public.erp_commercial_workflow_documents
  where company_id=p_company_id and parent_id=p_order_id and module=p_module
    and document_type=case when p_module='sales' then 'delivery' else 'receipt' end
    and not is_deleted and status<>'cancelled' order by created_at desc limit 1 for update;
  select * into v_invoice from public.erp_commercial_workflow_documents
  where company_id=p_company_id and parent_id=p_order_id and module=p_module
    and document_type='invoice' and not is_deleted and status<>'cancelled'
  order by created_at desc limit 1 for update;

  v_result:=jsonb_build_object(
    'orderStatus',v_order_status,
    'logistics',case when v_logistics.id is null then null else jsonb_build_object(
      'id',v_logistics.id,'status',v_logistics.status,'warehouseId',v_logistics.warehouse_id,
      'notes',v_logistics.payload->>'notes') end,
    'invoice',case when v_invoice.id is null then null else jsonb_build_object(
      'id',v_invoice.id,'status',v_invoice.status) end,
    'payments','[]'::jsonb
  );

  if v_invoice.id is not null then
    v_payments:=public.erp_reverse_cloud_workflow_invoice_payments(
      p_company_id,v_invoice.id,coalesce(p_reason,'تعديل الأمر المرتبط'));
    if p_module='sales' then
      perform public.erp_cancel_cloud_sales_workflow_invoice(p_company_id,v_invoice.id,p_reason);
    else
      perform public.erp_cancel_cloud_purchase_workflow_invoice(p_company_id,v_invoice.id,p_reason);
    end if;
    v_result:=jsonb_set(v_result,'{payments}',v_payments,true);
  end if;
  if v_logistics.id is not null then
    if p_module='sales' then
      perform public.erp_cancel_cloud_sales_delivery(p_company_id,v_logistics.id);
    else
      perform public.erp_cancel_cloud_purchase_receipt(p_company_id,v_logistics.id);
    end if;
  end if;
  if v_order_status='approved' then
    if p_module='sales' then
      perform public.erp_reopen_cloud_sales_order(p_company_id,p_order_id);
    else
      perform public.erp_reopen_cloud_purchase_order(p_company_id,p_order_id);
    end if;
  elsif v_order_status<>'draft' then
    raise exception 'حالة الأمر لا تسمح بالتعديل أو الحذف';
  end if;
  return v_result;
end;
$$;

create or replace function public.erp_restore_commercial_order_links(
  p_company_id uuid,p_order_id uuid,p_module text,p_snapshot jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_logistics jsonb:=p_snapshot->'logistics';
  v_invoice jsonb:=p_snapshot->'invoice';
  v_payments jsonb:=coalesce(p_snapshot->'payments','[]'::jsonb);
  v_payment jsonb;
  v_logistics_id uuid;
  v_invoice_id uuid;
  v_order_status text:=p_snapshot->>'orderStatus';
begin
  if v_order_status='approved' or v_logistics is not null or v_invoice is not null then
    if p_module='sales' then perform public.erp_approve_cloud_sales_order(p_company_id,p_order_id);
    else perform public.erp_approve_cloud_purchase_order(p_company_id,p_order_id); end if;
  end if;
  if v_logistics is not null then
    if p_module='sales' then
      v_logistics_id:=public.erp_create_cloud_sales_delivery(
        p_company_id,p_order_id,v_logistics->>'warehouseId',v_logistics->>'notes');
      if v_logistics->>'status'='approved' then
        perform public.erp_approve_cloud_sales_delivery(p_company_id,v_logistics_id);
      end if;
    else
      v_logistics_id:=public.erp_create_cloud_purchase_receipt(
        p_company_id,p_order_id,v_logistics->>'warehouseId',v_logistics->>'notes');
      if v_logistics->>'status'='approved' then
        perform public.erp_approve_cloud_purchase_receipt(p_company_id,v_logistics_id);
      end if;
    end if;
  end if;
  if v_invoice is not null then
    if p_module='sales' then
      v_invoice_id:=public.erp_create_cloud_sales_workflow_invoice(p_company_id,p_order_id);
      if v_invoice->>'status'='approved' then
        perform public.erp_approve_cloud_sales_workflow_invoice(p_company_id,v_invoice_id);
      end if;
    else
      v_invoice_id:=public.erp_create_cloud_purchase_workflow_invoice(p_company_id,p_order_id);
      if v_invoice->>'status'='approved' then
        perform public.erp_approve_cloud_purchase_workflow_invoice(p_company_id,v_invoice_id);
      end if;
    end if;
    if jsonb_array_length(v_payments)>0 and v_invoice->>'status'<>'approved' then
      raise exception 'لا يمكن إعادة الدفعات إلى فاتورة غير مصدقة';
    end if;
    for v_payment in select value from jsonb_array_elements(v_payments) loop
      if p_module='sales' then
        perform public.erp_pay_cloud_sales_workflow_invoice(p_company_id,v_invoice_id,v_payment);
      else
        perform public.erp_pay_cloud_purchase_workflow_invoice(p_company_id,v_invoice_id,v_payment);
      end if;
    end loop;
  end if;
  return jsonb_build_object('orderId',p_order_id,'logisticsId',v_logistics_id,'invoiceId',v_invoice_id);
end;
$$;

create or replace function public.erp_update_cloud_purchase_order_with_links(
  p_company_id uuid,p_order_id uuid,p_supplier_id text,p_currency text,
  p_exchange_rate numeric,p_discount numeric,p_items jsonb,p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_snapshot jsonb; v_result jsonb;
begin
  v_snapshot:=public.erp_prepare_commercial_order_change(
    p_company_id,p_order_id,'purchases','تعديل أمر الشراء وإعادة ربط مستنداته');
  perform public.erp_update_cloud_purchase_order(p_company_id,p_order_id,p_supplier_id,
    p_currency,p_exchange_rate,p_discount,p_items,p_notes);
  v_result:=public.erp_restore_commercial_order_links(p_company_id,p_order_id,'purchases',v_snapshot);
  update public.erp_commercial_workflow_documents
  set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and parent_id=p_order_id and module='purchases'
    and id::text in (
      coalesce(v_snapshot#>>'{logistics,id}',''),
      coalesce(v_snapshot#>>'{invoice,id}','')
    ) and not is_deleted;
  perform public.erp_commercial_audit(p_company_id,'purchases',p_order_id,null,null,
    'edit_order_with_links',v_snapshot->>'orderStatus',v_snapshot->>'orderStatus','تم حفظ التعديل وإعادة بناء الارتباطات');
  return v_result;
end;
$$;

create or replace function public.erp_update_cloud_sales_order_with_links(
  p_company_id uuid,p_order_id uuid,p_customer_id text,p_currency text,
  p_exchange_rate numeric,p_discount numeric,p_items jsonb,p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_snapshot jsonb; v_result jsonb;
begin
  v_snapshot:=public.erp_prepare_commercial_order_change(
    p_company_id,p_order_id,'sales','تعديل أمر البيع وإعادة ربط مستنداته');
  perform public.erp_update_cloud_sales_order(p_company_id,p_order_id,p_customer_id,
    p_currency,p_exchange_rate,p_discount,p_items,p_notes);
  v_result:=public.erp_restore_commercial_order_links(p_company_id,p_order_id,'sales',v_snapshot);
  update public.erp_commercial_workflow_documents
  set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and parent_id=p_order_id and module='sales'
    and id::text in (
      coalesce(v_snapshot#>>'{logistics,id}',''),
      coalesce(v_snapshot#>>'{invoice,id}','')
    ) and not is_deleted;
  perform public.erp_commercial_audit(p_company_id,'sales',p_order_id,null,null,
    'edit_order_with_links',v_snapshot->>'orderStatus',v_snapshot->>'orderStatus','تم حفظ التعديل وإعادة بناء الارتباطات');
  return v_result;
end;
$$;

create or replace function public.erp_delete_cloud_purchase_order(
  p_company_id uuid,p_order_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare v_snapshot jsonb; v_number text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select order_number into v_number from public.erp_purchase_orders_cloud
  where company_id=p_company_id and id=p_order_id and not is_deleted;
  if not found then return; end if;
  v_snapshot:=public.erp_prepare_commercial_order_change(
    p_company_id,p_order_id,'purchases','حذف أمر الشراء وعكس ارتباطاته');
  perform public.erp_commercial_audit(p_company_id,'purchases',p_order_id,null,v_number,
    'delete_order_cascade',v_snapshot->>'orderStatus','deleted','حذف مع عكس الاستلام والفاتورة والدفعات');
  update public.erp_commercial_workflow_documents
  set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=p_company_id and parent_id=p_order_id and module='purchases' and not is_deleted;
  update public.erp_purchase_order_items_cloud set is_deleted=true
  where company_id=p_company_id and order_id=p_order_id and not is_deleted;
  update public.erp_purchase_orders_cloud
  set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=p_company_id and id=p_order_id and not is_deleted;
end;
$$;

create or replace function public.erp_delete_cloud_sales_order(
  p_company_id uuid,p_order_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare v_snapshot jsonb; v_number text;
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;
  select order_number into v_number from public.erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id and not is_deleted;
  if not found then return; end if;
  v_snapshot:=public.erp_prepare_commercial_order_change(
    p_company_id,p_order_id,'sales','حذف أمر البيع وعكس ارتباطاته');
  perform public.erp_commercial_audit(p_company_id,'sales',p_order_id,null,v_number,
    'delete_order_cascade',v_snapshot->>'orderStatus','deleted','حذف مع عكس التجهيز والفاتورة والدفعات');
  update public.erp_commercial_workflow_documents
  set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=p_company_id and parent_id=p_order_id and module='sales' and not is_deleted;
  update public.erp_sales_order_items_cloud set is_deleted=true
  where company_id=p_company_id and order_id=p_order_id and not is_deleted;
  update public.erp_sales_orders_cloud
  set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=p_company_id and id=p_order_id and not is_deleted;
end;
$$;

-- ---------------------------------------------------------------------------
-- Comprehensive contextual reports. rawData preserves every source field.
-- ---------------------------------------------------------------------------
create or replace function public.erp_cloud_contextual_report(
  p_company_id uuid,p_module text,p_start_date date default null,p_end_date date default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_sections jsonb:='[]'::jsonb;
  d1 date:=coalesce(p_start_date,date '1900-01-01');
  d2 date:=coalesce(p_end_date,date '2999-12-31');
  m text:=lower(btrim(coalesce(p_module,'overview')));
begin
  if not public.erp_is_company_member(p_company_id) then raise exception 'tenant denied'; end if;

  if m in ('overview','sales') then
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','sales_orders','title','Sales orders / أوامر البيع',
      'columns',jsonb_build_array('orderNumber','customer','status','currency','exchangeRate','subtotal','discount','total','notes','createdAt','updatedAt','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(o.order_number,coalesce(c.data->>'name',''),o.status,o.currency,o.exchange_rate,o.subtotal,o.discount,o.total,o.notes,o.created_at,o.updated_at,to_jsonb(o)::text) order by o.created_at desc),'[]'::jsonb)
              from public.erp_sales_orders_cloud o left join public.erp_customers c on c.company_id=o.company_id and c.id=o.customer_id and not c.is_deleted
              where o.company_id=p_company_id and not o.is_deleted and o.created_at::date between d1 and d2)));
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','sales_items','title','Sales order items / بنود أوامر البيع',
      'columns',jsonb_build_array('orderNumber','itemType','itemId','description','quantity','unitPrice','lineTotal','itemDetails','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(o.order_number,x.item_type,x.item_id,x.description,x.quantity,x.unit_price,x.line_total,coalesce(c.data,i.data,'{}'::jsonb)::text,to_jsonb(x)::text) order by o.created_at desc,x.id),'[]'::jsonb)
              from public.erp_sales_order_items_cloud x join public.erp_sales_orders_cloud o on o.company_id=x.company_id and o.id=x.order_id and not o.is_deleted
              left join public.erp_cars c on x.item_type='car' and c.company_id=x.company_id and c.id=x.item_id
              left join public.erp_inventory i on x.item_type='product' and i.company_id=x.company_id and i.id=x.item_id
              where x.company_id=p_company_id and not x.is_deleted and o.created_at::date between d1 and d2)));
  end if;

  if m in ('overview','purchases') then
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','purchase_orders','title','Purchase orders / أوامر الشراء',
      'columns',jsonb_build_array('orderNumber','supplier','status','currency','exchangeRate','subtotal','discount','total','notes','createdAt','updatedAt','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(o.order_number,coalesce(s.data->>'name',''),o.status,o.currency,o.exchange_rate,o.subtotal,o.discount,o.total,o.notes,o.created_at,o.updated_at,to_jsonb(o)::text) order by o.created_at desc),'[]'::jsonb)
              from public.erp_purchase_orders_cloud o left join public.erp_suppliers s on s.company_id=o.company_id and s.id=o.supplier_id and not s.is_deleted
              where o.company_id=p_company_id and not o.is_deleted and o.created_at::date between d1 and d2)));
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','purchase_items','title','Purchase order items / بنود أوامر الشراء',
      'columns',jsonb_build_array('orderNumber','itemType','itemId','description','quantity','unitCost','lineTotal','itemDetails','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(o.order_number,x.item_type,x.item_id,x.description,x.quantity,x.unit_cost,x.line_total,coalesce(c.data,i.data,'{}'::jsonb)::text,to_jsonb(x)::text) order by o.created_at desc,x.id),'[]'::jsonb)
              from public.erp_purchase_order_items_cloud x join public.erp_purchase_orders_cloud o on o.company_id=x.company_id and o.id=x.order_id and not o.is_deleted
              left join public.erp_cars c on x.item_type='car' and c.company_id=x.company_id and c.id=x.item_id
              left join public.erp_inventory i on x.item_type='product' and i.company_id=x.company_id and i.id=x.item_id
              where x.company_id=p_company_id and not x.is_deleted and o.created_at::date between d1 and d2)));
  end if;

  if m in ('overview','sales','purchases','finance','operations') then
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','workflow_documents','title','Workflow documents / مستندات الدورة التجارية',
      'columns',jsonb_build_array('module','documentType','documentNumber','parentId','warehouse','status','total','paid','remaining','createdAt','updatedAt','payload'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(d.module,d.document_type,d.document_number,d.parent_id,coalesce(w.data->>'name',d.warehouse_id,''),d.status,public.erp_try_numeric(d.payload->>'totalAmount',0),public.erp_try_numeric(d.payload->>'paidAmount',0),public.erp_try_numeric(d.payload->>'remainingAmount',0),d.created_at,d.updated_at,d.payload::text) order by d.created_at desc),'[]'::jsonb)
              from public.erp_commercial_workflow_documents d left join public.erp_warehouses w on w.company_id=d.company_id and w.id=d.warehouse_id
              where d.company_id=p_company_id and not d.is_deleted and d.created_at::date between d1 and d2
                and (m in ('overview','finance','operations') or d.module=m))));
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','workflow_payments','title','Invoice payments / دفعات الفواتير',
      'columns',jsonb_build_array('module','invoiceNumber','paymentId','cashAccount','paymentCurrency','cashAmount','invoiceCurrency','invoiceAmount','exchangeRate','exchangeDifference','paymentDate','notes','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(d.module,d.document_number,p.value->>'paymentId',coalesce(c.data->>'name',''),p.value->>'paymentCurrency',p.value->>'cashAmount',p.value->>'invoiceCurrency',p.value->>'invoiceAmount',p.value->>'exchangeRate',p.value->>'exchangeDifference',p.value->>'paymentDate',p.value->>'notes',p.value::text) order by public.erp_try_timestamptz(p.value->>'paymentDate',d.created_at) desc),'[]'::jsonb)
              from public.erp_commercial_workflow_documents d cross join lateral jsonb_array_elements(coalesce(d.payload->'payments','[]'::jsonb)) p(value)
              left join public.erp_cash_accounts c on c.company_id=d.company_id and c.id=p.value->>'cashAccountId'
              where d.company_id=p_company_id and not d.is_deleted and d.document_type='invoice'
                and d.created_at::date between d1 and d2 and (m in ('overview','finance','operations') or d.module=m))));
  end if;

  if m in ('overview','inventory') then
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','warehouse_stock','title','Warehouse stock / أرصدة المخازن',
      'columns',jsonb_build_array('productCode','productName','warehouse','quantity','reservedQuantity','availableQuantity','expectedIncoming','expectedOutgoing','averageUnitCost','stockValue','updatedAt','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(i.data->>'code',i.data->>'name',w.data->>'name',public.erp_try_numeric(s.data->>'quantity',0),public.erp_try_numeric(s.data->>'reservedQuantity',0),public.erp_try_numeric(s.data->>'quantity',0)-public.erp_try_numeric(s.data->>'reservedQuantity',0),public.erp_try_numeric(s.data->>'expectedIncoming',0),public.erp_try_numeric(s.data->>'expectedOutgoing',0),public.erp_try_numeric(s.data->>'averageUnitCost',0),public.erp_try_numeric(s.data->>'quantity',0)*public.erp_try_numeric(s.data->>'averageUnitCost',0),s.updated_at,s.data::text) order by i.data->>'name',w.data->>'name'),'[]'::jsonb)
              from public.erp_warehouse_stock s left join public.erp_inventory i on i.company_id=s.company_id and i.id=s.data->>'productId'
              left join public.erp_warehouses w on w.company_id=s.company_id and w.id=s.data->>'warehouseId'
              where s.company_id=p_company_id and not s.is_deleted)));
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','inventory_movements','title','Inventory movements / الحركات المخزنية',
      'columns',jsonb_build_array('movementNumber','product','warehouse','movementType','quantity','unitCost','referenceType','referenceId','movementDate','notes','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(x.data->>'movementNumber',coalesce(i.data->>'name',x.data->>'productId'),coalesce(w.data->>'name',x.data->>'warehouseId'),x.data->>'movementType',x.data->>'quantity',x.data->>'unitCost',x.data->>'referenceType',x.data->>'referenceId',x.data->>'movementDate',x.data->>'notes',x.data::text) order by public.erp_try_timestamptz(x.data->>'movementDate',x.created_at) desc),'[]'::jsonb)
              from public.erp_inventory_movements x left join public.erp_inventory i on i.company_id=x.company_id and i.id=x.data->>'productId'
              left join public.erp_warehouses w on w.company_id=x.company_id and w.id=x.data->>'warehouseId'
              where x.company_id=p_company_id and not x.is_deleted and coalesce(public.erp_try_timestamptz(x.data->>'movementDate',x.created_at),x.created_at)::date between d1 and d2)));
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','warehouse_transfers','title','Product warehouse transfers / نقل المنتجات',
      'columns',jsonb_build_array('transferNumber','fromWarehouse','toWarehouse','product','quantity','unitCost','status','transferDate','notes','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(t.data->>'transferNumber',fw.data->>'name',tw.data->>'name',coalesce(i.data->>'name',ti.data->>'productId'),ti.data->>'quantity',ti.data->>'unitCost',t.data->>'status',t.data->>'transferDate',t.data->>'notes',(t.data||jsonb_build_object('item',ti.data))::text) order by public.erp_try_timestamptz(t.data->>'transferDate',t.created_at) desc),'[]'::jsonb)
              from public.erp_warehouse_transfers t join public.erp_warehouse_transfer_items ti on ti.company_id=t.company_id and ti.data->>'transferId'=t.id and not ti.is_deleted
              left join public.erp_inventory i on i.company_id=t.company_id and i.id=ti.data->>'productId'
              left join public.erp_warehouses fw on fw.company_id=t.company_id and fw.id=t.data->>'fromWarehouseId'
              left join public.erp_warehouses tw on tw.company_id=t.company_id and tw.id=t.data->>'toWarehouseId'
              where t.company_id=p_company_id and not t.is_deleted and coalesce(public.erp_try_timestamptz(t.data->>'transferDate',t.created_at),t.created_at)::date between d1 and d2)));
  end if;

  if m in ('overview','cars') then
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','cars','title','Vehicles / السيارات',
      'columns',jsonb_build_array('brand','model','year','chassis','plateNumber','color','status','warehouse','purchasePrice','maintenanceCost','salePrice','createdAt','updatedAt','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(coalesce(c.data->>'brand',c.data->>'make'),c.data->>'model',c.data->>'year',coalesce(c.data->>'chassis',c.data->>'vin'),c.data->>'plateNumber',c.data->>'color',c.data->>'status',coalesce(w.data->>'name',''),c.data->>'purchasePrice',c.data->>'maintenanceCost',c.data->>'salePrice',c.created_at,c.updated_at,c.data::text) order by c.created_at desc),'[]'::jsonb)
              from public.erp_cars c left join public.erp_warehouses w on w.company_id=c.company_id and w.id=coalesce(c.data->>'warehouseId',c.data->>'warehouse_id')
              where c.company_id=p_company_id and not c.is_deleted)));
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','car_transfers','title','Vehicle warehouse transfers / نقل السيارات',
      'columns',jsonb_build_array('transferNumber','vehicle','chassis','fromWarehouse','toWarehouse','status','transferDate','createdBy','notes','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(t.data->>'transferNumber',concat_ws(' ',coalesce(c.data->>'brand',c.data->>'make'),c.data->>'model',c.data->>'year'),coalesce(c.data->>'chassis',c.data->>'vin'),fw.data->>'name',tw.data->>'name',t.data->>'status',t.data->>'transferDate',t.data->>'createdByUserName',t.data->>'notes',t.data::text) order by public.erp_try_timestamptz(t.data->>'transferDate',t.created_at) desc),'[]'::jsonb)
              from public.erp_car_warehouse_transfers t left join public.erp_cars c on c.company_id=t.company_id and c.id=t.data->>'carId'
              left join public.erp_warehouses fw on fw.company_id=t.company_id and fw.id=t.data->>'fromWarehouseId'
              left join public.erp_warehouses tw on tw.company_id=t.company_id and tw.id=t.data->>'toWarehouseId'
              where t.company_id=p_company_id and not t.is_deleted and coalesce(public.erp_try_timestamptz(t.data->>'transferDate',t.created_at),t.created_at)::date between d1 and d2)));
  end if;

  if m in ('overview','finance') then
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','cash_transactions','title','Cash transactions / حركات الصندوق',
      'columns',jsonb_build_array('voucherNumber','type','category','cashAccount','amount','currency','exchangeRate','amountUsd','amountIqd','transactionDate','party','notes','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(x.data->>'voucherNumber',x.data->>'type',x.data->>'category',coalesce(c.data->>'name',x.data->>'cashAccountId'),x.data->>'amount',x.data->>'currency',x.data->>'exchangeRate',x.data->>'amountUsd',x.data->>'amountIqd',x.data->>'transactionDate',concat_ws(': ',x.data->>'partyType',x.data->>'partyId'),x.data->>'notes',x.data::text) order by public.erp_try_timestamptz(x.data->>'transactionDate',x.created_at) desc),'[]'::jsonb)
              from public.erp_cash_transactions x left join public.erp_cash_accounts c on c.company_id=x.company_id and c.id=x.data->>'cashAccountId'
              where x.company_id=p_company_id and not x.is_deleted and coalesce(public.erp_try_timestamptz(x.data->>'transactionDate',x.created_at),x.created_at)::date between d1 and d2)));
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','journal_entries','title','Journal entries / القيود المحاسبية',
      'columns',jsonb_build_array('entryNumber','entryDate','description','currency','totalDebit','totalCredit','status','referenceType','referenceId','orderId','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(j.data->>'entryNumber',j.data->>'entryDate',j.data->>'description',j.data->>'currency',j.data->>'totalDebit',j.data->>'totalCredit',j.data->>'status',j.data->>'referenceType',j.data->>'referenceId',j.data->>'orderId',j.data::text) order by public.erp_try_timestamptz(j.data->>'entryDate',j.created_at) desc),'[]'::jsonb)
              from public.erp_journal_entries j where j.company_id=p_company_id and not j.is_deleted and coalesce(public.erp_try_timestamptz(j.data->>'entryDate',j.created_at),j.created_at)::date between d1 and d2)));
  end if;

  if m in ('overview','partners') then
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','customers','title','Customers / العملاء','columns',jsonb_build_array('id','name','phone','email','address','taxNumber','createdAt','updatedAt','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(c.id,c.data->>'name',c.data->>'phone',c.data->>'email',c.data->>'address',c.data->>'taxNumber',c.created_at,c.updated_at,c.data::text) order by c.data->>'name'),'[]'::jsonb) from public.erp_customers c where c.company_id=p_company_id and not c.is_deleted)));
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','suppliers','title','Suppliers / الموردون','columns',jsonb_build_array('id','name','phone','email','address','taxNumber','createdAt','updatedAt','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(s.id,s.data->>'name',s.data->>'phone',s.data->>'email',s.data->>'address',s.data->>'taxNumber',s.created_at,s.updated_at,s.data::text) order by s.data->>'name'),'[]'::jsonb) from public.erp_suppliers s where s.company_id=p_company_id and not s.is_deleted)));
  end if;

  if m in ('overview','operations') then
    v_sections:=v_sections||jsonb_build_array(jsonb_build_object('key','commercial_audit','title','Commercial audit trail / سجل تدقيق العمليات',
      'columns',jsonb_build_array('module','documentNumber','action','fromStatus','toStatus','reason','performedBy','performedAt','parentId','documentId','rawData'),
      'rows',(select coalesce(jsonb_agg(jsonb_build_array(a.module,a.document_number,a.action,a.from_status,a.to_status,a.reason,coalesce(u.email,'system'),a.performed_at,a.parent_id,a.document_id,to_jsonb(a)::text) order by a.performed_at desc),'[]'::jsonb)
              from public.erp_commercial_workflow_audit a left join auth.users u on u.id=a.performed_by
              where a.company_id=p_company_id and a.performed_at::date between d1 and d2)));
  end if;
  return v_sections;
end;
$$;

grant execute on function public.erp_create_car_warehouse_transfer(uuid,text,text,text,text) to authenticated;
grant execute on function public.erp_update_car_warehouse_transfer(uuid,text,text,text,text) to authenticated;
grant execute on function public.erp_reverse_car_warehouse_transfer(uuid,text,text) to authenticated;
grant execute on function public.erp_transfer_inventory_stock(uuid,text,text,text,integer,text) to authenticated;
grant execute on function public.erp_delete_cloud_purchase_order(uuid,uuid) to authenticated;
grant execute on function public.erp_delete_cloud_sales_order(uuid,uuid) to authenticated;
grant execute on function public.erp_cloud_purchase_order_edit_catalog(uuid,uuid) to authenticated;
grant execute on function public.erp_cloud_sales_order_edit_catalog(uuid,uuid) to authenticated;
grant execute on function public.erp_reverse_cloud_workflow_invoice_payments(uuid,uuid,text) to authenticated;
grant execute on function public.erp_prepare_commercial_order_change(uuid,uuid,text,text) to authenticated;
grant execute on function public.erp_restore_commercial_order_links(uuid,uuid,text,jsonb) to authenticated;
grant execute on function public.erp_update_cloud_purchase_order_with_links(uuid,uuid,text,text,numeric,numeric,jsonb,text) to authenticated;
grant execute on function public.erp_update_cloud_sales_order_with_links(uuid,uuid,text,text,numeric,numeric,jsonb,text) to authenticated;
grant execute on function public.erp_cloud_contextual_report(uuid,text,date,date) to authenticated;

-- Complete order detail package used by the in-window editor and the bilingual
-- PDF renderer. The legacy detail RPC is retained for compatibility; this
-- wrapper enriches every linked record with its complete cloud payload.
create or replace function public.erp_get_cloud_commercial_order_complete_details(
  p_company_id uuid,
  p_order_id uuid,
  p_purchase boolean
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_result jsonb;
  v_order_raw jsonb;
  v_items jsonb;
  v_logistics jsonb;
  v_invoices jsonb;
  v_payments jsonb;
  v_movements jsonb;
  v_journals jsonb;
  v_audit jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'tenant denied';
  end if;

  v_result := public.erp_get_cloud_commercial_order_details(
    p_company_id,
    p_order_id,
    p_purchase
  );

  if p_purchase then
    select to_jsonb(o) into v_order_raw
    from public.erp_purchase_orders_cloud o
    where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted;

    select coalesce(
      jsonb_agg(
        e.item || jsonb_build_object(
          'rawData',to_jsonb(x),
          'details',coalesce(c.data,i.data,e.item->'details','{}'::jsonb)
        ) order by e.ordinality
      ),
      '[]'::jsonb
    ) into v_items
    from jsonb_array_elements(coalesce(v_result->'items','[]'::jsonb))
      with ordinality as e(item,ordinality)
    left join public.erp_purchase_order_items_cloud x
      on x.company_id=p_company_id and x.id::text=e.item->>'id'
    left join public.erp_cars c
      on x.item_type='car' and c.company_id=x.company_id and c.id=x.item_id
    left join public.erp_inventory i
      on x.item_type='product' and i.company_id=x.company_id and i.id=x.item_id;
  else
    select to_jsonb(o) into v_order_raw
    from public.erp_sales_orders_cloud o
    where o.company_id=p_company_id and o.id=p_order_id and not o.is_deleted;

    select coalesce(
      jsonb_agg(
        e.item || jsonb_build_object(
          'rawData',to_jsonb(x),
          'details',coalesce(c.data,i.data,e.item->'details','{}'::jsonb)
        ) order by e.ordinality
      ),
      '[]'::jsonb
    ) into v_items
    from jsonb_array_elements(coalesce(v_result->'items','[]'::jsonb))
      with ordinality as e(item,ordinality)
    left join public.erp_sales_order_items_cloud x
      on x.company_id=p_company_id and x.id::text=e.item->>'id'
    left join public.erp_cars c
      on x.item_type='car' and c.company_id=x.company_id and c.id=x.item_id
    left join public.erp_inventory i
      on x.item_type='product' and i.company_id=x.company_id and i.id=x.item_id;
  end if;

  select coalesce(
    jsonb_agg(
      e.item || jsonb_build_object(
        'payload',coalesce(d.payload,'{}'::jsonb),
        'rawData',to_jsonb(d)
      ) order by e.ordinality
    ),
    '[]'::jsonb
  ) into v_logistics
  from jsonb_array_elements(coalesce(v_result->'logistics','[]'::jsonb))
    with ordinality as e(item,ordinality)
  left join public.erp_commercial_workflow_documents d
    on d.company_id=p_company_id and d.id::text=e.item->>'id';

  select coalesce(
    jsonb_agg(
      e.item || jsonb_build_object(
        'payload',coalesce(d.payload,'{}'::jsonb),
        'rawData',to_jsonb(d)
      ) order by e.ordinality
    ),
    '[]'::jsonb
  ) into v_invoices
  from jsonb_array_elements(coalesce(v_result->'invoices','[]'::jsonb))
    with ordinality as e(item,ordinality)
  left join public.erp_commercial_workflow_documents d
    on d.company_id=p_company_id and d.id::text=e.item->>'id';

  select coalesce(
    jsonb_agg(
      e.item || jsonb_build_object(
        'invoicePayload',coalesce(d.payload,'{}'::jsonb),
        'invoiceRawData',to_jsonb(d)
      ) order by e.ordinality
    ),
    '[]'::jsonb
  ) into v_payments
  from jsonb_array_elements(coalesce(v_result->'payments','[]'::jsonb))
    with ordinality as e(item,ordinality)
  left join public.erp_commercial_workflow_documents d
    on d.company_id=p_company_id and d.id::text=e.item->>'invoiceId';

  select coalesce(
    jsonb_agg(
      e.item || jsonb_build_object(
        'rawData',coalesce(m.data,'{}'::jsonb),
        'recordMeta',to_jsonb(m)-'data'
      ) order by e.ordinality
    ),
    '[]'::jsonb
  ) into v_movements
  from jsonb_array_elements(coalesce(v_result->'movements','[]'::jsonb))
    with ordinality as e(item,ordinality)
  left join public.erp_inventory_movements m
    on m.company_id=p_company_id and m.id=e.item->>'id';

  select coalesce(
    jsonb_agg(
      e.item || jsonb_build_object(
        'rawData',coalesce(j.data,'{}'::jsonb),
        'recordMeta',to_jsonb(j)-'data',
        'lines',coalesce((
          select jsonb_agg(
            coalesce(l.data,'{}'::jsonb) || jsonb_build_object(
              'id',l.id,
              'createdAt',l.created_at,
              'updatedAt',l.updated_at
            ) order by l.created_at,l.id
          )
          from public.erp_journal_lines l
          where l.company_id=p_company_id
            and l.data->>'entryId'=j.id
            and not l.is_deleted
        ),'[]'::jsonb)
      ) order by e.ordinality
    ),
    '[]'::jsonb
  ) into v_journals
  from jsonb_array_elements(coalesce(v_result->'journalEntries','[]'::jsonb))
    with ordinality as e(item,ordinality)
  left join public.erp_journal_entries j
    on j.company_id=p_company_id and j.id=e.item->>'id';

  select coalesce(
    jsonb_agg(
      e.item || jsonb_build_object('rawData',to_jsonb(a))
      order by e.ordinality
    ),
    '[]'::jsonb
  ) into v_audit
  from jsonb_array_elements(coalesce(v_result->'auditTrail','[]'::jsonb))
    with ordinality as e(item,ordinality)
  left join public.erp_commercial_workflow_audit a
    on a.company_id=p_company_id and a.id::text=e.item->>'id';

  return jsonb_build_object(
    'order',coalesce(v_result->'order','{}'::jsonb) || jsonb_build_object(
      'rawData',coalesce(v_order_raw,'{}'::jsonb)
    ),
    'items',coalesce(v_items,'[]'::jsonb),
    'logistics',coalesce(v_logistics,'[]'::jsonb),
    'invoices',coalesce(v_invoices,'[]'::jsonb),
    'payments',coalesce(v_payments,'[]'::jsonb),
    'movements',coalesce(v_movements,'[]'::jsonb),
    'journalEntries',coalesce(v_journals,'[]'::jsonb),
    'auditTrail',coalesce(v_audit,'[]'::jsonb)
  );
end;
$$;

grant execute on function public.erp_get_cloud_commercial_order_complete_details(uuid,uuid,boolean) to authenticated;

commit;
