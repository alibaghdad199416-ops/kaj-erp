begin;

-- V6.7: one warehouse-transfer document for both the source and destination.
-- Editing keeps the same transfer id/number and atomically rebuilds stock,
-- movement, scrap-accounting, and item links according to the document status.

create or replace function public.erp_v67_retire_transfer_movements(
  p_company_id uuid,
  p_transfer_id text,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_movement record;
  v_journal record;
  v_now timestamptz:=now();
begin
  for v_movement in
    select im.id
    from public.erp_inventory_movements as im
    where im.company_id=p_company_id
      and not im.is_deleted
      and lower(coalesce(im.data->>'referenceType',im.data->>'reference_type',''))='warehouse_transfer'
      and coalesce(im.data->>'referenceId',im.data->>'reference_id')=p_transfer_id
    for update
  loop
    for v_journal in
      select je.id
      from public.erp_journal_entries as je
      where je.company_id=p_company_id
        and not je.is_deleted
        and lower(coalesce(je.data->>'referenceType',je.data->>'reference_type',''))='scrap_warehouse'
        and coalesce(je.data->>'referenceId',je.data->>'reference_id')=v_movement.id
      for update
    loop
      perform public.erp_v65_soft_delete_journal(
        p_company_id,v_journal.id,coalesce(p_reason,'Rebuild warehouse transfer')
      );
    end loop;

    update public.erp_inventory_movements as im
       set is_deleted=true,
           deleted_at=v_now,
           updated_at=v_now,
           updated_by=auth.uid(),
           data=im.data||jsonb_build_object(
             'supersededAt',v_now,
             'supersededReason',coalesce(p_reason,'Rebuild warehouse transfer')
           )
     where im.company_id=p_company_id
       and im.id=v_movement.id
       and not im.is_deleted;
  end loop;
end;
$$;

create or replace function public.erp_v67_reverse_product_transfer_effect(
  p_company_id uuid,
  p_transfer_id text,
  p_reason text default null,
  p_write_reversal_movements boolean default true
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_transfer public.erp_warehouse_transfers%rowtype;
  v_item record;
  v_source_stock public.erp_warehouse_stock%rowtype;
  v_target_stock public.erp_warehouse_stock%rowtype;
  v_source_id text;
  v_target_id text;
  v_product_id text;
  v_qty numeric;
  v_unit_cost numeric;
  v_source_qty numeric;
  v_source_avg numeric;
  v_target_qty numeric;
  v_target_avg numeric;
  v_target_reserved numeric;
  v_source_new_avg numeric;
  v_target_new_value numeric;
  v_target_new_avg numeric;
  v_now timestamptz:=now();
begin
  select wt.* into v_transfer
  from public.erp_warehouse_transfers as wt
  where wt.company_id=p_company_id
    and wt.id=p_transfer_id
    and not wt.is_deleted
  for update;
  if not found then return; end if;

  if lower(coalesce(v_transfer.data->>'status','completed')) in ('draft','reversed','cancelled') then
    return;
  end if;

  v_source_id:=coalesce(v_transfer.data->>'fromWarehouseId',v_transfer.data->>'from_warehouse_id');
  v_target_id:=coalesce(v_transfer.data->>'toWarehouseId',v_transfer.data->>'to_warehouse_id');
  if nullif(v_source_id,'') is null or nullif(v_target_id,'') is null or v_source_id=v_target_id then
    raise exception 'warehouse_transfer_invalid_warehouse_link';
  end if;

  for v_item in
    select wi.*
    from public.erp_warehouse_transfer_items as wi
    where wi.company_id=p_company_id
      and not wi.is_deleted
      and coalesce(wi.data->>'transferId',wi.data->>'transfer_id')=p_transfer_id
    order by wi.id
    for update
  loop
    v_product_id:=coalesce(v_item.data->>'productId',v_item.data->>'product_id');
    v_qty:=public.erp_try_numeric(v_item.data->>'quantity',0);
    v_unit_cost:=public.erp_try_numeric(
      coalesce(v_item.data->>'unitCost',v_item.data->>'unit_cost'),0
    );
    if nullif(v_product_id,'') is null or v_qty<=0 then
      raise exception 'warehouse_transfer_invalid_item';
    end if;

    v_source_stock:=public.erp_inventory_ensure_stock(p_company_id,v_source_id,v_product_id);
    v_target_stock:=public.erp_inventory_ensure_stock(p_company_id,v_target_id,v_product_id);
    v_source_qty:=public.erp_try_numeric(v_source_stock.data->>'quantity',0);
    v_source_avg:=public.erp_try_numeric(v_source_stock.data->>'averageUnitCost',0);
    v_target_qty:=public.erp_try_numeric(v_target_stock.data->>'quantity',0);
    v_target_avg:=public.erp_try_numeric(v_target_stock.data->>'averageUnitCost',0);
    v_target_reserved:=public.erp_try_numeric(v_target_stock.data->>'reservedQuantity',0);

    if v_target_qty<v_qty or v_target_qty-v_qty<v_target_reserved then
      raise exception 'warehouse_transfer_has_later_consumption:%',v_product_id;
    end if;

    v_source_new_avg:=case
      when v_source_qty+v_qty>0 then
        ((v_source_qty*v_source_avg)+(v_qty*v_unit_cost))/(v_source_qty+v_qty)
      else v_unit_cost end;
    v_target_new_value:=(v_target_qty*v_target_avg)-(v_qty*v_unit_cost);
    v_target_new_avg:=case
      when v_target_qty-v_qty>0 then greatest(v_target_new_value,0)/(v_target_qty-v_qty)
      else 0 end;

    update public.erp_warehouse_stock as ws
       set data=ws.data||jsonb_build_object(
             'quantity',(v_source_qty+v_qty)::int,
             'averageUnitCost',v_source_new_avg,
             'updatedAt',v_now
           ),
           updated_at=v_now,
           updated_by=auth.uid()
     where ws.company_id=p_company_id and ws.id=v_source_stock.id;

    update public.erp_warehouse_stock as ws
       set data=ws.data||jsonb_build_object(
             'quantity',(v_target_qty-v_qty)::int,
             'averageUnitCost',v_target_new_avg,
             'updatedAt',v_now
           ),
           updated_at=v_now,
           updated_by=auth.uid()
     where ws.company_id=p_company_id and ws.id=v_target_stock.id;

    if p_write_reversal_movements then
      perform public.erp_inventory_insert_movement(
        p_company_id,v_product_id,v_target_id,'transfer_edit_reverse_out',-v_qty,
        v_unit_cost,'warehouse_transfer_edit',p_transfer_id,p_reason
      );
      perform public.erp_inventory_insert_movement(
        p_company_id,v_product_id,v_source_id,'transfer_edit_reverse_in',v_qty,
        v_unit_cost,'warehouse_transfer_edit',p_transfer_id,p_reason
      );
    end if;
    perform public.erp_inventory_refresh_product(p_company_id,v_product_id);
  end loop;
end;
$$;

create or replace function public.erp_v67_apply_product_transfer_effect(
  p_company_id uuid,
  p_transfer_id text,
  p_from_warehouse_id text,
  p_to_warehouse_id text,
  p_items jsonb,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_line jsonb;
  v_source public.erp_warehouse_stock%rowtype;
  v_target public.erp_warehouse_stock%rowtype;
  v_product_id text;
  v_qty numeric;
  v_source_qty numeric;
  v_source_reserved numeric;
  v_source_cost numeric;
  v_target_qty numeric;
  v_target_cost numeric;
  v_target_new_avg numeric;
  v_item_id text;
  v_items jsonb:='[]'::jsonb;
  v_now timestamptz:=now();
begin
  if nullif(btrim(p_from_warehouse_id),'') is null
     or nullif(btrim(p_to_warehouse_id),'') is null
     or p_from_warehouse_id=p_to_warehouse_id then
    raise exception 'warehouse_transfer_invalid_warehouse_link';
  end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
    raise exception 'warehouse_transfer_requires_items';
  end if;

  for v_line in select value from jsonb_array_elements(p_items)
  loop
    v_product_id:=coalesce(nullif(v_line->>'productId',''),nullif(v_line->>'product_id',''));
    v_qty:=public.erp_try_numeric(v_line->>'quantity',0);
    if v_product_id is null or v_qty<=0 then
      raise exception 'warehouse_transfer_invalid_item';
    end if;
    if exists(
      select 1 from jsonb_array_elements(v_items) e
      where e->>'productId'=v_product_id
    ) then
      raise exception 'warehouse_transfer_duplicate_product:%',v_product_id;
    end if;

    v_source:=public.erp_inventory_ensure_stock(p_company_id,p_from_warehouse_id,v_product_id);
    v_target:=public.erp_inventory_ensure_stock(p_company_id,p_to_warehouse_id,v_product_id);
    v_source_qty:=public.erp_try_numeric(v_source.data->>'quantity',0);
    v_source_reserved:=public.erp_try_numeric(v_source.data->>'reservedQuantity',0);
    v_source_cost:=public.erp_try_numeric(v_source.data->>'averageUnitCost',0);
    if v_source_qty-v_source_reserved<v_qty then
      raise exception 'warehouse_transfer_insufficient_stock:%',v_product_id;
    end if;
    v_target_qty:=public.erp_try_numeric(v_target.data->>'quantity',0);
    v_target_cost:=public.erp_try_numeric(v_target.data->>'averageUnitCost',0);
    v_target_new_avg:=case
      when v_target_qty+v_qty>0 then
        ((v_target_qty*v_target_cost)+(v_qty*v_source_cost))/(v_target_qty+v_qty)
      else v_source_cost end;

    update public.erp_warehouse_stock as ws
       set data=ws.data||jsonb_build_object(
             'quantity',(v_source_qty-v_qty)::int,
             'updatedAt',v_now
           ),
           updated_at=v_now,
           updated_by=auth.uid()
     where ws.company_id=p_company_id and ws.id=v_source.id;
    update public.erp_warehouse_stock as ws
       set data=ws.data||jsonb_build_object(
             'quantity',(v_target_qty+v_qty)::int,
             'averageUnitCost',v_target_new_avg,
             'updatedAt',v_now
           ),
           updated_at=v_now,
           updated_by=auth.uid()
     where ws.company_id=p_company_id and ws.id=v_target.id;

    v_item_id:=gen_random_uuid()::text;
    insert into public.erp_warehouse_transfer_items(
      company_id,id,data,created_by,updated_by
    ) values(
      p_company_id,v_item_id,jsonb_build_object(
        'transferId',p_transfer_id,
        'productId',v_product_id,
        'quantity',v_qty,
        'unitCost',v_source_cost,
        'fromWarehouseId',p_from_warehouse_id,
        'toWarehouseId',p_to_warehouse_id,
        'notes',p_notes,
        'createdAt',v_now
      ),auth.uid(),auth.uid()
    );

    perform public.erp_inventory_insert_movement(
      p_company_id,v_product_id,p_from_warehouse_id,'transfer_out',-v_qty,
      v_source_cost,'warehouse_transfer',p_transfer_id,p_notes
    );
    perform public.erp_inventory_insert_movement(
      p_company_id,v_product_id,p_to_warehouse_id,'transfer_in',v_qty,
      v_source_cost,'warehouse_transfer',p_transfer_id,p_notes
    );
    perform public.erp_inventory_refresh_product(p_company_id,v_product_id);

    v_items:=v_items||jsonb_build_array(jsonb_build_object(
      'id',v_item_id,'productId',v_product_id,'quantity',v_qty,'unitCost',v_source_cost
    ));
  end loop;
  return v_items;
end;
$$;

create or replace function public.erp_update_inventory_warehouse_transfer(
  p_company_id uuid,
  p_transfer_id text,
  p_from_warehouse_id text,
  p_to_warehouse_id text,
  p_items jsonb,
  p_notes text default null,
  p_status text default 'completed'
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_transfer public.erp_warehouse_transfers%rowtype;
  v_status text:=lower(coalesce(nullif(btrim(p_status),''),'completed'));
  v_items jsonb:='[]'::jsonb;
  v_now timestamptz:=now();
  v_reason text:='Edit product warehouse transfer and rebuild linked stock movements';
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['inventory.transfer']
  );
  if v_status not in ('draft','completed') then
    raise exception 'warehouse_transfer_invalid_status';
  end if;

  select wt.* into v_transfer
  from public.erp_warehouse_transfers as wt
  where wt.company_id=p_company_id and wt.id=p_transfer_id and not wt.is_deleted
  for update;
  if not found then raise exception 'warehouse_transfer_not_found'; end if;
  if lower(coalesce(v_transfer.data->>'status','completed')) in ('reversed','cancelled') then
    raise exception 'warehouse_transfer_not_editable';
  end if;

  perform public.erp_v67_reverse_product_transfer_effect(
    p_company_id,p_transfer_id,v_reason,true
  );
  perform public.erp_v67_retire_transfer_movements(
    p_company_id,p_transfer_id,v_reason
  );

  update public.erp_warehouse_transfer_items as wi
     set is_deleted=true,
         deleted_at=v_now,
         updated_at=v_now,
         updated_by=auth.uid(),
         data=wi.data||jsonb_build_object('supersededAt',v_now,'supersededReason',v_reason)
   where wi.company_id=p_company_id
     and not wi.is_deleted
     and coalesce(wi.data->>'transferId',wi.data->>'transfer_id')=p_transfer_id;

  if v_status='completed' then
    v_items:=public.erp_v67_apply_product_transfer_effect(
      p_company_id,p_transfer_id,p_from_warehouse_id,p_to_warehouse_id,p_items,p_notes
    );
  else
    if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
      raise exception 'warehouse_transfer_requires_items';
    end if;
    insert into public.erp_warehouse_transfer_items(company_id,id,data,created_by,updated_by)
    select p_company_id,gen_random_uuid()::text,jsonb_build_object(
      'transferId',p_transfer_id,
      'productId',coalesce(value->>'productId',value->>'product_id'),
      'quantity',public.erp_try_numeric(value->>'quantity',0),
      'unitCost',public.erp_try_numeric(coalesce(value->>'unitCost',value->>'unit_cost'),0),
      'fromWarehouseId',p_from_warehouse_id,
      'toWarehouseId',p_to_warehouse_id,
      'notes',p_notes,
      'createdAt',v_now
    ),auth.uid(),auth.uid()
    from jsonb_array_elements(p_items);
    v_items:=p_items;
  end if;

  update public.erp_warehouse_transfers as wt
     set data=wt.data||jsonb_build_object(
           'fromWarehouseId',p_from_warehouse_id,
           'toWarehouseId',p_to_warehouse_id,
           'notes',p_notes,
           'status',v_status,
           'lineCount',jsonb_array_length(v_items),
           'updatedAt',v_now,
           'updatedByUserId',auth.uid()::text,
           'sourceAndDestinationInOneDocument',true
         ),
         updated_at=v_now,
         updated_by=auth.uid()
   where wt.company_id=p_company_id and wt.id=p_transfer_id;

  return jsonb_build_object(
    'transferId',p_transfer_id,
    'transferNumber',coalesce(v_transfer.data->>'transferNumber',v_transfer.data->>'transfer_number',p_transfer_id),
    'status',v_status,
    'fromWarehouseId',p_from_warehouse_id,
    'toWarehouseId',p_to_warehouse_id,
    'items',v_items,
    'updatedAt',v_now
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
  v_reason text:=coalesce(nullif(btrim(p_reason),''),'Delete product warehouse transfer and reverse all links');
  v_now timestamptz:=now();
  v_batch uuid:=gen_random_uuid();
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,array['inventory.transfer.delete']
  );
  select wt.* into v_transfer
  from public.erp_warehouse_transfers as wt
  where wt.company_id=p_company_id and wt.id=p_transfer_id
  for update;
  if not found or v_transfer.is_deleted then return; end if;

  perform set_config('qualityline.deletion_batch_id',v_batch::text,true);
  perform set_config('qualityline.deletion_root_table','erp_warehouse_transfers',true);
  perform set_config('qualityline.deletion_root_id',p_transfer_id,true);
  perform set_config('qualityline.deletion_reason',v_reason,true);

  perform public.erp_v67_reverse_product_transfer_effect(
    p_company_id,p_transfer_id,v_reason,true
  );
  perform public.erp_v67_retire_transfer_movements(
    p_company_id,p_transfer_id,v_reason
  );

  update public.erp_warehouse_transfer_items as wi
     set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
         data=wi.data||jsonb_build_object('deletedAt',v_now,'deleteReason',v_reason)
   where wi.company_id=p_company_id and not wi.is_deleted
     and coalesce(wi.data->>'transferId',wi.data->>'transfer_id')=p_transfer_id;

  update public.erp_warehouse_transfers as wt
     set is_deleted=true,deleted_at=v_now,updated_at=v_now,updated_by=auth.uid(),
         data=wt.data||jsonb_build_object(
           'status','reversed','deletedAt',v_now,'deleteReason',v_reason,
           'sourceAndDestinationInOneDocument',true
         )
   where wt.company_id=p_company_id and wt.id=p_transfer_id and not wt.is_deleted;

  update public.erp_universal_recycle_bin
     set relation_context=relation_context||jsonb_build_object(
       'warehouseTransferType','product',
       'stockReversed',true,
       'movementLinksRetired',true,
       'sourceAndDestinationInOneDocument',true
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
    'transferId',t.id,
    'documentKind','warehouse_transfer',
    'sourceAndDestinationInOneDocument',true,
    'transferNumber',coalesce(t.data->>'transferNumber',t.data->>'transfer_number',t.id),
    'transferDate',coalesce(t.data->>'transferDate',t.data->>'transfer_date',t.created_at::text),
    'fromWarehouseId',coalesce(t.data->>'fromWarehouseId',t.data->>'from_warehouse_id'),
    'fromWarehouseCode',coalesce(wf.data->>'code',''),
    'fromWarehouseName',coalesce(wf.data->>'name',''),
    'fromWarehouseAddress',coalesce(wf.data->>'address',''),
    'toWarehouseId',coalesce(t.data->>'toWarehouseId',t.data->>'to_warehouse_id'),
    'toWarehouseCode',coalesce(wt.data->>'code',''),
    'toWarehouseName',coalesce(wt.data->>'name',''),
    'toWarehouseAddress',coalesce(wt.data->>'address',''),
    'status',coalesce(t.data->>'status','completed'),
    'notes',coalesce(t.data->>'notes',''),
    'lineCount',coalesce(nullif(public.erp_try_integer(t.data->>'lineCount',0),0),count(i.id)::int),
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'id',i.id,
      'productId',coalesce(i.data->>'productId',i.data->>'product_id'),
      'productName',coalesce(p.data->>'name',p.data->>'nameAr',p.data->>'name_ar',''),
      'productCode',coalesce(p.data->>'code',p.data->>'productNumber',''),
      'category',coalesce(p.data->>'category',''),
      'unit',coalesce(p.data->>'unit',''),
      'currency',coalesce(p.data->>'costCurrency',p.data->>'currency','USD'),
      'quantity',public.erp_try_numeric(i.data->>'quantity',0),
      'unitCost',public.erp_try_numeric(coalesce(i.data->>'unitCost',i.data->>'unit_cost'),0)
    ) order by i.created_at) filter(where i.id is not null),'[]'::jsonb)
  )
  from public.erp_warehouse_transfers as t
  left join public.erp_warehouse_transfer_items as i
    on i.company_id=t.company_id
   and coalesce(i.data->>'transferId',i.data->>'transfer_id')=t.id
   and not i.is_deleted
  left join public.erp_inventory as p
    on p.company_id=t.company_id
   and p.id=coalesce(i.data->>'productId',i.data->>'product_id')
   and not p.is_deleted
  left join public.erp_warehouses as wf
    on wf.company_id=t.company_id
   and wf.id=coalesce(t.data->>'fromWarehouseId',t.data->>'from_warehouse_id')
   and not wf.is_deleted
  left join public.erp_warehouses as wt
    on wt.company_id=t.company_id
   and wt.id=coalesce(t.data->>'toWarehouseId',t.data->>'to_warehouse_id')
   and not wt.is_deleted
  where t.company_id=p_company_id
    and not t.is_deleted
    and public.erp_active_company_context(p_company_id) is not null
  group by t.company_id,t.id,t.data,t.created_at,wf.data,wt.data
  order by coalesce(public.erp_try_timestamptz(t.data->>'transferDate',t.created_at),t.created_at) desc,
           t.created_at desc;
$$;

revoke all on function public.erp_v67_retire_transfer_movements(uuid,text,text) from public,anon,authenticated;
revoke all on function public.erp_v67_reverse_product_transfer_effect(uuid,text,text,boolean) from public,anon,authenticated;
revoke all on function public.erp_v67_apply_product_transfer_effect(uuid,text,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function public.erp_update_inventory_warehouse_transfer(uuid,text,text,text,jsonb,text,text) from public,anon;
revoke all on function public.erp_delete_inventory_warehouse_transfer(uuid,text,text) from public,anon;
revoke all on function public.erp_list_inventory_warehouse_transfers(uuid) from public,anon;
grant execute on function public.erp_update_inventory_warehouse_transfer(uuid,text,text,text,jsonb,text,text) to authenticated,service_role;
grant execute on function public.erp_delete_inventory_warehouse_transfer(uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_list_inventory_warehouse_transfers(uuid) to authenticated,service_role;

commit;
