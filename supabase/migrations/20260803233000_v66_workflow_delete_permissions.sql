begin;

-- Quality Line ERP V6.6
-- Complete maintenance workflow deletion, linked accounting cleanup,
-- product/vehicle warehouse-transfer deletion, and dedicated permissions.

insert into public.permissions(code,name_ar,name_en)
values
  ('cars.transfer.delete','حذف نقل السيارات','Delete vehicle transfers'),
  ('inventory.transfer.delete','حذف نقل المنتجات','Delete product transfers')
on conflict(code) do update
set name_ar=excluded.name_ar,
    name_en=excluded.name_en;

insert into public.role_permissions(role_code,permission_code)
select role_code,permission_code
from (values
  ('owner','cars.transfer.delete'),
  ('admin','cars.transfer.delete'),
  ('owner','inventory.transfer.delete'),
  ('admin','inventory.transfer.delete')
) as x(role_code,permission_code)
on conflict do nothing;

-- Seed the two new permissions into the legacy access catalog used by the UI.
do $$
declare c record;
begin
  if to_regprocedure('public.erp_seed_access_catalog(uuid)') is not null then
    for c in select id from public.companies where is_active loop
      perform public.erp_seed_access_catalog(c.id);
    end loop;
  end if;
end $$;

create or replace function public.erp_v66_reverse_maintenance_stock(
  p_company_id uuid,
  p_order_id uuid,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  o public.erp_maintenance_orders%rowtype;
  line record;
  stock_row public.erp_warehouse_stock%rowtype;
  product_id text;
  warehouse_id text;
  issued numeric;
  returned numeric;
  quantity_to_restore numeric;
  current_qty numeric;
  current_avg numeric;
  new_avg numeric;
  now_value timestamptz:=now();
begin
  select * into o
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted
  for update;
  if not found then
    raise exception 'maintenance_order_not_found';
  end if;

  for line in
    select
      coalesce(source_product_id,product_id::text) as product_id,
      coalesce(source_warehouse_id,warehouse_id::text,o.source_warehouse_id,o.warehouse_id::text) as warehouse_id,
      sum(quantity)::numeric as line_quantity,
      case when sum(quantity)>0 then sum(quantity*unit_cost)/sum(quantity) else 0 end as unit_cost
    from public.erp_maintenance_parts
    where company_id=p_company_id
      and maintenance_order_id=p_order_id
      and not is_deleted
      and line_type<>'service'
    group by coalesce(source_product_id,product_id::text),
             coalesce(source_warehouse_id,warehouse_id::text,o.source_warehouse_id,o.warehouse_id::text)
  loop
    product_id:=line.product_id;
    warehouse_id:=line.warehouse_id;

    select coalesce(sum(abs(public.erp_try_numeric(data->>'quantity',0))),0)
      into issued
    from public.erp_inventory_movements
    where company_id=p_company_id and not is_deleted
      and coalesce(data->>'referenceId',data->>'reference_id')=p_order_id::text
      and lower(coalesce(data->>'referenceType',data->>'reference_type',''))='maintenance_order'
      and lower(coalesce(data->>'movementType',data->>'movement_type',''))='maintenance_out'
      and coalesce(data->>'productId',data->>'product_id')=product_id
      and coalesce(data->>'warehouseId',data->>'warehouse_id')=warehouse_id;

    select coalesce(sum(abs(public.erp_try_numeric(data->>'quantity',0))),0)
      into returned
    from public.erp_inventory_movements
    where company_id=p_company_id and not is_deleted
      and coalesce(data->>'referenceId',data->>'reference_id')=p_order_id::text
      and lower(coalesce(data->>'movementType',data->>'movement_type',''))='maintenance_return'
      and coalesce(data->>'productId',data->>'product_id')=product_id
      and coalesce(data->>'warehouseId',data->>'warehouse_id')=warehouse_id;

    quantity_to_restore:=greatest(issued-returned,0);
    if quantity_to_restore<=0 then
      continue;
    end if;

    stock_row:=public.erp_inventory_ensure_stock(
      p_company_id,warehouse_id,product_id
    );
    current_qty:=public.erp_try_numeric(stock_row.data->>'quantity',0);
    current_avg:=public.erp_try_numeric(stock_row.data->>'averageUnitCost',0);
    if current_qty+quantity_to_restore>0 then
      new_avg:=((current_qty*current_avg)+(quantity_to_restore*line.unit_cost)) /
               (current_qty+quantity_to_restore);
    else
      new_avg:=line.unit_cost;
    end if;

    update public.erp_warehouse_stock
       set data=data||jsonb_build_object(
             'quantity',(current_qty+quantity_to_restore)::int,
             'averageUnitCost',new_avg,
             'updatedAt',now_value
           ),
           updated_at=now_value,
           updated_by=auth.uid()
     where company_id=p_company_id and id=stock_row.id;

    perform public.erp_inventory_insert_movement(
      p_company_id,product_id,warehouse_id,'maintenance_return',
      quantity_to_restore,line.unit_cost,'maintenance_delete',p_order_id::text,
      coalesce(nullif(btrim(p_reason),''),'Delete maintenance order and restore stock')
    );
    perform public.erp_inventory_refresh_product(p_company_id,product_id);
  end loop;

  if coalesce(o.car_cost_added,0)>0 then
    update public.erp_cars
       set data=data||jsonb_build_object(
             'maintenanceCost',greatest(
               public.erp_try_numeric(coalesce(data->>'maintenanceCost',data->>'maintenance_cost'),0)-o.car_cost_added,
               0
             ),
             'updatedAt',now_value
           ),
           updated_at=now_value,
           updated_by=auth.uid()
     where company_id=p_company_id
       and id=coalesce(o.source_car_id,o.car_id::text)
       and not is_deleted;

    update public.erp_maintenance_orders
       set car_cost_added=0,updated_at=now_value
     where company_id=p_company_id and id=p_order_id;
  end if;

  perform public.erp_phase2_void_reference_journals(
    p_company_id,'maintenance_stock_issue',p_order_id::text
  );
  perform public.erp_phase2_void_reference_journals(
    p_company_id,'maintenance_invoice',p_order_id::text
  );
  perform public.erp_phase2_void_reference_journals(
    p_company_id,'maintenance_payment',p_order_id::text
  );
  perform public.erp_phase2_void_reference_journals(
    p_company_id,'maintenance',p_order_id::text
  );
end;
$$;

create or replace function public.erp_advance_cloud_maintenance_workflow(
  p_company_id uuid,p_order_id uuid
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  o public.erp_maintenance_orders%rowtype;
  p record;
  s public.erp_warehouse_stock%rowtype;
  v_now timestamptz:=now();
  product_id text;
  warehouse_id text;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['maintenance.approve']
  );
  select * into o
  from public.erp_maintenance_orders
  where id=p_order_id and company_id=p_company_id and not is_deleted
  for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;

  if o.workflow_stage='order_draft' then
    update public.erp_maintenance_orders
       set workflow_stage='order_approved',status='approved',updated_at=v_now
     where id=o.id;
  elsif o.workflow_stage='order_approved' then
    update public.erp_maintenance_orders
       set workflow_stage='stock_issue_draft',stock_issue_number='PENDING',updated_at=v_now
     where id=o.id;
  elsif o.workflow_stage='stock_issue_draft' then
    for p in
      select * from public.erp_maintenance_parts
      where company_id=p_company_id and maintenance_order_id=o.id
        and not is_deleted and line_type<>'service'
    loop
      product_id:=coalesce(p.source_product_id,p.product_id::text);
      warehouse_id:=coalesce(
        p.source_warehouse_id,p.warehouse_id::text,
        o.source_warehouse_id,o.warehouse_id::text
      );
      select * into s
      from public.erp_warehouse_stock
      where company_id=p_company_id and not is_deleted
        and coalesce(data->>'warehouseId',data->>'warehouse_id')=warehouse_id
        and coalesce(data->>'productId',data->>'product_id')=product_id
      for update;
      if not found or
         public.erp_try_numeric(s.data->>'quantity',0)-
         public.erp_try_numeric(s.data->>'reservedQuantity',0)<p.quantity then
        raise exception 'maintenance_insufficient_stock:%',p.product_name;
      end if;
      update public.erp_warehouse_stock
         set data=data||jsonb_build_object(
               'quantity',public.erp_try_numeric(data->>'quantity',0)-p.quantity,
               'updatedAt',v_now
             ),
             updated_at=v_now,
             updated_by=auth.uid()
       where id=s.id;
      perform public.erp_inventory_insert_movement(
        p_company_id,product_id,warehouse_id,'maintenance_out',-p.quantity,
        p.unit_cost,'maintenance_order',o.id::text,
        'Maintenance issue '||o.order_number
      );
    end loop;
    perform public.erp_phase3_refresh_maintenance_products(p_company_id,o.id);
    perform public.erp_phase3_post_maintenance_issue(p_company_id,o.id);
    update public.erp_maintenance_orders
       set workflow_stage='stock_issue_approved',
           stock_issue_number=case
             when stock_issue_number is null or stock_issue_number='PENDING' then
               public.erp_next_document_number(
                 p_company_id,'maintenance_stock_issue','MSI',o.maintenance_date
               )
             else stock_issue_number
           end,
           updated_at=v_now
     where id=o.id;
  elsif o.workflow_stage='stock_issue_approved' then
    update public.erp_maintenance_orders
       set workflow_stage=case when pricing_type='paid' then 'invoice_draft' else 'completed' end,
           status=case when pricing_type='paid' then status else 'completed' end,
           invoice_number=case when pricing_type='paid' then 'PENDING' else invoice_number end,
           updated_at=v_now
     where id=o.id;
  elsif o.workflow_stage='invoice_draft' then
    update public.erp_maintenance_orders
       set workflow_stage='invoice_approved',
           invoice_number=case
             when invoice_number is null or invoice_number='PENDING' then
               public.erp_next_document_number(
                 p_company_id,'maintenance_invoice','MINV',o.maintenance_date
               )
             else invoice_number
           end,
           updated_at=v_now
     where id=o.id;
  else
    raise exception 'maintenance_no_next_stage';
  end if;
end;
$$;

create or replace function public.erp_cancel_cloud_maintenance_order(
  p_company_id uuid,p_order_id uuid,p_reason text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare o public.erp_maintenance_orders%rowtype;
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['maintenance.cancel']
  );
  select * into o
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted
  for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if o.workflow_stage='cancelled' then return; end if;
  if coalesce(o.paid_amount,0)>0 or exists(
    select 1 from public.erp_maintenance_payments
    where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted
  ) then
    raise exception 'maintenance_reverse_payments_first';
  end if;

  perform public.erp_v66_reverse_maintenance_stock(
    p_company_id,p_order_id,
    coalesce(nullif(btrim(p_reason),''),'Cancel maintenance order')
  );
  update public.erp_maintenance_orders
     set workflow_stage='cancelled',status='cancelled',cancelled_at=now(),
         cancel_reason=nullif(btrim(p_reason),''),updated_at=now()
   where company_id=p_company_id and id=p_order_id;
end;
$$;

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
  v_id uuid;
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
  v_currency:=coalesce(nullif(p_currency_code,''),o.currency_code);
  v_rate:=coalesce(p_exchange_rate,o.exchange_rate);
  if v_rate<=0 then raise exception 'maintenance_invalid_exchange_rate'; end if;
  v_converted:=case
    when v_currency=o.currency_code then p_amount
    when v_currency='IQD' and o.currency_code='USD' then p_amount/v_rate
    else p_amount*v_rate
  end;
  v_next:=o.paid_amount+v_converted;
  if v_next>o.sale_price+0.001 then raise exception 'maintenance_payment_exceeds_balance'; end if;
  insert into public.erp_maintenance_payments(
    company_id,maintenance_order_id,amount,currency_code,exchange_rate,
    amount_in_order_currency,notes
  ) values(
    p_company_id,o.id,p_amount,v_currency,v_rate,v_converted,p_notes
  ) returning id into v_id;
  update public.erp_maintenance_orders
     set paid_amount=v_next,
         workflow_stage=case when v_next+0.001>=sale_price then 'paid' else 'invoice_approved' end,
         status=case when v_next+0.001>=sale_price then 'completed' else 'approved' end,
         updated_at=now()
   where id=o.id;
  return v_id;
end;
$$;

create or replace function public.erp_delete_cloud_maintenance_order(
  p_company_id uuid,p_order_id uuid,p_reason text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  o public.erp_maintenance_orders%rowtype;
  cash_row record;
  v_reason text:=coalesce(nullif(btrim(p_reason),''),'Delete maintenance order and update links');
  v_batch uuid:=gen_random_uuid();
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['maintenance.delete']
  );
  select * into o
  from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id
  for update;
  if not found then raise exception 'maintenance_order_not_found'; end if;
  if o.is_deleted then return; end if;

  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_maintenance_orders',true);
  perform set_config('qualityline.deletion_root_id',p_order_id::text,true);
  perform set_config('qualityline.deletion_reason',v_reason,true);

  -- Remove every cash receipt generated for this maintenance order and its journal.
  for cash_row in
    select id,coalesce(
      nullif(data->>'journalEntryId',''),nullif(data->>'journal_entry_id',''),
      nullif(data->>'entryId',''),nullif(data->>'entry_id','')
    ) as journal_id
    from public.erp_cash_transactions
    where company_id=p_company_id and not is_deleted
      and coalesce(
        data->>'maintenanceOrderId',data->>'maintenance_order_id',
        data->>'referenceId',data->>'reference_id'
      )=p_order_id::text
      and lower(coalesce(data->>'referenceType',data->>'reference_type','')) in
          ('maintenance','maintenance_payment','maintenance payment')
    for update
  loop
    perform public.erp_v65_soft_delete_journal(
      p_company_id,cash_row.journal_id,v_reason
    );
    update public.erp_cash_transactions
       set is_deleted=true,deleted_at=now(),updated_at=now(),updated_by=auth.uid(),
           data=data||jsonb_build_object('deleteReason',v_reason,'deletedAt',now())
     where company_id=p_company_id and id=cash_row.id and not is_deleted;
  end loop;

  update public.erp_maintenance_payments
     set is_deleted=true,deleted_at=now()
   where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;
  update public.erp_maintenance_orders
     set paid_amount=0,updated_at=now()
   where company_id=p_company_id and id=p_order_id;

  perform public.erp_v66_reverse_maintenance_stock(
    p_company_id,p_order_id,v_reason
  );

  update public.erp_maintenance_parts
     set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=p_company_id and maintenance_order_id=p_order_id and not is_deleted;

  update public.erp_maintenance_orders
     set paid_amount=0,status='cancelled',workflow_stage='cancelled',
         cancel_reason=v_reason,cancelled_at=coalesce(cancelled_at,now()),
         is_deleted=true,deleted_at=now(),deleted_by=auth.uid(),
         deleted_reason=v_reason,updated_at=now()
   where company_id=p_company_id and id=p_order_id;

  update public.erp_universal_recycle_bin
     set relation_context=relation_context||jsonb_build_object(
       'maintenanceWorkflowStage',o.workflow_stage,
       'maintenanceOrderNumber',o.order_number,
       'linkedPaymentsReversed',true,
       'linkedInventoryReversed',true,
       'linkedJournalsReversed',true
     )
   where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

create or replace function public.erp_list_inventory_warehouse_transfers(
  p_company_id uuid
) returns setof jsonb
language sql
security definer
set search_path=public
as $$
  select jsonb_build_object(
    'id',t.id,
    'transferNumber',coalesce(t.data->>'transferNumber',t.data->>'transfer_number',t.id),
    'transferDate',coalesce(t.data->>'transferDate',t.data->>'transfer_date',t.created_at::text),
    'fromWarehouseId',coalesce(t.data->>'fromWarehouseId',t.data->>'from_warehouse_id'),
    'fromWarehouseName',coalesce(wf.data->>'name',''),
    'toWarehouseId',coalesce(t.data->>'toWarehouseId',t.data->>'to_warehouse_id'),
    'toWarehouseName',coalesce(wt.data->>'name',''),
    'status',coalesce(t.data->>'status','completed'),
    'notes',coalesce(t.data->>'notes',''),
    'lineCount',coalesce(nullif(public.erp_try_integer(t.data->>'lineCount',0),0),count(i.id)::int),
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'id',i.id,
      'productId',coalesce(i.data->>'productId',i.data->>'product_id'),
      'productName',coalesce(p.data->>'name',p.data->>'nameAr',p.data->>'name_ar',''),
      'productCode',coalesce(p.data->>'code',p.data->>'productNumber',''),
      'quantity',public.erp_try_numeric(i.data->>'quantity',0),
      'unitCost',public.erp_try_numeric(coalesce(i.data->>'unitCost',i.data->>'unit_cost'),0)
    ) order by i.created_at) filter(where i.id is not null),'[]'::jsonb)
  )
  from public.erp_warehouse_transfers t
  left join public.erp_warehouse_transfer_items i
    on i.company_id=t.company_id
   and coalesce(i.data->>'transferId',i.data->>'transfer_id')=t.id
   and not i.is_deleted
  left join public.erp_inventory p
    on p.company_id=t.company_id
   and p.id=coalesce(i.data->>'productId',i.data->>'product_id')
   and not p.is_deleted
  left join public.erp_warehouses wf
    on wf.company_id=t.company_id
   and wf.id=coalesce(t.data->>'fromWarehouseId',t.data->>'from_warehouse_id')
   and not wf.is_deleted
  left join public.erp_warehouses wt
    on wt.company_id=t.company_id
   and wt.id=coalesce(t.data->>'toWarehouseId',t.data->>'to_warehouse_id')
   and not wt.is_deleted
  where t.company_id=p_company_id and not t.is_deleted
    and public.erp_active_company_context(p_company_id) is not null
  group by t.company_id,t.id,t.data,t.created_at,wf.data,wt.data
  order by coalesce(
    public.erp_try_timestamptz(t.data->>'transferDate',t.created_at),t.created_at
  ) desc,t.created_at desc;
$$;

create or replace function public.erp_delete_inventory_warehouse_transfer(
  p_company_id uuid,p_transfer_id text,p_reason text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  transfer_row public.erp_warehouse_transfers%rowtype;
  item_row record;
  source_stock public.erp_warehouse_stock%rowtype;
  target_stock public.erp_warehouse_stock%rowtype;
  source_id text;
  target_id text;
  product_id text;
  qty numeric;
  unit_cost numeric;
  source_qty numeric;
  source_avg numeric;
  target_qty numeric;
  target_avg numeric;
  target_reserved numeric;
  source_new_avg numeric;
  target_new_avg numeric;
  target_new_value numeric;
  now_value timestamptz:=now();
  reason_value text:=coalesce(nullif(btrim(p_reason),''),'Delete product warehouse transfer and reverse stock');
  v_batch uuid:=gen_random_uuid();
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['inventory.transfer.delete']
  );
  select * into transfer_row
  from public.erp_warehouse_transfers
  where company_id=p_company_id and id=p_transfer_id and not is_deleted
  for update;
  if not found then return; end if;

  source_id:=coalesce(
    transfer_row.data->>'fromWarehouseId',transfer_row.data->>'from_warehouse_id'
  );
  target_id:=coalesce(
    transfer_row.data->>'toWarehouseId',transfer_row.data->>'to_warehouse_id'
  );
  if source_id is null or target_id is null or source_id=target_id then
    raise exception 'warehouse_transfer_invalid_warehouse_link';
  end if;

  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_warehouse_transfers',true);
  perform set_config('qualityline.deletion_root_id',p_transfer_id,true);
  perform set_config('qualityline.deletion_reason',reason_value,true);

  if lower(coalesce(transfer_row.data->>'status','completed'))<>'reversed' then
    for item_row in
      select *
      from public.erp_warehouse_transfer_items
      where company_id=p_company_id and not is_deleted
        and coalesce(data->>'transferId',data->>'transfer_id')=p_transfer_id
      order by id
      for update
    loop
      product_id:=coalesce(item_row.data->>'productId',item_row.data->>'product_id');
      qty:=public.erp_try_numeric(item_row.data->>'quantity',0);
      unit_cost:=public.erp_try_numeric(
        coalesce(item_row.data->>'unitCost',item_row.data->>'unit_cost'),0
      );
      if product_id is null or qty<=0 then
        raise exception 'warehouse_transfer_invalid_item';
      end if;

      source_stock:=public.erp_inventory_ensure_stock(
        p_company_id,source_id,product_id
      );
      target_stock:=public.erp_inventory_ensure_stock(
        p_company_id,target_id,product_id
      );
      source_qty:=public.erp_try_numeric(source_stock.data->>'quantity',0);
      source_avg:=public.erp_try_numeric(source_stock.data->>'averageUnitCost',0);
      target_qty:=public.erp_try_numeric(target_stock.data->>'quantity',0);
      target_avg:=public.erp_try_numeric(target_stock.data->>'averageUnitCost',0);
      target_reserved:=public.erp_try_numeric(target_stock.data->>'reservedQuantity',0);

      if target_qty-qty<target_reserved or target_qty<qty then
        raise exception 'warehouse_transfer_has_later_consumption:%',product_id;
      end if;

      source_new_avg:=case
        when source_qty+qty>0 then ((source_qty*source_avg)+(qty*unit_cost))/(source_qty+qty)
        else unit_cost
      end;
      target_new_value:=(target_qty*target_avg)-(qty*unit_cost);
      target_new_avg:=case
        when target_qty-qty>0 then greatest(target_new_value,0)/(target_qty-qty)
        else 0
      end;

      update public.erp_warehouse_stock
         set data=data||jsonb_build_object(
               'quantity',(source_qty+qty)::int,
               'averageUnitCost',source_new_avg,
               'updatedAt',now_value
             ),updated_at=now_value,updated_by=auth.uid()
       where company_id=p_company_id and id=source_stock.id;
      update public.erp_warehouse_stock
         set data=data||jsonb_build_object(
               'quantity',(target_qty-qty)::int,
               'averageUnitCost',target_new_avg,
               'updatedAt',now_value
             ),updated_at=now_value,updated_by=auth.uid()
       where company_id=p_company_id and id=target_stock.id;

      perform public.erp_inventory_insert_movement(
        p_company_id,product_id,target_id,'transfer_delete_out',-qty,
        unit_cost,'warehouse_transfer_delete',p_transfer_id,reason_value
      );
      perform public.erp_inventory_insert_movement(
        p_company_id,product_id,source_id,'transfer_delete_in',qty,
        unit_cost,'warehouse_transfer_delete',p_transfer_id,reason_value
      );
      perform public.erp_inventory_refresh_product(p_company_id,product_id);
    end loop;
  end if;

  update public.erp_inventory_movements
     set data=data||jsonb_build_object(
           'sourceTransferDeletedAt',now_value,
           'sourceTransferDeleteReason',reason_value
         ),updated_at=now_value,updated_by=auth.uid()
   where company_id=p_company_id and not is_deleted
     and lower(coalesce(data->>'referenceType',data->>'reference_type',''))='warehouse_transfer'
     and coalesce(data->>'referenceId',data->>'reference_id')=p_transfer_id;

  update public.erp_warehouse_transfer_items
     set is_deleted=true,deleted_at=now_value,updated_at=now_value,updated_by=auth.uid(),
         data=data||jsonb_build_object('deletedAt',now_value,'deleteReason',reason_value)
   where company_id=p_company_id and not is_deleted
     and coalesce(data->>'transferId',data->>'transfer_id')=p_transfer_id;

  update public.erp_warehouse_transfers
     set is_deleted=true,deleted_at=now_value,updated_at=now_value,updated_by=auth.uid(),
         data=data||jsonb_build_object(
           'status','reversed','deletedAt',now_value,'deleteReason',reason_value
         )
   where company_id=p_company_id and id=p_transfer_id and not is_deleted;

  update public.erp_universal_recycle_bin
     set relation_context=relation_context||jsonb_build_object(
       'warehouseTransferType','product',
       'stockReversed',true,
       'fromWarehouseId',source_id,
       'toWarehouseId',target_id
     )
   where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

create or replace function public.erp_delete_car_warehouse_transfer(
  p_company_id uuid,p_transfer_id text,p_user_name text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  transfer_row public.erp_car_warehouse_transfers%rowtype;
  current_warehouse text;
  car_status text;
  sales_order_id text;
  now_value timestamptz:=clock_timestamp();
  v_batch uuid:=gen_random_uuid();
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['cars.transfer.delete']
  );
  select * into transfer_row
  from public.erp_car_warehouse_transfers
  where company_id=p_company_id and id=p_transfer_id and not is_deleted
  for update;
  if not found then return; end if;

  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_car_warehouse_transfers',true);
  perform set_config('qualityline.deletion_root_id',p_transfer_id,true);
  perform set_config('qualityline.deletion_reason','Delete vehicle warehouse transfer',true);

  if lower(coalesce(transfer_row.data->>'status','completed'))='completed' then
    select
      coalesce(data->>'warehouseId',data->>'warehouse_id'),
      lower(btrim(coalesce(data->>'status',''))),
      nullif(btrim(coalesce(data->>'salesOrderId',data->>'sales_order_id','')),'')
      into current_warehouse,car_status,sales_order_id
    from public.erp_cars
    where company_id=p_company_id
      and id=coalesce(transfer_row.data->>'carId',transfer_row.data->>'car_id')
      and not is_deleted
    for update;
    if not found then raise exception 'vehicle_not_found'; end if;
    if current_warehouse<>coalesce(
      transfer_row.data->>'toWarehouseId',transfer_row.data->>'to_warehouse_id'
    ) then
      raise exception 'vehicle_transfer_has_later_movement';
    end if;
    if car_status not in ('available','متوفرة','متوفر','متاحة') or sales_order_id is not null then
      raise exception 'vehicle_transfer_is_linked_to_sales';
    end if;

    update public.erp_cars
       set data=(data-'warehouseId'-'warehouse_id')||jsonb_build_object(
             'warehouseId',coalesce(transfer_row.data->>'fromWarehouseId',transfer_row.data->>'from_warehouse_id'),
             'warehouse_id',coalesce(transfer_row.data->>'fromWarehouseId',transfer_row.data->>'from_warehouse_id'),
             'updatedAt',now_value
           ),updated_at=now_value,updated_by=auth.uid()
     where company_id=p_company_id
       and id=coalesce(transfer_row.data->>'carId',transfer_row.data->>'car_id');

    insert into public.erp_car_history_events(
      company_id,car_id,event_type,warehouse_before,warehouse_after,
      reference_type,reference_id,notes,event_date
    ) values(
      p_company_id,
      coalesce(transfer_row.data->>'carId',transfer_row.data->>'car_id'),
      'warehouse_transfer_deleted',
      coalesce(transfer_row.data->>'toWarehouseId',transfer_row.data->>'to_warehouse_id'),
      coalesce(transfer_row.data->>'fromWarehouseId',transfer_row.data->>'from_warehouse_id'),
      'car_warehouse_transfer_delete',p_transfer_id,
      coalesce(nullif(p_user_name,''),'system'),now_value
    );
  end if;

  update public.erp_car_warehouse_transfers
     set is_deleted=true,deleted_at=now_value,updated_at=now_value,updated_by=auth.uid(),
         data=data||jsonb_build_object(
           'status','reversed','deletedByUserName',p_user_name,
           'deletedAt',now_value,'deleteReason','Delete vehicle warehouse transfer'
         )
   where company_id=p_company_id and id=p_transfer_id and not is_deleted;

  update public.erp_universal_recycle_bin
     set relation_context=relation_context||jsonb_build_object(
       'warehouseTransferType','vehicle','vehicleWarehouseRestored',true
     )
   where company_id=p_company_id and deletion_batch_id=v_batch;
end;
$$;

revoke all on function public.erp_v66_reverse_maintenance_stock(uuid,uuid,text) from public,anon;
grant execute on function public.erp_v66_reverse_maintenance_stock(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_advance_cloud_maintenance_workflow(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_cancel_cloud_maintenance_order(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_record_cloud_maintenance_payment(uuid,uuid,numeric,text,numeric,text) to authenticated,service_role;
grant execute on function public.erp_delete_cloud_maintenance_order(uuid,uuid,text) to authenticated,service_role;
grant execute on function public.erp_list_inventory_warehouse_transfers(uuid) to authenticated,service_role;
grant execute on function public.erp_delete_inventory_warehouse_transfer(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_delete_car_warehouse_transfer(uuid,text,text) to authenticated,service_role;

commit;
