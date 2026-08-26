begin;

-- R53 security closure. Forward-only and data-preserving.
-- R52 repaired compilation/runtime issues but accidentally weakened several
-- SECURITY DEFINER read surfaces. Restore the canonical membership,
-- permission, table-contract and tombstone boundaries without changing data.

-- ---------------------------------------------------------------------------
-- Document-processing jobs: RLS must have an actual tenant policy.
-- ---------------------------------------------------------------------------
alter table public.erp_document_processing_jobs enable row level security;
do $$
begin
  drop policy if exists tenant_access on public.erp_document_processing_jobs;
  create policy tenant_access
    on public.erp_document_processing_jobs
    for all
    using (public.erp_user_belongs_to_company(company_id))
    with check (public.erp_user_belongs_to_company(company_id));
exception when undefined_function then
  null;
end $$;

-- ---------------------------------------------------------------------------
-- Canonical master readers: never allow a SECURITY DEFINER caller to select
-- an arbitrary public table. The table must be a known ERP master resource,
-- its schema contract must be valid, and the caller must belong to the
-- requested company and hold the module view permission.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r9_get_cloud_master_record(
  p_company_id uuid,
  p_table text,
  p_record_id text
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_permission text;
  v_id text;
  v_data jsonb;
  v_version bigint;
  v_updated timestamptz;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if public.erp_r9_master_resource_for_table(p_table) is null then
    raise exception 'unsupported_master_table:%',p_table using errcode='22023';
  end if;
  if to_regclass(format('public.%I',p_table)) is null then
    raise exception 'master_table_not_found:%',p_table using errcode='42P01';
  end if;
  if not public.erp_r14_master_table_contract_ok(p_table) then
    raise exception 'master_table_contract_invalid:%',p_table using errcode='22023';
  end if;
  v_permission:=public.erp_r9_master_required_permission(p_table,'view');
  if v_permission is null
     or (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
         and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.view') using errcode='42501';
  end if;
  if public.erp_r15_pending_delete_exists(p_company_id,p_table,p_record_id) then
    return null;
  end if;

  execute format(
    'select id::text,data,version,updated_at from public.%I where company_id=$1 and id=$2 and not coalesce(is_deleted,false)',
    p_table
  ) into v_id,v_data,v_version,v_updated using p_company_id,p_record_id;

  if v_id is null then return null; end if;
  return public.erp_r9_filter_readable_master_json(
    p_company_id,p_table,coalesce(v_data,'{}'::jsonb)
  ) || jsonb_build_object(
    'id',v_id,'_cloudVersion',v_version,'_cloudUpdatedAt',v_updated
  );
end;
$$;

create or replace function public.erp_r9_list_cloud_master_records(
  p_company_id uuid,
  p_table text
) returns setof jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_permission text;
  v_id text;
  v_data jsonb;
  v_version bigint;
  v_updated timestamptz;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if public.erp_r9_master_resource_for_table(p_table) is null then
    raise exception 'unsupported_master_table:%',p_table using errcode='22023';
  end if;
  if to_regclass(format('public.%I',p_table)) is null then
    raise exception 'master_table_not_found:%',p_table using errcode='42P01';
  end if;
  if not public.erp_r14_master_table_contract_ok(p_table) then
    raise exception 'master_table_contract_invalid:%',p_table using errcode='22023';
  end if;
  v_permission:=public.erp_r9_master_required_permission(p_table,'view');
  if v_permission is null
     or (not public.erp_cloud_user_has_permission(p_company_id,v_permission)
         and not public.is_company_admin(p_company_id)) then
    raise exception 'permission_denied:%',coalesce(v_permission,'master.view') using errcode='42501';
  end if;

  for v_id,v_data,v_version,v_updated in execute format(
    'select id::text,data,version,updated_at from public.%I where company_id=$1 and not coalesce(is_deleted,false) and not public.erp_r15_pending_delete_exists($1,$2,id) order by updated_at desc',
    p_table
  ) using p_company_id,p_table loop
    return next public.erp_r9_filter_readable_master_json(
      p_company_id,p_table,coalesce(v_data,'{}'::jsonb)
    ) || jsonb_build_object(
      'id',v_id,'_cloudVersion',v_version,'_cloudUpdatedAt',v_updated
    );
  end loop;
  return;
end;
$$;

-- ---------------------------------------------------------------------------
-- Global search: keep the existing canonical R9 search and add opportunities,
-- but enforce authentication, tenant membership and the opportunity view
-- permission before exposing any SECURITY DEFINER rows.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r49_cloud_global_search(
  p_company_id uuid,
  p_query text,
  p_limit integer default 50
) returns setof jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_slug text;
  v_limit integer:=greatest(1,least(coalesce(p_limit,50),200));
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  if length(btrim(coalesce(p_query,'')))<2 then return; end if;

  select slug into v_slug from public.companies where id=p_company_id;
  if v_slug is null then
    raise exception 'company_not_found' using errcode='P0002';
  end if;

  return query
  with base as (
    select row_payload,20 as rank
    from public.erp_r9_cloud_global_search(p_company_id,p_query,v_limit) as b(row_payload)
  ), opportunities as (
    select jsonb_build_object(
      'id',r.record_id,
      'type','الفرص التجارية',
      'title',coalesce(
        nullif(r.payload->>'title',''),
        nullif(r.payload->>'opportunityNumber',''),
        'فرصة تجارية'
      ),
      'subtitle',concat_ws(' • ',
        nullif(r.payload->>'opportunityNumber',''),
        nullif(r.payload->>'customerName',''),
        nullif(r.payload->>'stage','')
      ),
      'route','/customer-service',
      'permission','customer_service.view',
      'icon','opportunity',
      'status',coalesce(
        nullif(r.payload->>'status',''),
        nullif(r.payload->>'stage',''),
        'pending'
      ),
      'amount',public.erp_try_numeric(r.payload->>'expectedValue',0),
      'currency',case
        when upper(coalesce(r.payload->>'currency','')) in ('USD','IQD')
          then upper(r.payload->>'currency')
        else null
      end,
      'date',coalesce(
        nullif(r.payload->>'updatedAt',''),
        nullif(r.payload->>'createdAt',''),
        r.updated_at::text
      )
    ) as row_payload,
    10 as rank
    from public.erp_records r
    where r.company_id=v_slug
      and r.entity_type='opportunities'
      and r.deleted_at is null
      and (
        public.is_company_admin(p_company_id)
        or public.erp_cloud_user_has_permission(p_company_id,'customer_service.view')
      )
      and r.payload::text ilike '%'||btrim(p_query)||'%'
  )
  select x.row_payload
  from (
    select row_payload,rank from opportunities
    union all
    select row_payload,rank from base
  ) x
  order by x.rank,coalesce(x.row_payload->>'date','') desc
  limit v_limit;
end;
$$;

-- ---------------------------------------------------------------------------
-- State-health endpoints are read-only but still tenant-scoped. They are
-- SECURITY DEFINER and therefore must never become a cross-company oracle.
-- ---------------------------------------------------------------------------
create or replace function public.erp_r15_reconcile_company_state(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  t text;
  tables text[]:=array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers',
    'erp_warehouses','erp_inventory','erp_inventory_groups','erp_product_images'
  ];
  checked bigint:=0;
  conflicts bigint:=0;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  foreach t in array tables loop
    if to_regclass('public.'||t) is not null then
      checked:=checked+1;
      execute format(
        'select count(*) from public.%I r join public.erp_canonical_deletion_tombstones z on z.company_id=r.company_id and z.source_table=$2 and z.record_id=r.id::text where r.company_id=$1 and z.restored_at is null and not coalesce(r.is_deleted,false)',
        t
      ) into conflicts using p_company_id,t;
    end if;
  end loop;
  return jsonb_build_object(
    'companyId',p_company_id,
    'checkedTables',checked,
    'openCanonicalConflicts',conflicts,
    'status','ok'
  );
end;
$$;

create or replace function public.erp_r16_current_state_health(p_company_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  t text;
  tables text[]:=array[
    'erp_cars','erp_car_images','erp_customers','erp_suppliers',
    'erp_warehouses','erp_inventory','erp_inventory_groups','erp_product_images'
  ];
  conflicts bigint:=0;
begin
  if auth.uid() is null or not public.is_active_company_member(p_company_id) then
    raise exception 'company_membership_required' using errcode='42501';
  end if;
  foreach t in array tables loop
    if to_regclass('public.'||t) is not null then
      execute format(
        'select count(*) from public.%I r join public.erp_canonical_deletion_tombstones z on z.company_id=r.company_id and z.source_table=$2 and z.record_id=r.id::text where r.company_id=$1 and z.restored_at is null and not coalesce(r.is_deleted,false)',
        t
      ) into conflicts using p_company_id,t;
    end if;
  end loop;
  return jsonb_build_object(
    'companyId',p_company_id,
    'canonicalConflicts',conflicts,
    'healthy',conflicts=0
  );
end;
$$;

-- Explicitly revoke browser execution from the internal health endpoints if
-- their historical grants were broader than the current canonical surface.
revoke all on function public.erp_r15_reconcile_company_state(uuid) from anon;
revoke all on function public.erp_r16_current_state_health(uuid) from anon;
grant execute on function public.erp_r15_reconcile_company_state(uuid) to authenticated,service_role;
grant execute on function public.erp_r16_current_state_health(uuid) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
