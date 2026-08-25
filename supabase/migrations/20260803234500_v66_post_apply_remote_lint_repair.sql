begin;

-- Quality Line ERP V6.6.7
-- Forward-only repair for issues detected by `supabase db lint` after the
-- V6.5/V6.6 migrations were applied to the linked project.
--
-- The already-applied migrations are intentionally left untouched. This
-- migration adds the missing maintenance audit columns and replaces the stock
-- reversal helper with fully qualified identifiers so PL/pgSQL variables can
-- never shadow table columns.

alter table public.erp_maintenance_orders
  add column if not exists updated_by uuid
    references auth.users(id) on delete set null default auth.uid();

alter table public.erp_maintenance_parts
  add column if not exists updated_by uuid
    references auth.users(id) on delete set null default auth.uid();

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
  v_order public.erp_maintenance_orders%rowtype;
  v_line record;
  v_stock_row public.erp_warehouse_stock%rowtype;
  v_product_id text;
  v_warehouse_id text;
  v_issued numeric;
  v_returned numeric;
  v_quantity_to_restore numeric;
  v_current_qty numeric;
  v_current_avg numeric;
  v_new_avg numeric;
  v_now timestamptz:=now();
begin
  select mo.* into v_order
  from public.erp_maintenance_orders as mo
  where mo.company_id=p_company_id
    and mo.id=p_order_id
    and not mo.is_deleted
  for update;

  if not found then
    raise exception 'maintenance_order_not_found';
  end if;

  for v_line in
    select
      coalesce(mp.source_product_id,mp.product_id::text) as resolved_product_id,
      coalesce(
        mp.source_warehouse_id,
        mp.warehouse_id::text,
        v_order.source_warehouse_id,
        v_order.warehouse_id::text
      ) as resolved_warehouse_id,
      sum(mp.quantity)::numeric as line_quantity,
      case
        when sum(mp.quantity)>0 then
          sum(mp.quantity*mp.unit_cost)/sum(mp.quantity)
        else 0
      end as unit_cost
    from public.erp_maintenance_parts as mp
    where mp.company_id=p_company_id
      and mp.maintenance_order_id=p_order_id
      and not mp.is_deleted
      and mp.line_type<>'service'
    group by
      coalesce(mp.source_product_id,mp.product_id::text),
      coalesce(
        mp.source_warehouse_id,
        mp.warehouse_id::text,
        v_order.source_warehouse_id,
        v_order.warehouse_id::text
      )
  loop
    v_product_id:=v_line.resolved_product_id;
    v_warehouse_id:=v_line.resolved_warehouse_id;

    if v_product_id is null or v_warehouse_id is null then
      raise exception 'maintenance_stock_link_missing';
    end if;

    select coalesce(sum(abs(public.erp_try_numeric(
             coalesce(im.data->>'quantity','0'),0
           ))),0)
      into v_issued
    from public.erp_inventory_movements as im
    where im.company_id=p_company_id
      and not im.is_deleted
      and coalesce(im.data->>'referenceId',im.data->>'reference_id')=p_order_id::text
      and lower(coalesce(im.data->>'referenceType',im.data->>'reference_type',''))='maintenance_order'
      and lower(coalesce(im.data->>'movementType',im.data->>'movement_type',''))='maintenance_out'
      and coalesce(im.data->>'productId',im.data->>'product_id')=v_product_id
      and coalesce(im.data->>'warehouseId',im.data->>'warehouse_id')=v_warehouse_id;

    select coalesce(sum(abs(public.erp_try_numeric(
             coalesce(im.data->>'quantity','0'),0
           ))),0)
      into v_returned
    from public.erp_inventory_movements as im
    where im.company_id=p_company_id
      and not im.is_deleted
      and coalesce(im.data->>'referenceId',im.data->>'reference_id')=p_order_id::text
      and lower(coalesce(im.data->>'movementType',im.data->>'movement_type',''))='maintenance_return'
      and coalesce(im.data->>'productId',im.data->>'product_id')=v_product_id
      and coalesce(im.data->>'warehouseId',im.data->>'warehouse_id')=v_warehouse_id;

    v_quantity_to_restore:=greatest(v_issued-v_returned,0);
    if v_quantity_to_restore<=0 then
      continue;
    end if;

    v_stock_row:=public.erp_inventory_ensure_stock(
      p_company_id,v_warehouse_id,v_product_id
    );
    v_current_qty:=public.erp_try_numeric(v_stock_row.data->>'quantity',0);
    v_current_avg:=public.erp_try_numeric(v_stock_row.data->>'averageUnitCost',0);

    if v_current_qty+v_quantity_to_restore>0 then
      v_new_avg:=((v_current_qty*v_current_avg)+
                  (v_quantity_to_restore*v_line.unit_cost)) /
                 (v_current_qty+v_quantity_to_restore);
    else
      v_new_avg:=v_line.unit_cost;
    end if;

    update public.erp_warehouse_stock as ws
       set data=ws.data||jsonb_build_object(
             'quantity',(v_current_qty+v_quantity_to_restore)::int,
             'averageUnitCost',v_new_avg,
             'updatedAt',v_now
           ),
           updated_at=v_now,
           updated_by=auth.uid()
     where ws.company_id=p_company_id
       and ws.id=v_stock_row.id;

    perform public.erp_inventory_insert_movement(
      p_company_id,
      v_product_id,
      v_warehouse_id,
      'maintenance_return',
      v_quantity_to_restore,
      v_line.unit_cost,
      'maintenance_delete',
      p_order_id::text,
      coalesce(
        nullif(btrim(p_reason),''),
        'Delete maintenance order and restore stock'
      )
    );
    perform public.erp_inventory_refresh_product(p_company_id,v_product_id);
  end loop;

  if coalesce(v_order.car_cost_added,0)>0 then
    update public.erp_cars as c
       set data=c.data||jsonb_build_object(
             'maintenanceCost',greatest(
               public.erp_try_numeric(
                 coalesce(c.data->>'maintenanceCost',c.data->>'maintenance_cost'),
                 0
               )-v_order.car_cost_added,
               0
             ),
             'updatedAt',v_now
           ),
           updated_at=v_now,
           updated_by=auth.uid()
     where c.company_id=p_company_id
       and c.id=coalesce(v_order.source_car_id,v_order.car_id::text)
       and not c.is_deleted;

    update public.erp_maintenance_orders as mo
       set car_cost_added=0,
           updated_at=v_now,
           updated_by=auth.uid()
     where mo.company_id=p_company_id
       and mo.id=p_order_id;
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

revoke all on function public.erp_v66_reverse_maintenance_stock(uuid,uuid,text)
  from public,anon;
grant execute on function public.erp_v66_reverse_maintenance_stock(uuid,uuid,text)
  to authenticated,service_role;

commit;