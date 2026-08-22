begin;

-- Product transfers historically moved warehouse stock and valuation value but
-- left the remaining FIFO layer at the source warehouse. Maintenance issue
-- must consume the selected warehouse, so re-home only transfer-backed
-- remaining valuation immediately before that issue.
create function public.erp_r57_prepare_maintenance_warehouse_fifo(
  p_company_id uuid,p_issue_id uuid,p_product_id text,p_warehouse_id text,
  p_quantity numeric,p_effective_at timestamptz
) returns void language plpgsql security definer set search_path=public as $$
declare v_fifo numeric; v_needed numeric; v_capacity numeric; v_moved numeric:=0;
  v_source record; v_layer record; v_take numeric;
begin
  if exists(select 1 from public.erp_maintenance_material_issues
    where company_id=p_company_id and id=p_issue_id) then return; end if;

  select coalesce(sum(remaining_quantity),0) into v_fifo
  from public.erp_inventory_cost_layers
  where company_id=p_company_id and item_type='product' and item_id=p_product_id
    and warehouse_id=p_warehouse_id and status in ('active','consumed')
    and remaining_quantity>0 and effective_at<=coalesce(p_effective_at,now());
  v_needed:=greatest(coalesce(p_quantity,0)-v_fifo,0);
  if v_needed<=0 then return; end if;

  select greatest(coalesce(sum(public.erp_try_numeric(mi.data->>'quantity',0)),0)
    -coalesce((select sum(original_quantity) from public.erp_inventory_cost_layers
      where company_id=p_company_id and item_type='product' and item_id=p_product_id
        and warehouse_id=p_warehouse_id and source_type='maintenance_transfer_rehome'),0),0)
  into v_capacity from public.erp_inventory_movements mi
  where mi.company_id=p_company_id and not mi.is_deleted
    and coalesce(mi.data->>'productId',mi.data->>'itemId')=p_product_id
    and coalesce(mi.data->>'warehouseId',mi.data->>'warehouse_id')=p_warehouse_id
    and mi.data->>'movementType'='transfer_in';
  if v_capacity<v_needed then return; end if;

  for v_source in
    select distinct mo.data->>'warehouseId' warehouse_id
    from public.erp_inventory_movements mi
    join public.erp_inventory_movements mo on mo.company_id=mi.company_id and not mo.is_deleted
      and mo.data->>'referenceType'='warehouse_transfer'
      and mo.data->>'referenceId'=mi.data->>'referenceId'
      and mo.data->>'movementType'='transfer_out'
      and coalesce(mo.data->>'productId',mo.data->>'itemId')=p_product_id
    where mi.company_id=p_company_id and not mi.is_deleted
      and mi.data->>'referenceType'='warehouse_transfer' and mi.data->>'movementType'='transfer_in'
      and coalesce(mi.data->>'productId',mi.data->>'itemId')=p_product_id
      and mi.data->>'warehouseId'=p_warehouse_id
  loop
    for v_layer in select * from public.erp_inventory_cost_layers l
      where l.company_id=p_company_id and l.item_type='product' and l.item_id=p_product_id
        and l.warehouse_id=v_source.warehouse_id and l.status in ('active','consumed')
        and l.remaining_quantity>0 and l.effective_at<=coalesce(p_effective_at,now())
      order by l.effective_at,l.created_at,l.id for update
    loop
      exit when v_moved>=v_needed;
      v_take:=least(v_needed-v_moved,v_layer.remaining_quantity,v_capacity-v_moved);
      exit when v_take<=0;
      update public.erp_inventory_cost_layers set
        original_quantity=original_quantity-v_take,
        remaining_quantity=remaining_quantity-v_take,
        status=case when remaining_quantity-v_take<=0 then 'consumed' else 'active' end,
        updated_at=now(),updated_by=auth.uid() where id=v_layer.id;
      insert into public.erp_inventory_cost_layers(company_id,item_type,item_id,warehouse_id,
        layer_number,effective_at,original_quantity,remaining_quantity,unit_cost,currency,
        asset_account_id,cost_expense_account_id,source_type,status,created_by,updated_by)
      values(p_company_id,'product',p_product_id,p_warehouse_id,
        'MTR-'||replace(gen_random_uuid()::text,'-',''),coalesce(p_effective_at,now()),
        v_take,v_take,v_layer.unit_cost,v_layer.currency,v_layer.asset_account_id,
        v_layer.cost_expense_account_id,'maintenance_transfer_rehome','active',auth.uid(),auth.uid());
      v_moved:=v_moved+v_take;
    end loop;
    exit when v_moved>=v_needed;
  end loop;
end $$;

alter function public.erp_r57_execute_maintenance_material_issue(uuid,uuid,uuid,uuid,text,numeric,timestamptz)
  rename to erp_r57_execute_maintenance_material_issue_pre_multi_warehouse;

create function public.erp_r57_execute_maintenance_material_issue(
  p_company_id uuid,p_order_id uuid,p_issue_id uuid,p_part_id uuid,
  p_warehouse_id text,p_quantity numeric,p_effective_at timestamptz default now()
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_product text;
begin
  select coalesce(source_product_id,product_id::text) into v_product
  from public.erp_maintenance_parts where company_id=p_company_id and id=p_part_id
    and maintenance_order_id=p_order_id and not is_deleted and line_type<>'service';
  if found then
    perform public.erp_r57_prepare_maintenance_warehouse_fifo(
      p_company_id,p_issue_id,v_product,p_warehouse_id,p_quantity,p_effective_at);
  end if;
  return public.erp_r57_execute_maintenance_material_issue_pre_multi_warehouse(
    p_company_id,p_order_id,p_issue_id,p_part_id,p_warehouse_id,p_quantity,p_effective_at);
end $$;

revoke all on function public.erp_r57_prepare_maintenance_warehouse_fifo(uuid,uuid,text,text,numeric,timestamptz) from public,anon,authenticated,service_role;
revoke all on function public.erp_r57_execute_maintenance_material_issue_pre_multi_warehouse(uuid,uuid,uuid,uuid,text,numeric,timestamptz) from public,anon,authenticated,service_role;
revoke all on function public.erp_r57_execute_maintenance_material_issue(uuid,uuid,uuid,uuid,text,numeric,timestamptz) from public,anon;
grant execute on function public.erp_r57_execute_maintenance_material_issue(uuid,uuid,uuid,uuid,text,numeric,timestamptz) to authenticated,service_role;

commit;
