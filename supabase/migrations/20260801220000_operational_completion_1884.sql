begin;

-- 18.8.4: deterministic, backward-compatible vehicle warehouse projection.
-- The latest completed/reversed transfer is authoritative. Historical vehicle
-- and transfer aliases are still accepted so filtering does not depend on the
-- generation that created a record.
create or replace function public.erp_list_cloud_cars_with_warehouse(
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
)
select
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
      coalesce(nullif(btrim(t.data->>'status'),''),'completed'),
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
      coalesce(nullif(btrim(t.data->>'status'),''),'completed'),
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

revoke all on function public.erp_list_cloud_cars_with_warehouse(uuid)
  from public, anon;
grant execute on function public.erp_list_cloud_cars_with_warehouse(uuid)
  to authenticated;

-- These indexes support the canonical projection and the hierarchical report
-- without changing business data.
create index if not exists erp_car_transfers_vehicle_lookup_1884_idx
  on public.erp_car_warehouse_transfers (
    company_id,
    (coalesce(
      nullif(btrim(data->>'carId'),''),
      nullif(btrim(data->>'car_id'),''),
      nullif(btrim(data->>'vehicleId'),''),
      nullif(btrim(data->>'vehicle_id'),'')
    )),
    created_at desc
  )
  where not is_deleted;

create index if not exists erp_warehouses_code_lookup_1884_idx
  on public.erp_warehouses (
    company_id,
    (lower(btrim(coalesce(
      data->>'code',data->>'warehouseCode',data->>'warehouse_code',''
    ))))
  )
  where not is_deleted;

create index if not exists erp_warehouses_name_lookup_1884_idx
  on public.erp_warehouses (
    company_id,
    (lower(btrim(coalesce(
      data->>'name',data->>'warehouseName',data->>'warehouse_name',''
    ))))
  )
  where not is_deleted;

commit;
