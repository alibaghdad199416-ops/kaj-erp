begin;

-- Final 18.8.3 compatibility and warehouse-filter repair.
-- The latest completed/reversed transfer is authoritative over stale vehicle
-- master aliases. This keeps historical records filterable without rewriting
-- accounting or vehicle master data.
create or replace function public.erp_list_cloud_cars_with_warehouse(
  p_company_id uuid
) returns setof jsonb
language sql
security definer
set search_path = public
as $$
select
  c.data
  || jsonb_build_object(
    'id', c.id,
    'warehouseId', resolved.canonical_warehouse_id,
    'warehouse_id', resolved.canonical_warehouse_id,
    'currentWarehouseId', resolved.canonical_warehouse_id,
    'current_warehouse_id', resolved.canonical_warehouse_id,
    'warehouseCode', coalesce(resolved.warehouse_code,''),
    'warehouseName', coalesce(resolved.warehouse_name,'')
  )
from public.erp_cars c
left join lateral (
  select
    t.data->>'fromWarehouseId' from_warehouse_id,
    t.data->>'toWarehouseId' to_warehouse_id,
    lower(coalesce(t.data->>'status','completed')) transfer_status
  from public.erp_car_warehouse_transfers t
  where t.company_id = c.company_id
    and not t.is_deleted
    and coalesce(t.data->>'carId',t.data->>'car_id') = c.id
    and lower(coalesce(t.data->>'status','completed')) in ('completed','reversed')
  order by
    public.erp_try_timestamptz(t.data->>'transferDate',t.created_at) desc,
    t.created_at desc
  limit 1
) latest on true
left join lateral (
  select coalesce(
    case when latest.transfer_status = 'reversed'
      then nullif(btrim(latest.from_warehouse_id),'')
      else nullif(btrim(latest.to_warehouse_id),'')
    end,
    nullif(btrim(c.data->>'currentWarehouseId'),''),
    nullif(btrim(c.data->>'current_warehouse_id'),''),
    nullif(btrim(c.data->>'warehouseId'),''),
    nullif(btrim(c.data->>'warehouse_id'),''),
    nullif(btrim(c.data->>'lastWarehouseId'),''),
    nullif(btrim(c.data->>'last_warehouse_id'),''),
    nullif(btrim(c.data->>'warehouseCode'),''),
    nullif(btrim(c.data->>'warehouseName'),'')
  ) reference
) candidate on true
left join lateral (
  select w.id,w.data->>'code' code,w.data->>'name' name
  from public.erp_warehouses w
  where w.company_id = c.company_id
    and not w.is_deleted
    and (
      w.id = candidate.reference
      or lower(btrim(coalesce(w.data->>'code',''))) = lower(btrim(candidate.reference))
      or lower(btrim(coalesce(w.data->>'name',''))) = lower(btrim(candidate.reference))
      or regexp_replace(lower(coalesce(w.data->>'code','') || coalesce(w.data->>'name','')), '[[:space:][:punct:]]+', '', 'g')
         = regexp_replace(lower(coalesce(candidate.reference,'')), '[[:space:][:punct:]]+', '', 'g')
    )
  order by case when w.id = candidate.reference then 0 else 1 end
  limit 1
) warehouse on true
left join lateral (
  select
    coalesce(warehouse.id,candidate.reference) canonical_warehouse_id,
    warehouse.code warehouse_code,
    warehouse.name warehouse_name
) resolved on true
where c.company_id = p_company_id
  and not c.is_deleted
  and public.is_active_company_member(p_company_id)
order by c.created_at desc;
$$;


revoke all on function public.erp_list_cloud_cars_with_warehouse(uuid) from public,anon;
grant execute on function public.erp_list_cloud_cars_with_warehouse(uuid) to authenticated;

commit;
