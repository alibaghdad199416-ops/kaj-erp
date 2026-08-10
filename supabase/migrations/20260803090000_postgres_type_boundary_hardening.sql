-- Quality Line ERP 18.8.8 PostgreSQL type-boundary hardening.
--
-- Legacy erp_records rows use a text company key. Newer transactional tables
-- use UUID company identifiers. Keep the conversion at one explicit boundary
-- so later function replacements cannot accidentally compare text with UUID.

begin;

create or replace function public.erp_legacy_company_keys(p_company_id uuid)
returns text[]
language sql
stable
security definer
set search_path=public
as $$
  select coalesce(
    array(
      select distinct key_value
      from unnest(array[
        p_company_id::text,
        (select nullif(btrim(c.slug),'') from public.companies c where c.id=p_company_id)
      ]::text[]) as keys(key_value)
      where key_value is not null
    ),
    array[p_company_id::text]::text[]
  );
$$;

comment on function public.erp_legacy_company_keys(uuid) is
  'Returns every valid legacy text key for a UUID company (UUID text plus slug). Use at erp_records boundaries.';

revoke all on function public.erp_legacy_company_keys(uuid) from public,anon;
grant execute on function public.erp_legacy_company_keys(uuid) to authenticated,service_role;

create or replace function public.erp_delete_cloud_purchase(
  p_company_id uuid,p_purchase_id text
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  v_car_id text;
  v_now timestamptz:=clock_timestamp();
begin
  perform public.erp_require_any_cloud_permission(
    p_company_id,
    array['purchases.delete']
  );

  perform 1
  from public.erp_purchases
  where company_id=p_company_id
    and id=p_purchase_id
    and not is_deleted
  for update;
  if not found then return; end if;

  for v_car_id in
    select nullif(data->>'carId','')
    from public.erp_purchase_items
    where company_id=p_company_id
      and not is_deleted
      and data->>'purchaseId'=p_purchase_id
      and nullif(data->>'carId','') is not null
  loop
    if exists(
      select 1
      from public.erp_sales
      where company_id=p_company_id
        and not is_deleted
        and data->>'carId'=v_car_id
    ) then
      raise exception 'لا يمكن إلغاء الشراء لأن إحدى السيارات تم بيعها لاحقاً';
    end if;

    if exists(
      select 1
      from public.erp_records r
      where r.company_id=any(public.erp_legacy_company_keys(p_company_id))
        and r.entity_type='reservations'
        and r.deleted_at is null
        and r.payload->>'carId'=v_car_id
        and r.payload->>'status'='active'
    ) then
      raise exception 'لا يمكن إلغاء الشراء لأن إحدى السيارات قيد البيع حالياً';
    end if;
  end loop;

  for v_car_id in
    select nullif(data->>'carId','')
    from public.erp_purchase_items
    where company_id=p_company_id
      and not is_deleted
      and data->>'purchaseId'=p_purchase_id
      and nullif(data->>'carId','') is not null
  loop
    update public.erp_cars
    set data=(data-'warehouseId'-'warehouse_id')||jsonb_build_object(
          'status','معرفة',
          'warehouseId',null,
          'warehouse_id',null,
          'updatedAt',v_now
        ),
        updated_at=v_now,
        updated_by=auth.uid()
    where company_id=p_company_id
      and id=v_car_id
      and not is_deleted;
  end loop;

  update public.erp_purchase_items
  set is_deleted=true,
      deleted_at=v_now,
      updated_at=v_now,
      updated_by=auth.uid()
  where company_id=p_company_id
    and not is_deleted
    and data->>'purchaseId'=p_purchase_id;

  update public.erp_purchases
  set is_deleted=true,
      deleted_at=v_now,
      updated_at=v_now,
      updated_by=auth.uid()
  where company_id=p_company_id
    and id=p_purchase_id
    and not is_deleted;
end;
$$;

revoke all on function public.erp_delete_cloud_purchase(uuid,text) from public,anon;
grant execute on function public.erp_delete_cloud_purchase(uuid,text) to authenticated,service_role;

commit;
