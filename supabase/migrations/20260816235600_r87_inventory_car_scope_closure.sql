-- Quality Line ERP R87
-- Forward-only record-scope closure for inventory transfers and the canonical
-- vehicle/warehouse projection used by the live Inventory & Cars UI.
begin;

create or replace function public.erp_r49_list_inventory_warehouse_transfers(p_company_id uuid)
returns setof jsonb language plpgsql stable security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'inventory.view') then
    raise exception 'permission_denied:inventory.view' using errcode='42501';
  end if;
  return query
  select jsonb_build_object(
    'id',t.id,'transferId',t.id,'documentKind','warehouse_transfer','sourceAndDestinationInOneDocument',true,
    'transferNumber',coalesce(t.data->>'transferNumber',t.data->>'transfer_number',t.id),
    'transferDate',coalesce(t.data->>'transferDate',t.data->>'transfer_date',t.created_at::text),
    'fromWarehouseId',coalesce(t.data->>'fromWarehouseId',t.data->>'from_warehouse_id'),
    'fromWarehouseCode',coalesce(wf.data->>'code',''),'fromWarehouseName',coalesce(wf.data->>'name',''),'fromWarehouseAddress',coalesce(wf.data->>'address',''),
    'toWarehouseId',coalesce(t.data->>'toWarehouseId',t.data->>'to_warehouse_id'),
    'toWarehouseCode',coalesce(wt.data->>'code',''),'toWarehouseName',coalesce(wt.data->>'name',''),'toWarehouseAddress',coalesce(wt.data->>'address',''),
    'status',nullif(btrim(coalesce(t.data->>'status','')),''),'notes',coalesce(t.data->>'notes',''),
    'lineCount',coalesce(nullif(public.erp_try_integer(t.data->>'lineCount',0),0),count(i.id)::int),
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'id',i.id,'productId',coalesce(i.data->>'productId',i.data->>'product_id'),
      'productName',coalesce(p.data->>'name',p.data->>'nameAr',p.data->>'name_ar',''),
      'productCode',coalesce(p.data->>'code',p.data->>'productNumber',''),'category',coalesce(p.data->>'category',''),'unit',coalesce(p.data->>'unit',''),
      'currency',case when upper(coalesce(nullif(p.data->>'costCurrency',''),nullif(p.data->>'currency',''))) in ('USD','IQD')
        then upper(coalesce(nullif(p.data->>'costCurrency',''),nullif(p.data->>'currency',''))) else null end,
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
  where t.company_id=p_company_id
    and not t.is_deleted
    and public.erp_r84_record_visible(p_company_id,'inventory',t.created_by,null)
  group by t.company_id,t.id,t.data,t.created_at,wf.data,wt.data
  order by coalesce(public.erp_try_timestamptz(t.data->>'transferDate',t.created_at),t.created_at) desc,t.created_at desc;
end $$;
revoke all on function public.erp_r49_list_inventory_warehouse_transfers(uuid) from public,anon;
grant execute on function public.erp_r49_list_inventory_warehouse_transfers(uuid) to authenticated,service_role;

-- The live cars page uses this richer projection instead of the generic master
-- list. Scope the car CTE itself; transfer history remains authoritative for a
-- visible car so current warehouse resolution cannot become stale.
create or replace function public.erp_r49_list_cloud_cars_with_warehouse(
  p_company_id uuid
) returns setof jsonb
language sql
security definer
set search_path = public
as $$
with cars as (
  select c.*
  from public.erp_cars c
  where c.company_id = p_company_id
    and not c.is_deleted
    and public.is_active_company_member(p_company_id)
    and public.erp_r84_record_visible(p_company_id,'cars',c.created_by,null)
)
select
  public.erp_r9_filter_result_json(
    p_company_id,
    'cars',
    c.data
    || jsonb_build_object(
    'id', c.id,
    'warehouseId', resolved.canonical_warehouse_id,
    'warehouse_id', resolved.canonical_warehouse_id,
    'currentWarehouseId', resolved.canonical_warehouse_id,
    'current_warehouse_id', resolved.canonical_warehouse_id,
    'warehouseCode', coalesce(resolved.warehouse_code,''),
    'warehouseName', coalesce(resolved.warehouse_name,''),
    'warehouseResolutionSource', resolved.resolution_source
    ),
    'cars.view'
  )
from cars c
left join lateral (
  select
    coalesce(
      nullif(btrim(t.data->>'fromWarehouseId'),''),
      nullif(btrim(t.data->>'from_warehouse_id'),''),
      nullif(btrim(t.data->>'sourceWarehouseId'),''),
      nullif(btrim(t.data->>'source_warehouse_id'),'')
    ) from_warehouse_id,
    coalesce(
      nullif(btrim(t.data->>'toWarehouseId'),''),
      nullif(btrim(t.data->>'to_warehouse_id'),''),
      nullif(btrim(t.data->>'destinationWarehouseId'),''),
      nullif(btrim(t.data->>'destination_warehouse_id'),'')
    ) to_warehouse_id,
    lower(regexp_replace(
      coalesce(nullif(btrim(t.data->>'status'),''),''),
      '[[:space:]_-]+','','g'
    )) transfer_status
  from public.erp_car_warehouse_transfers t
  where t.company_id = c.company_id
    and not t.is_deleted
    and coalesce(
      nullif(btrim(t.data->>'carId'),''),
      nullif(btrim(t.data->>'car_id'),''),
      nullif(btrim(t.data->>'vehicleId'),''),
      nullif(btrim(t.data->>'vehicle_id'),'')
    ) = c.id
    and lower(regexp_replace(
      coalesce(nullif(btrim(t.data->>'status'),''),''),
      '[[:space:]_-]+','','g'
    )) in (
      'completed','complete','done','posted','executed','منفذ','مكتمل',
      'reversed','reverse','returned','مرجع','مُرجع','معكوس'
    )
  order by
    public.erp_try_timestamptz(
      coalesce(
        nullif(t.data->>'transferDate',''),
        nullif(t.data->>'transfer_date',''),
        nullif(t.data->>'date','')
      ),
      t.created_at
    ) desc,
    t.created_at desc,
    t.id desc
  limit 1
) latest on true
left join lateral (
  select
    coalesce(
      case when latest.transfer_status in (
        'reversed','reverse','returned','مرجع','مُرجع','معكوس'
      ) then latest.from_warehouse_id else latest.to_warehouse_id end,
      nullif(btrim(c.data->>'currentWarehouseId'),''),
      nullif(btrim(c.data->>'current_warehouse_id'),''),
      nullif(btrim(c.data->>'warehouseId'),''),
      nullif(btrim(c.data->>'warehouse_id'),''),
      nullif(btrim(c.data->>'lastWarehouseId'),''),
      nullif(btrim(c.data->>'last_warehouse_id'),''),
      nullif(btrim(c.data->>'warehouseCode'),''),
      nullif(btrim(c.data->>'warehouse_code'),''),
      nullif(btrim(c.data->>'warehouseName'),''),
      nullif(btrim(c.data->>'warehouse_name'),'')
    ) reference,
    case
      when latest.transfer_status is not null then 'latest_transfer'
      else 'vehicle_master'
    end resolution_source
) candidate on true
left join lateral (
  select
    w.id,
    coalesce(
      nullif(btrim(w.data->>'code'),''),
      nullif(btrim(w.data->>'warehouseCode'),''),
      nullif(btrim(w.data->>'warehouse_code'),'')
    ) code,
    coalesce(
      nullif(btrim(w.data->>'name'),''),
      nullif(btrim(w.data->>'warehouseName'),''),
      nullif(btrim(w.data->>'warehouse_name'),'')
    ) name
  from public.erp_warehouses w
  where w.company_id = c.company_id
    and not w.is_deleted
    and candidate.reference is not null
    and (
      w.id = candidate.reference
      or lower(btrim(coalesce(
        w.data->>'code',w.data->>'warehouseCode',w.data->>'warehouse_code',''
      ))) = lower(btrim(candidate.reference))
      or lower(btrim(coalesce(
        w.data->>'name',w.data->>'warehouseName',w.data->>'warehouse_name',''
      ))) = lower(btrim(candidate.reference))
      or regexp_replace(
        lower(coalesce(
          w.data->>'code',w.data->>'warehouseCode',w.data->>'warehouse_code',''
        ) || coalesce(
          w.data->>'name',w.data->>'warehouseName',w.data->>'warehouse_name',''
        )),
        '[[:space:][:punct:]]+','','g'
      ) = regexp_replace(
        lower(coalesce(candidate.reference,'')),
        '[[:space:][:punct:]]+','','g'
      )
    )
  order by case when w.id = candidate.reference then 0 else 1 end
  limit 1
) warehouse on true
left join lateral (
  select
    coalesce(warehouse.id,candidate.reference) canonical_warehouse_id,
    warehouse.code warehouse_code,
    warehouse.name warehouse_name,
    candidate.resolution_source
) resolved on true
order by c.created_at desc, c.id;
$$;
revoke all on function public.erp_r49_list_cloud_cars_with_warehouse(uuid) from public,anon;
grant execute on function public.erp_r49_list_cloud_cars_with_warehouse(uuid) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
