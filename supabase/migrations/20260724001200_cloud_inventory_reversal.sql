-- Quality Line ERP v17.12.0 P13
-- PostgreSQL-authoritative reversal for delivery and receipt inventory movements.

create or replace function public.erp_reverse_inventory_document_cloud(
  p_organization_id uuid,
  p_module text,
  p_document_id text,
  p_reason text default 'inventory document reversal'
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_workflow_id text;
  v_reference_type text;
  v_movement public.erp_cloud_inventory_movements%rowtype;
  v_reversal_id uuid;
  v_reversal_ids jsonb := '[]'::jsonb;
  v_delta numeric(20,4);
  v_now timestamptz := now();
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if not public.erp_is_active_member(p_organization_id) then raise exception 'permission_denied'; end if;
  if p_module not in ('sales','purchases') then raise exception 'invalid_module'; end if;

  v_reference_type := case when p_module='sales' then 'sales_delivery' else 'purchase_receipt' end;

  select workflow_id into v_workflow_id
  from public.erp_cloud_inventory_movements
  where organization_id=p_organization_id
    and module=p_module
    and reference_type=v_reference_type
    and reference_id=p_document_id
  limit 1;
  if v_workflow_id is null then raise exception 'cloud_inventory_document_not_found'; end if;

  for v_movement in
    select * from public.erp_cloud_inventory_movements
    where organization_id=p_organization_id
      and module=p_module
      and workflow_id=v_workflow_id
      and reference_type=v_reference_type
      and reference_id=p_document_id
      and source_movement_id not like 'REV:%'
    order by movement_date,id
    for update
  loop
    select id into v_reversal_id
    from public.erp_cloud_inventory_movements
    where organization_id=p_organization_id
      and source_movement_id='REV:'||v_movement.id::text;

    if v_reversal_id is null then
      v_delta := case when p_module='sales' then v_movement.quantity else -v_movement.quantity end;

      insert into public.erp_cloud_stock_balances(
        organization_id,warehouse_id,product_id,quantity,minimum_quantity,
        reserved_quantity,expected_incoming,expected_outgoing,average_unit_cost,
        source_updated_at,synchronized_by,synchronized_at
      ) values (
        p_organization_id,v_movement.warehouse_id,v_movement.product_id,v_delta,0,
        0,0,0,v_movement.unit_cost,v_now,auth.uid(),v_now
      ) on conflict (organization_id,warehouse_id,product_id) do update set
        quantity=public.erp_cloud_stock_balances.quantity+v_delta,
        source_updated_at=v_now,synchronized_by=auth.uid(),synchronized_at=v_now;

      insert into public.erp_cloud_inventory_movements(
        organization_id,financial_event_id,module,workflow_id,source_movement_id,
        movement_number,product_id,warehouse_id,movement_type,quantity,unit_cost,
        total_cost,reference_type,reference_id,movement_date,notes,created_by
      ) values (
        p_organization_id,v_movement.financial_event_id,p_module,v_workflow_id,
        'REV:'||v_movement.id::text,'REV-'||v_movement.movement_number,
        v_movement.product_id,v_movement.warehouse_id,
        v_movement.movement_type||'_reversal',-v_movement.quantity,
        v_movement.unit_cost,-v_movement.total_cost,
        v_reference_type||'_reversal',p_document_id,v_now,
        p_reason||coalesce(' - '||v_movement.notes,''),auth.uid()
      ) returning id into v_reversal_id;
    end if;
    v_reversal_ids := v_reversal_ids || jsonb_build_array(v_reversal_id);
  end loop;

  if p_module='sales' then
    update public.erp_sales_workflows
    set aggregate=jsonb_set(aggregate,'{delivery,status}','"cancelled"'::jsonb,true),
        version=version+1,updated_at=v_now,updated_by=auth.uid()
    where organization_id=p_organization_id and workflow_id=v_workflow_id;
  else
    update public.erp_purchase_workflows
    set aggregate=jsonb_set(aggregate,'{receipt,status}','"cancelled"'::jsonb,true),
        version=version+1,updated_at=v_now,updated_by=auth.uid()
    where organization_id=p_organization_id and workflow_id=v_workflow_id;
  end if;

  return jsonb_build_object('workflowId',v_workflow_id,'movementIds',v_reversal_ids,'duplicate',false);
end;
$$;

grant execute on function public.erp_reverse_inventory_document_cloud(uuid,text,text,text) to authenticated;
