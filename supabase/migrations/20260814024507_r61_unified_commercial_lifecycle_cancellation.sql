begin;

-- R61 separates creation-time stock validation from invoice-time proof.
-- A posted delivery/receipt is the authoritative physical document: invoicing
-- verifies its exact order items and quantities, but never asks a delivered
-- vehicle to still be available in its former warehouse.
create or replace function public.erp_r61_validate_approved_logistics(
  p_company_id uuid,
  p_order_id uuid,
  p_module text,
  p_allocations jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  a record;
  v_expected_type text;
  v_ordered numeric;
  v_normalized jsonb:='[]'::jsonb;
begin
  if not public.erp_is_company_member(p_company_id) then
    raise exception 'permission_denied' using errcode='42501';
  end if;
  if p_module not in ('sales','purchases') then
    raise exception 'invalid_workflow_module' using errcode='22023';
  end if;
  if jsonb_typeof(coalesce(p_allocations,'null'::jsonb))<>'array'
     or jsonb_array_length(p_allocations)=0 then
    raise exception 'approved_logistics_allocations_missing' using errcode='P0001';
  end if;

  for a in
    select x."itemType",x."itemId",x."warehouseId",sum(x.quantity) quantity
    from jsonb_to_recordset(p_allocations) as x(
      "itemType" text,"itemId" text,"description" text,
      "warehouseId" text,quantity numeric
    )
    group by 1,2,3
  loop
    if coalesce(btrim(a."itemId"),'')=''
       or coalesce(btrim(a."warehouseId"),'')=''
       or coalesce(a.quantity,0)<=0 then
      raise exception 'invalid_approved_logistics_allocation' using errcode='P0001';
    end if;

    if p_module='sales' then
      select i.item_type,i.quantity into v_expected_type,v_ordered
      from public.erp_sales_order_items_cloud i
      where i.company_id=p_company_id and i.order_id=p_order_id
        and not i.is_deleted and i.item_id=a."itemId";
    else
      select i.item_type,i.quantity into v_expected_type,v_ordered
      from public.erp_purchase_order_items_cloud i
      where i.company_id=p_company_id and i.order_id=p_order_id
        and not i.is_deleted and i.item_id=a."itemId";
    end if;
    if not found or v_expected_type is distinct from lower(btrim(a."itemType")) then
      raise exception 'approved_logistics_item_mismatch:%',a."itemId" using errcode='P0001';
    end if;
    if a.quantity>v_ordered then
      raise exception 'approved_logistics_quantity_mismatch:%',a."itemId" using errcode='P0001';
    end if;
    if lower(btrim(a."itemType"))='car' and (a.quantity<>1 or v_ordered<>1) then
      raise exception 'approved_logistics_car_identity_mismatch:%',a."itemId" using errcode='P0001';
    end if;
    v_normalized:=v_normalized||jsonb_build_array(jsonb_build_object(
      'itemType',lower(btrim(a."itemType")),'itemId',a."itemId",
      'warehouseId',a."warehouseId",'quantity',a.quantity
    ));
  end loop;
  return v_normalized;
end;
$$;

create or replace function public.erp_v736_active_logistics(
  p_company_id uuid,p_order_id uuid,p_module text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_type text; v_result jsonb;
begin
  v_type:=case when p_module='sales' then 'delivery' when p_module='purchases' then 'receipt' end;
  if v_type is null then raise exception 'invalid_workflow_module'; end if;
  with docs as (
    select d.* from public.erp_commercial_workflow_documents d
    where d.company_id=p_company_id and d.parent_id=p_order_id and d.module=p_module
      and d.document_type=v_type and lower(coalesce(d.status,'')) in ('approved','posted','completed','confirmed')
      and not d.is_deleted and (d.payload ? 'inventoryPostedAt' or d.payload ? 'postedAt' or d.payload ? 'approvedAt')
  ), latest as (select * from docs order by updated_at desc,id desc limit 1), allocations as (
    select x."itemType",x."itemId",max(x."description") description,x."warehouseId",sum(x.quantity) quantity
    from docs d cross join lateral jsonb_to_recordset(coalesce(d.payload->'allocations','[]'::jsonb))
      x("itemType" text,"itemId" text,"description" text,"warehouseId" text,quantity numeric)
    group by 1,2,4
  )
  select jsonb_build_object('id',l.id::text,'number',l.document_number,
    'documentIds',(select jsonb_agg(d.id order by d.effective_at,d.created_at,d.id) from docs d),
    'documentNumbers',(select jsonb_agg(d.document_number order by d.effective_at,d.created_at,d.id) from docs d),
    'allocations',(select jsonb_agg(jsonb_build_object('itemType',a."itemType",'itemId',a."itemId",
      'description',a.description,'warehouseId',a."warehouseId",'quantity',a.quantity)
      order by a."itemType",a."itemId",a."warehouseId") from allocations a),
    'effectiveAt',coalesce(l.effective_at,l.created_at),
    'warehouseIds',(select jsonb_agg(distinct a."warehouseId") from allocations a))
  into v_result from latest l;
  if v_result is null then raise exception 'approved_inventory_document_required'; end if;
  perform public.erp_r61_validate_approved_logistics(
    p_company_id,p_order_id,p_module,v_result->'allocations'
  );
  return v_result;
end;
$$;

create or replace function public.erp_r61_cancel_commercial_order(
  p_company_id uuid,p_order_id uuid,p_module text,p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_status text;
  v_reason text:=coalesce(nullif(btrim(p_reason),''),'Order cancelled');
  v_result jsonb;
begin
  if p_module not in ('sales','purchases') then
    raise exception 'invalid_workflow_module' using errcode='22023';
  end if;
  perform public.erp_require_any_cloud_permission(
    p_company_id,array[p_module||'.cancel',p_module||'.delete']
  );
  perform pg_advisory_xact_lock(hashtextextended(
    p_company_id::text||':'||p_module||':cancel-order:'||p_order_id::text,0
  ));

  if p_module='sales' then
    select lower(status) into v_status from public.erp_sales_orders_cloud
      where company_id=p_company_id and id=p_order_id for update;
  else
    select lower(status) into v_status from public.erp_purchase_orders_cloud
      where company_id=p_company_id and id=p_order_id for update;
  end if;
  if not found then raise exception 'order_not_found' using errcode='P0001'; end if;
  if v_status='cancelled' then
    return jsonb_build_object('ok',true,'status','cancelled','idempotent',true);
  end if;

  if p_module='sales' then
    v_result:=public.erp_delete_cloud_sales_order_v3(p_company_id,p_order_id);
    update public.erp_sales_orders_cloud set status='cancelled',is_deleted=false,
      deleted_at=null,notes=concat_ws(E'\n',nullif(notes,''),'CANCEL: '||v_reason),updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=p_order_id;
    update public.erp_sales_order_items_cloud set is_deleted=false,deleted_at=null,updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and order_id=p_order_id;
  else
    v_result:=public.erp_delete_cloud_purchase_order_v3(p_company_id,p_order_id);
    update public.erp_purchase_orders_cloud set status='cancelled',is_deleted=false,
      deleted_at=null,notes=concat_ws(E'\n',nullif(notes,''),'CANCEL: '||v_reason),updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and id=p_order_id;
    update public.erp_purchase_order_items_cloud set is_deleted=false,deleted_at=null,updated_at=now(),updated_by=auth.uid()
      where company_id=p_company_id and order_id=p_order_id;
  end if;
  perform public.erp_commercial_audit(
    p_company_id,p_module,p_order_id,p_order_id,null,
    'cancel_order',v_status,'cancelled',v_reason
  );
  return coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
    'ok',true,'status','cancelled','orderPreserved',true,
    'paymentsPreserved',true,'reason',v_reason
  );
end;
$$;

revoke all on function public.erp_r61_validate_approved_logistics(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public.erp_r61_validate_approved_logistics(uuid,uuid,text,jsonb) to service_role;
revoke all on function public.erp_v736_active_logistics(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.erp_v736_active_logistics(uuid,uuid,text) to service_role;
revoke all on function public.erp_r61_cancel_commercial_order(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.erp_r61_cancel_commercial_order(uuid,uuid,text,text) to authenticated,service_role;

commit;
