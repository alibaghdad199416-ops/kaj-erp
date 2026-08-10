begin;

-- R49 focused final closure: granular CRM CRUD, protected commercial draft
-- entry points, approval wrappers, and planned-stock authorization. Historical
-- implementations remain internal so their proven business logic is reused
-- without exposing membership-only SECURITY DEFINER endpoints to browsers.

insert into public.permissions(code,name_ar,name_en) values
  ('customer_service.update','تعديل خدمة العملاء','Update customer service'),
  ('customer_service.delete','حذف خدمة العملاء','Delete customer service records')
on conflict(code) do update
set name_ar=excluded.name_ar,name_en=excluded.name_en;

insert into public.role_permissions(role_code,permission_code)
select r.role_code,p.code
from (values('owner'),('admin')) as r(role_code)
join public.permissions p on p.code in ('customer_service.update','customer_service.delete')
on conflict do nothing;

-- Refresh tenant-local permission records on fresh/current companies. Auth is
-- null while a migration runs, so erp_seed_access_catalog performs no user-side
-- membership expansion here.
do $$ declare c record; begin
  if to_regprocedure('public.erp_seed_access_catalog(uuid)') is not null then
    for c in select id from public.companies where is_active loop
      perform public.erp_seed_access_catalog(c.id);
    end loop;
  end if;
end $$;

create or replace function public.erp_r49_opportunity_command(
  p_action text,
  p_payload jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_company uuid;
  v_slug text;
  v_admin boolean;
  v_payload jsonb:=coalesce(p_payload,'{}'::jsonb);
  v_record jsonb;
  v_existing jsonb:='{}'::jsonb;
  v_id text;
  v_raw jsonb;
  v_result jsonb;
  v_existing_updated_at timestamptz;
  v_expected_updated_at timestamptz;
  v_create_only boolean:=coalesce(nullif(v_payload->>'create_only','')::boolean,false);
begin
  select company_uuid,company_slug,is_admin into v_company,v_slug,v_admin
  from public.erp_active_company_context();
  if v_company is null then raise exception 'membership_not_found' using errcode='42501'; end if;

  if p_action='list' then
    if not v_admin and not public.erp_cloud_user_has_permission(v_company,'customer_service.view') then
      raise exception 'permission_denied:customer_service.view' using errcode='42501';
    end if;
    select coalesce(jsonb_agg(public.erp_r9_filter_readable_json(
             v_company,'opportunities',item
           ) order by item_updated_at desc),'[]'::jsonb)
      into v_result
    from (
      select r.payload || jsonb_build_object(
               'updatedAt',r.updated_at,
               '_cloudUpdatedAt',r.updated_at
             ) as item,
             r.updated_at as item_updated_at
      from public.erp_records r
      where r.company_id=v_slug and r.entity_type='opportunities' and r.deleted_at is null
      order by r.updated_at desc
      limit 500
    ) q;
    return v_result;
  end if;

  if p_action='save' then
    v_record:=coalesce(v_payload->'record','{}'::jsonb);
    v_id:=coalesce(nullif(btrim(v_record->>'id'),''),gen_random_uuid()::text);
    select coalesce(payload,'{}'::jsonb),updated_at into v_existing,v_existing_updated_at
    from public.erp_records
    where company_id=v_slug and entity_type='opportunities'
      and record_id=v_id and deleted_at is null
    limit 1 for update;
    v_existing:=coalesce(v_existing,'{}'::jsonb);

    if v_existing='{}'::jsonb then
      if not v_create_only then
        raise exception 'opportunity_not_found' using errcode='P0002';
      end if;
      if not v_admin and not public.erp_cloud_user_has_permission(v_company,'customer_service.create') then
        raise exception 'permission_denied:customer_service.create' using errcode='42501';
      end if;
    else
      if v_create_only then
        raise exception 'opportunity_already_exists' using errcode='23505';
      end if;
      if not v_admin and not public.erp_cloud_user_has_permission(v_company,'customer_service.update') then
        raise exception 'permission_denied:customer_service.update' using errcode='42501';
      end if;
      begin
        v_expected_updated_at:=nullif(btrim(coalesce(v_payload->>'expected_updated_at','')),'')::timestamptz;
      exception when others then
        raise exception 'stale_version_invalid' using errcode='22023';
      end;
      if v_expected_updated_at is null then
        raise exception 'stale_version_required' using errcode='22023';
      end if;
      if v_existing_updated_at is distinct from v_expected_updated_at then
        raise exception 'stale_record_conflict' using errcode='40001';
      end if;
    end if;

    v_record:=public.erp_r9_guard_writable_json(
      v_company,'opportunities',v_existing,v_record
    );
    v_record:=v_record||jsonb_build_object(
      'id',v_id,
      'opportunityNumber',coalesce(
        nullif(v_existing->>'opportunityNumber',''),
        nullif(v_record->>'opportunityNumber',''),
        'OPP-'||floor(extract(epoch from clock_timestamp())*1000)::bigint::text
      ),
      'createdAt',coalesce(v_existing->'createdAt',to_jsonb(clock_timestamp())),
      'updatedAt',to_jsonb(clock_timestamp())
    );
    if v_existing='{}'::jsonb then
      v_record:=v_record||jsonb_build_object('status','pending');
    end if;
    v_payload:=jsonb_set(v_payload,'{record}',v_record,true);
    v_raw:=public.erp_phase26_cloud_command('opportunity','save',v_payload);
    return public.erp_r9_filter_readable_json(v_company,'opportunities',coalesce(v_raw,v_record));
  end if;

  if p_action='mark_lost' then
    if not v_admin and not public.erp_cloud_user_has_permission(v_company,'customer_service.update') then
      raise exception 'permission_denied:customer_service.update' using errcode='42501';
    end if;
    if not v_admin and not public.erp_cloud_user_can_edit_field(
      v_company,'opportunities','status','customer_service.update'
    ) then
      raise exception 'permission_denied:opportunities.status' using errcode='42501';
    end if;
    v_id:=nullif(btrim(v_payload->>'id'),'');
    if v_id is null then raise exception 'opportunity_id_required' using errcode='22023'; end if;
    begin
      v_expected_updated_at:=nullif(btrim(coalesce(v_payload->>'expected_updated_at','')),'')::timestamptz;
    exception when others then
      raise exception 'stale_version_invalid' using errcode='22023';
    end;
    select updated_at into v_existing_updated_at from public.erp_records
    where company_id=v_slug and entity_type='opportunities' and record_id=v_id and deleted_at is null
    for update;
    if not found then raise exception 'opportunity_not_found' using errcode='P0002'; end if;
    if v_expected_updated_at is null or v_existing_updated_at is distinct from v_expected_updated_at then
      raise exception 'stale_record_conflict' using errcode='40001';
    end if;
    if exists(
      select 1 from public.erp_sales_orders_cloud o
      where o.company_id=v_company and o.opportunity_id=v_id and not o.is_deleted
        and lower(coalesce(o.status,'')) not in ('cancelled','canceled','rejected')
    ) then
      raise exception 'opportunity_has_active_sales_order' using errcode='P0001';
    end if;
    v_raw:=public.erp_phase26_cloud_command('opportunity','mark_lost',v_payload);
    return public.erp_r9_filter_readable_json(v_company,'opportunities',coalesce(v_raw,'{}'::jsonb));
  end if;

  if p_action='mark_won' then
    if not v_admin and (
      not public.erp_cloud_user_has_permission(v_company,'customer_service.update')
      or not public.erp_cloud_user_has_permission(v_company,'sales.create')
      or not public.erp_cloud_user_can_edit_field(v_company,'opportunities','status','customer_service.update')
      or not public.erp_cloud_user_can_edit_field(v_company,'opportunities','linkedSale','customer_service.update')
    ) then
      raise exception 'permission_denied:opportunities.convert' using errcode='42501';
    end if;
    v_id:=nullif(btrim(coalesce(v_payload->>'opportunity_id',v_payload->>'id')),'');
    if v_id is null then raise exception 'opportunity_id_required' using errcode='22023'; end if;
    begin
      v_expected_updated_at:=nullif(btrim(coalesce(v_payload->>'expected_updated_at','')),'')::timestamptz;
    exception when others then
      raise exception 'stale_version_invalid' using errcode='22023';
    end;
    select updated_at into v_existing_updated_at from public.erp_records
    where company_id=v_slug and entity_type='opportunities' and record_id=v_id and deleted_at is null
    for update;
    if not found then raise exception 'opportunity_not_found' using errcode='P0002'; end if;
    if v_expected_updated_at is null then
      raise exception 'stale_version_required' using errcode='22023';
    end if;
    if v_existing_updated_at is distinct from v_expected_updated_at then
      raise exception 'stale_record_conflict' using errcode='40001';
    end if;
    v_raw:=public.erp_phase26_cloud_command('opportunity','mark_won',v_payload);
    return public.erp_r9_filter_readable_json(v_company,'sales',coalesce(v_raw,'{}'::jsonb));
  end if;

  if p_action='delete' then
    if not v_admin and not public.erp_cloud_user_has_permission(v_company,'customer_service.delete') then
      raise exception 'permission_denied:customer_service.delete' using errcode='42501';
    end if;
    v_id:=nullif(btrim(v_payload->>'id'),'');
    if v_id is null then raise exception 'opportunity_id_required' using errcode='22023'; end if;
    begin
      v_expected_updated_at:=nullif(btrim(coalesce(v_payload->>'expected_updated_at','')),'')::timestamptz;
    exception when others then
      raise exception 'stale_version_invalid' using errcode='22023';
    end;
    select updated_at into v_existing_updated_at from public.erp_records
    where company_id=v_slug and entity_type='opportunities' and record_id=v_id and deleted_at is null
    for update;
    if not found then raise exception 'opportunity_not_found' using errcode='P0002'; end if;
    if v_expected_updated_at is null or v_existing_updated_at is distinct from v_expected_updated_at then
      raise exception 'stale_record_conflict' using errcode='40001';
    end if;
    return public.erp_phase26_cloud_command('opportunity','delete',v_payload);
  end if;

  raise exception 'unsupported_opportunity_action:%',p_action using errcode='22023';
end;
$$;
revoke all on function public.erp_r49_opportunity_command(text,jsonb) from public,anon;
grant execute on function public.erp_r49_opportunity_command(text,jsonb) to authenticated,service_role;

-- Keep the existing stable client endpoint but route CRM through the hardened
-- R49 command. Other modules retain the already verified R35/R27/R14 chain.
create or replace function public.erp_r37_cloud_command(
  p_area text,p_action text,p_payload jsonb
) returns jsonb
language plpgsql security definer set search_path=public
as $$
begin
  if p_area='opportunity' then
    return public.erp_r49_opportunity_command(p_action,coalesce(p_payload,'{}'::jsonb));
  end if;
  return public.erp_r35_cloud_command(p_area,p_action,coalesce(p_payload,'{}'::jsonb));
end;
$$;
revoke all on function public.erp_r37_cloud_command(text,text,jsonb) from public,anon;
grant execute on function public.erp_r37_cloud_command(text,text,jsonb) to authenticated,service_role;

-- Read drafts through module permissions and attach the authoritative server
-- update token used by optimistic concurrency on edits.
create or replace function public.erp_r49_get_sales_order_draft(p_company_id uuid,p_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_result jsonb; v_updated timestamptz;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'sales.view') then
    raise exception 'permission_denied:sales.view' using errcode='42501';
  end if;
  v_result:=public.erp_get_cloud_sales_order_draft(p_company_id,p_order_id);
  if v_result is null then return null; end if;
  select updated_at into v_updated from public.erp_sales_orders_cloud
  where company_id=p_company_id and id=p_order_id and not is_deleted;
  return jsonb_set(v_result,'{order,updatedAt}',to_jsonb(v_updated),true);
end $$;

create or replace function public.erp_r49_get_purchase_order_draft(p_company_id uuid,p_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_result jsonb; v_updated timestamptz;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'purchases.view') then
    raise exception 'permission_denied:purchases.view' using errcode='42501';
  end if;
  v_result:=public.erp_get_cloud_purchase_order_draft(p_company_id,p_order_id);
  if v_result is null then return null; end if;
  select updated_at into v_updated from public.erp_purchase_orders_cloud
  where company_id=p_company_id and id=p_order_id and not is_deleted;
  return jsonb_set(v_result,'{order,updatedAt}',to_jsonb(v_updated),true);
end $$;

revoke all on function public.erp_r49_get_sales_order_draft(uuid,uuid) from public,anon;
revoke all on function public.erp_r49_get_purchase_order_draft(uuid,uuid) from public,anon;
grant execute on function public.erp_r49_get_sales_order_draft(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r49_get_purchase_order_draft(uuid,uuid) to authenticated,service_role;
revoke execute on function public.erp_get_cloud_sales_order_draft(uuid,uuid) from authenticated,anon,public;
revoke execute on function public.erp_get_cloud_purchase_order_draft(uuid,uuid) from authenticated,anon,public;
grant execute on function public.erp_get_cloud_sales_order_draft(uuid,uuid) to service_role;
grant execute on function public.erp_get_cloud_purchase_order_draft(uuid,uuid) to service_role;

-- Permission-protected V23 order endpoints. The underlying atomic functions
-- stay unchanged and are callable only by trusted server code/service_role.
create or replace function public.erp_r49_create_sales_order(p_company_id uuid,p_payload jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_opportunity text:=nullif(btrim(coalesce(p_payload->>'opportunityId','')),'');
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'sales.create') then
    raise exception 'permission_denied:sales.create' using errcode='42501';
  end if;
  if v_opportunity is not null then
    if not exists(
      select 1 from public.erp_records r join public.companies c on c.slug=r.company_id
      where c.id=p_company_id and r.entity_type='opportunities'
        and r.record_id=v_opportunity and r.deleted_at is null
    ) then
      raise exception 'opportunity_not_found' using errcode='23503';
    end if;
    if not public.is_company_admin(p_company_id)
       and not public.erp_cloud_user_has_permission(p_company_id,'customer_service.update') then
      raise exception 'permission_denied:customer_service.update' using errcode='42501';
    end if;
  end if;
  return public.erp_v2300_create_sales_order(p_company_id,coalesce(p_payload,'{}'::jsonb));
end $$;

create or replace function public.erp_r49_update_sales_order(p_company_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_order_id uuid; v_expected timestamptz; v_actual timestamptz;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'sales.update') then
    raise exception 'permission_denied:sales.update' using errcode='42501';
  end if;
  begin
    v_order_id:=(p_payload->>'orderId')::uuid;
    v_expected:=nullif(btrim(coalesce(p_payload->>'expectedUpdatedAt','')),'')::timestamptz;
  exception when others then raise exception 'stale_version_invalid' using errcode='22023'; end;
  if v_expected is null then raise exception 'stale_version_required' using errcode='22023'; end if;
  select updated_at into v_actual from public.erp_sales_orders_cloud
  where company_id=p_company_id and id=v_order_id and not is_deleted for update;
  if not found then raise exception 'sales_order_not_found' using errcode='P0002'; end if;
  if v_actual is distinct from v_expected then raise exception 'stale_record_conflict' using errcode='40001'; end if;
  return public.erp_v2300_update_sales_order(p_company_id,coalesce(p_payload,'{}'::jsonb));
end $$;

create or replace function public.erp_r49_create_purchase_order(p_company_id uuid,p_payload jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'purchases.create') then
    raise exception 'permission_denied:purchases.create' using errcode='42501';
  end if;
  return public.erp_v2300_create_purchase_order(p_company_id,coalesce(p_payload,'{}'::jsonb));
end $$;

create or replace function public.erp_r49_update_purchase_order(p_company_id uuid,p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_order_id uuid; v_expected timestamptz; v_actual timestamptz;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'purchases.update') then
    raise exception 'permission_denied:purchases.update' using errcode='42501';
  end if;
  begin
    v_order_id:=(p_payload->>'orderId')::uuid;
    v_expected:=nullif(btrim(coalesce(p_payload->>'expectedUpdatedAt','')),'')::timestamptz;
  exception when others then raise exception 'stale_version_invalid' using errcode='22023'; end;
  if v_expected is null then raise exception 'stale_version_required' using errcode='22023'; end if;
  select updated_at into v_actual from public.erp_purchase_orders_cloud
  where company_id=p_company_id and id=v_order_id and not is_deleted for update;
  if not found then raise exception 'purchase_order_not_found' using errcode='P0002'; end if;
  if v_actual is distinct from v_expected then raise exception 'stale_record_conflict' using errcode='40001'; end if;
  return public.erp_v2300_update_purchase_order(p_company_id,coalesce(p_payload,'{}'::jsonb));
end $$;

create or replace function public.erp_r49_approve_sales_order(p_company_id uuid,p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'sales.approve') then
    raise exception 'permission_denied:sales.approve' using errcode='42501';
  end if;
  perform public.erp_approve_cloud_sales_order(p_company_id,p_order_id);
end $$;

create or replace function public.erp_r49_approve_purchase_order(p_company_id uuid,p_order_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'purchases.approve') then
    raise exception 'permission_denied:purchases.approve' using errcode='42501';
  end if;
  perform public.erp_approve_cloud_purchase_order(p_company_id,p_order_id);
end $$;

revoke all on function public.erp_r49_create_sales_order(uuid,jsonb) from public,anon;
revoke all on function public.erp_r49_update_sales_order(uuid,jsonb) from public,anon;
revoke all on function public.erp_r49_create_purchase_order(uuid,jsonb) from public,anon;
revoke all on function public.erp_r49_update_purchase_order(uuid,jsonb) from public,anon;
revoke all on function public.erp_r49_approve_sales_order(uuid,uuid) from public,anon;
revoke all on function public.erp_r49_approve_purchase_order(uuid,uuid) from public,anon;
grant execute on function public.erp_r49_create_sales_order(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r49_update_sales_order(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r49_create_purchase_order(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r49_update_purchase_order(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r49_approve_sales_order(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r49_approve_purchase_order(uuid,uuid) to authenticated,service_role;

revoke execute on function public.erp_v2300_create_sales_order(uuid,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_v2300_update_sales_order(uuid,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_v2300_create_purchase_order(uuid,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_v2300_update_purchase_order(uuid,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_approve_cloud_sales_order(uuid,uuid) from authenticated,anon,public;
revoke execute on function public.erp_approve_cloud_purchase_order(uuid,uuid) from authenticated,anon,public;
-- Trusted server tooling may still invoke the underlying implementation.
grant execute on function public.erp_v2300_create_sales_order(uuid,jsonb) to service_role;
grant execute on function public.erp_v2300_update_sales_order(uuid,jsonb) to service_role;
grant execute on function public.erp_v2300_create_purchase_order(uuid,jsonb) to service_role;
grant execute on function public.erp_v2300_update_purchase_order(uuid,jsonb) to service_role;
grant execute on function public.erp_approve_cloud_sales_order(uuid,uuid) to service_role;
grant execute on function public.erp_approve_cloud_purchase_order(uuid,uuid) to service_role;



-- Maintenance list/readback carries the authoritative update token used to
-- protect edits from stale multi-user overwrites.
create or replace function public.erp_r9_list_cloud_maintenance_orders(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select public.erp_r9_filter_result_json(
    p_company_id,'maintenance',to_jsonb(x)||jsonb_build_object('updatedAt',o.updated_at),'maintenance.view'
  )
  from public.erp_list_cloud_maintenance_orders(p_company_id) x
  join public.erp_maintenance_orders o on o.company_id=p_company_id and o.id=x.id and not o.is_deleted
$$;
revoke all on function public.erp_r9_list_cloud_maintenance_orders(uuid) from public,anon;
grant execute on function public.erp_r9_list_cloud_maintenance_orders(uuid) to authenticated,service_role;

create or replace function public.erp_r49_update_cloud_maintenance_draft(
  p_company_id uuid,p_order_id uuid,p_warehouse_id text,p_pricing_type text,
  p_labor_cost numeric,p_sale_price numeric,p_currency_code text,p_exchange_rate numeric,
  p_notes text,p_parts jsonb,p_maintenance_expense_account_id text default null,
  p_effective_at timestamptz default null,p_expected_updated_at timestamptz default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_actual timestamptz;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'maintenance.update') then
    raise exception 'permission_denied:maintenance.update' using errcode='42501';
  end if;
  if p_expected_updated_at is null then raise exception 'stale_version_required' using errcode='22023'; end if;
  select updated_at into v_actual from public.erp_maintenance_orders
  where company_id=p_company_id and id=p_order_id and not is_deleted for update;
  if not found then raise exception 'maintenance_order_not_found' using errcode='P0002'; end if;
  if v_actual is distinct from p_expected_updated_at then raise exception 'stale_record_conflict' using errcode='40001'; end if;
  return public.erp_r39_update_cloud_maintenance_draft(
    p_company_id,p_order_id,p_warehouse_id,p_pricing_type,p_labor_cost,p_sale_price,
    p_currency_code,p_exchange_rate,p_notes,p_parts,p_maintenance_expense_account_id,p_effective_at
  );
end $$;
revoke all on function public.erp_r49_update_cloud_maintenance_draft(uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz,timestamptz) from public,anon;
grant execute on function public.erp_r49_update_cloud_maintenance_draft(uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz,timestamptz) to authenticated,service_role;
revoke execute on function public.erp_r39_update_cloud_maintenance_draft(uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) from authenticated,anon,public;
grant execute on function public.erp_r39_update_cloud_maintenance_draft(uuid,uuid,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) to service_role;

-- R49 logistics warehouse validation is fail-closed. Missing isActive is not
-- treated as active, and multi-allocation documents validate every referenced
-- warehouse before the historical stock/logistics implementation is invoked.
create or replace function public.erp_r49_require_active_warehouse(p_company_id uuid,p_warehouse_id text)
returns void language plpgsql stable security definer set search_path=public as $$
begin
  if nullif(btrim(coalesce(p_warehouse_id,'')),'') is null then return; end if;
  if not exists(
    select 1 from public.erp_warehouses w
    where w.company_id=p_company_id and w.id=p_warehouse_id and not w.is_deleted
      and public.erp_try_boolean(w.data->>'isActive',false)
  ) then raise exception 'warehouse_not_found_or_inactive' using errcode='22023'; end if;
end $$;
create or replace function public.erp_r49_require_allocation_warehouses(p_company_id uuid,p_allocations jsonb)
returns void language plpgsql stable security definer set search_path=public as $$
declare v_warehouse text;
begin
  if jsonb_typeof(coalesce(p_allocations,'null'::jsonb))<>'array' then raise exception 'invalid_warehouse_allocations' using errcode='22023'; end if;
  for v_warehouse in select distinct nullif(btrim(value->>'warehouseId'),'') from jsonb_array_elements(p_allocations) where nullif(btrim(value->>'warehouseId'),'') is not null loop
    perform public.erp_r49_require_active_warehouse(p_company_id,v_warehouse);
  end loop;
end $$;
revoke all on function public.erp_r49_require_active_warehouse(uuid,text) from public,anon,authenticated;
revoke all on function public.erp_r49_require_allocation_warehouses(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.erp_r49_require_active_warehouse(uuid,text) to service_role;
grant execute on function public.erp_r49_require_allocation_warehouses(uuid,jsonb) to service_role;

-- Logistics draft creation mutates an approved commercial workflow and must not
-- rely on button visibility. Keep the established logistics implementations
-- internal, while the browser-facing wrappers enforce granular update rights.
create or replace function public.erp_r49_create_purchase_receipt(
  p_company_id uuid,p_order_id uuid,p_warehouse_id text default null,p_notes text default null
) returns uuid language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'purchases.update') then
    raise exception 'permission_denied:purchases.update' using errcode='42501';
  end if;
  perform public.erp_r49_require_active_warehouse(p_company_id,p_warehouse_id);
  return public.erp_create_cloud_purchase_receipt(p_company_id,p_order_id,p_warehouse_id,p_notes);
end $$;

create or replace function public.erp_r49_create_purchase_receipt_multi(
  p_company_id uuid,p_order_id uuid,p_allocations jsonb,p_notes text default null
) returns uuid language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'purchases.update') then
    raise exception 'permission_denied:purchases.update' using errcode='42501';
  end if;
  perform public.erp_r49_require_allocation_warehouses(p_company_id,p_allocations);
  return public.erp_create_cloud_purchase_receipt_multi(p_company_id,p_order_id,p_allocations,p_notes);
end $$;

create or replace function public.erp_r49_create_sales_delivery(
  p_company_id uuid,p_order_id uuid,p_warehouse_id text default null,p_notes text default null
) returns uuid language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'sales.update') then
    raise exception 'permission_denied:sales.update' using errcode='42501';
  end if;
  perform public.erp_r49_require_active_warehouse(p_company_id,p_warehouse_id);
  return public.erp_create_cloud_sales_delivery(p_company_id,p_order_id,p_warehouse_id,p_notes);
end $$;

create or replace function public.erp_r49_create_sales_delivery_multi(
  p_company_id uuid,p_order_id uuid,p_allocations jsonb,p_notes text default null
) returns uuid language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'sales.update') then
    raise exception 'permission_denied:sales.update' using errcode='42501';
  end if;
  perform public.erp_r49_require_allocation_warehouses(p_company_id,p_allocations);
  return public.erp_create_cloud_sales_delivery_multi(p_company_id,p_order_id,p_allocations,p_notes);
end $$;

revoke all on function public.erp_r49_create_purchase_receipt(uuid,uuid,text,text) from public,anon;
revoke all on function public.erp_r49_create_purchase_receipt_multi(uuid,uuid,jsonb,text) from public,anon;
revoke all on function public.erp_r49_create_sales_delivery(uuid,uuid,text,text) from public,anon;
revoke all on function public.erp_r49_create_sales_delivery_multi(uuid,uuid,jsonb,text) from public,anon;
grant execute on function public.erp_r49_create_purchase_receipt(uuid,uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_r49_create_purchase_receipt_multi(uuid,uuid,jsonb,text) to authenticated,service_role;
grant execute on function public.erp_r49_create_sales_delivery(uuid,uuid,text,text) to authenticated,service_role;
grant execute on function public.erp_r49_create_sales_delivery_multi(uuid,uuid,jsonb,text) to authenticated,service_role;
revoke execute on function public.erp_create_cloud_purchase_receipt(uuid,uuid,text,text) from authenticated,anon,public;
revoke execute on function public.erp_create_cloud_purchase_receipt_multi(uuid,uuid,jsonb,text) from authenticated,anon,public;
revoke execute on function public.erp_create_cloud_sales_delivery(uuid,uuid,text,text) from authenticated,anon,public;
revoke execute on function public.erp_create_cloud_sales_delivery_multi(uuid,uuid,jsonb,text) from authenticated,anon,public;
grant execute on function public.erp_create_cloud_purchase_receipt(uuid,uuid,text,text) to service_role;
grant execute on function public.erp_create_cloud_purchase_receipt_multi(uuid,uuid,jsonb,text) to service_role;
grant execute on function public.erp_create_cloud_sales_delivery(uuid,uuid,text,text) to service_role;
grant execute on function public.erp_create_cloud_sales_delivery_multi(uuid,uuid,jsonb,text) to service_role;

-- Maintenance draft creation must be protected by maintenance.create at the
-- backend. The canonical R39 function remains the business implementation.
create or replace function public.erp_r49_create_cloud_maintenance_order(
  p_company_id uuid,p_car_id text,p_warehouse_id text,p_pricing_type text,
  p_labor_cost numeric,p_sale_price numeric,p_currency_code text,p_exchange_rate numeric,
  p_notes text,p_parts jsonb,p_maintenance_expense_account_id text default null,
  p_effective_at timestamptz default now()
) returns uuid language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'maintenance.create') then
    raise exception 'permission_denied:maintenance.create' using errcode='42501';
  end if;
  return public.erp_r39_create_cloud_maintenance_order(
    p_company_id,p_car_id,p_warehouse_id,p_pricing_type,p_labor_cost,p_sale_price,
    p_currency_code,p_exchange_rate,p_notes,p_parts,p_maintenance_expense_account_id,p_effective_at
  );
end $$;
revoke all on function public.erp_r49_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) from public,anon;
grant execute on function public.erp_r49_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) to authenticated,service_role;
revoke execute on function public.erp_r39_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) from authenticated,anon,public;
grant execute on function public.erp_r39_create_cloud_maintenance_order(uuid,text,text,text,numeric,numeric,text,numeric,text,jsonb,text,timestamptz) to service_role;

-- Planned stock is an inventory adjustment forecast, not generic master-data
-- management. Require the granular permission and validate an active warehouse
-- before allowing erp_inventory_ensure_stock to create any stock row.
create or replace function public.erp_r49_plan_inventory_movement(
  p_company_id uuid,p_product_id text,p_warehouse_id text,p_incoming boolean,
  p_quantity integer,p_notes text default null
) returns void
language plpgsql security definer set search_path=public as $$
declare
  v_stock public.erp_warehouse_stock%rowtype;
  v_field text;
  v_current numeric;
  v_product public.erp_inventory%rowtype;
  v_cost numeric;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'inventory.adjust') then
    raise exception 'permission_denied:inventory.adjust' using errcode='42501';
  end if;
  if coalesce(p_quantity,0)<=0 then raise exception 'planned_quantity_invalid' using errcode='22023'; end if;

  select * into v_product from public.erp_inventory
  where company_id=p_company_id and id=p_product_id and not is_deleted
    and public.erp_try_boolean(data->>'isActive',false)
  for share;
  if not found then raise exception 'product_not_found_or_inactive' using errcode='23503'; end if;

  perform 1 from public.erp_warehouses
  where company_id=p_company_id and id=p_warehouse_id and not is_deleted
    and public.erp_try_boolean(data->>'isActive',false)
  for share;
  if not found then raise exception 'warehouse_not_found_or_inactive' using errcode='23503'; end if;

  v_stock:=public.erp_inventory_ensure_stock(p_company_id,p_warehouse_id,p_product_id);
  v_field:=case when p_incoming then 'expectedIncoming' else 'expectedOutgoing' end;
  v_current:=coalesce(public.erp_try_numeric(v_stock.data->>v_field,0),0);
  v_cost:=coalesce(public.erp_try_numeric(v_product.data->>'unitCost',0),0);
  update public.erp_warehouse_stock
  set data=jsonb_set(data,array[v_field],to_jsonb((v_current+p_quantity)::int),true)
           ||jsonb_build_object('updatedAt',now()),
      updated_at=now(),updated_by=auth.uid()
  where company_id=p_company_id and id=v_stock.id;
  perform public.erp_inventory_insert_movement(
    p_company_id,p_product_id,p_warehouse_id,
    case when p_incoming then 'expected_in' else 'expected_out' end,
    case when p_incoming then p_quantity else -p_quantity end,
    v_cost,'stock_forecast',null,nullif(btrim(coalesce(p_notes,'')),'')
  );
  perform public.erp_inventory_refresh_product(p_company_id,p_product_id);
end $$;
revoke all on function public.erp_r49_plan_inventory_movement(uuid,text,text,boolean,integer,text) from public,anon;
grant execute on function public.erp_r49_plan_inventory_movement(uuid,text,text,boolean,integer,text) to authenticated,service_role;
revoke execute on function public.erp_plan_inventory_movement(uuid,text,text,boolean,integer,text) from authenticated,anon,public;
grant execute on function public.erp_plan_inventory_movement(uuid,text,text,boolean,integer,text) to service_role;



-- R49 focused inventory permission bridge.
-- Historical inventory implementations predate granular inventory.* permissions
-- and call can_manage_master_data(), which is role-based. The bridge is only
-- activated transaction-locally by the protected R49 entry points below, and
-- still validates the exact granular permission against the current company.
create or replace function public.can_manage_master_data(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists (
    select 1
    from public.company_memberships m
    join public.companies c on c.id=m.company_id
    where m.company_id=p_company_id
      and public.erp_membership_matches_current_user(m.user_id,m.user_uid)
      and m.is_active and c.is_active
      and (
        m.is_system_admin
        or m.role_code in ('owner','admin','manager','sales','warehouse','accountant')
        or (
          nullif(current_setting('qualityline.r49_master_permission',true),'') = any(array[
            'inventory.create','inventory.update','inventory.adjust','inventory.receive','inventory.transfer',
            'sales.create','sales.update','purchases.create','purchases.update',
            'accounting.create','accounting.update','accounting.post'
          ])
          and public.erp_cloud_user_has_permission(
            p_company_id,current_setting('qualityline.r49_master_permission',true)
          )
        )
      )
  );
$$;

create or replace function public.erp_r49_create_inventory_product(
  p_company_id uuid,p_product_id text,p_product jsonb,p_warehouse_id text,
  p_opening_quantity integer,p_images jsonb,p_user_name text
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'inventory.create') then
    raise exception 'permission_denied:inventory.create' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','inventory.create',true);
  perform public.erp_create_inventory_product(
    p_company_id,p_product_id,p_product,p_warehouse_id,p_opening_quantity,p_images,p_user_name
  );
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

create or replace function public.erp_r49_update_inventory_product(
  p_company_id uuid,p_product_id text,p_product jsonb,p_images jsonb default '[]'::jsonb
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'inventory.update') then
    raise exception 'permission_denied:inventory.update' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','inventory.update',true);
  perform public.erp_update_inventory_product(p_company_id,p_product_id,p_product,p_images);
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

create or replace function public.erp_r49_adjust_product_opening_balance(
  p_company_id uuid,p_product_id text,p_warehouse_id text,p_new_opening_quantity integer,
  p_user_name text default null
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'inventory.adjust') then
    raise exception 'permission_denied:inventory.adjust' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','inventory.adjust',true);
  perform public.erp_adjust_product_opening_balance(
    p_company_id,p_product_id,p_warehouse_id,p_new_opening_quantity,p_user_name
  );
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

create or replace function public.erp_r49_receive_inventory_stock(
  p_company_id uuid,p_product_id text,p_warehouse_id text,p_quantity integer,
  p_unit_purchase_price numeric,p_freight_cost numeric,p_customs_cost numeric,
  p_insurance_cost numeric,p_other_cost numeric,p_supplier_id text default null,
  p_supplier_name text default null,p_notes text default null
) returns text language plpgsql security definer set search_path=public as $$
declare v_id text;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'inventory.receive') then
    raise exception 'permission_denied:inventory.receive' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','inventory.receive',true);
  v_id:=public.erp_receive_inventory_stock(
    p_company_id,p_product_id,p_warehouse_id,p_quantity,p_unit_purchase_price,
    p_freight_cost,p_customs_cost,p_insurance_cost,p_other_cost,p_supplier_id,p_supplier_name,p_notes
  );
  perform set_config('qualityline.r49_master_permission','',true);
  return v_id;
end $$;

create or replace function public.erp_r49_transfer_inventory_stock(
  p_company_id uuid,p_product_id text,p_from_warehouse_id text,p_to_warehouse_id text,
  p_quantity integer,p_notes text default null
) returns text language plpgsql security definer set search_path=public as $$
declare v_id text;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'inventory.transfer') then
    raise exception 'permission_denied:inventory.transfer' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','inventory.transfer',true);
  v_id:=public.erp_transfer_inventory_stock(
    p_company_id,p_product_id,p_from_warehouse_id,p_to_warehouse_id,p_quantity,p_notes
  );
  perform set_config('qualityline.r49_master_permission','',true);
  return v_id;
end $$;

create or replace function public.erp_r49_transfer_inventory_stock_batch(
  p_company_id uuid,p_lines jsonb,p_notes text default null,p_effective_at timestamptz default now()
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_result jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'inventory.transfer') then
    raise exception 'permission_denied:inventory.transfer' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','inventory.transfer',true);
  v_result:=public.erp_v2300_transfer_inventory_stock_batch(p_company_id,p_lines,p_notes,p_effective_at);
  perform set_config('qualityline.r49_master_permission','',true);
  return v_result;
end $$;

create or replace function public.erp_r49_create_car_warehouse_transfer(
  p_company_id uuid,p_car_id text,p_to_warehouse_id text,p_user_name text,
  p_notes text default null,p_effective_at timestamptz default now()
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_result jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'inventory.transfer') then
    raise exception 'permission_denied:inventory.transfer' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','inventory.transfer',true);
  v_result:=public.erp_v2300_create_car_warehouse_transfer(
    p_company_id,p_car_id,p_to_warehouse_id,p_user_name,p_notes,p_effective_at
  );
  perform set_config('qualityline.r49_master_permission','',true);
  return v_result;
end $$;

create or replace function public.erp_r49_create_car_warehouse_transfer_batch(
  p_company_id uuid,p_lines jsonb,p_to_warehouse_id uuid,p_user_name text,
  p_notes text default null,p_effective_at timestamptz default now()
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_result jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'inventory.transfer') then
    raise exception 'permission_denied:inventory.transfer' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','inventory.transfer',true);
  v_result:=public.erp_v2300_create_car_warehouse_transfer_batch(
    p_company_id,p_lines,p_to_warehouse_id,p_user_name,p_notes,p_effective_at
  );
  perform set_config('qualityline.r49_master_permission','',true);
  return v_result;
end $$;

create or replace function public.erp_r49_edit_car_warehouse_transfer(
  p_company_id uuid,p_transfer_id text,p_car_id text,p_to_warehouse_id text,
  p_user_name text,p_notes text default null
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'inventory.transfer') then
    raise exception 'permission_denied:inventory.transfer' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','inventory.transfer',true);
  perform public.erp_edit_car_warehouse_transfer(
    p_company_id,p_transfer_id,p_car_id,p_to_warehouse_id,p_user_name,p_notes
  );
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

create or replace function public.erp_r49_reverse_car_warehouse_transfer(
  p_company_id uuid,p_transfer_id text,p_user_name text
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'inventory.transfer') then
    raise exception 'permission_denied:inventory.transfer' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','inventory.transfer',true);
  perform public.erp_reverse_car_warehouse_transfer(p_company_id,p_transfer_id,p_user_name);
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

revoke all on function public.erp_r49_create_inventory_product(uuid,text,jsonb,text,integer,jsonb,text) from public,anon;
revoke all on function public.erp_r49_update_inventory_product(uuid,text,jsonb,jsonb) from public,anon;
revoke all on function public.erp_r49_adjust_product_opening_balance(uuid,text,text,integer,text) from public,anon;
revoke all on function public.erp_r49_receive_inventory_stock(uuid,text,text,integer,numeric,numeric,numeric,numeric,numeric,text,text,text) from public,anon;
revoke all on function public.erp_r49_transfer_inventory_stock(uuid,text,text,text,integer,text) from public,anon;
revoke all on function public.erp_r49_transfer_inventory_stock_batch(uuid,jsonb,text,timestamptz) from public,anon;
revoke all on function public.erp_r49_create_car_warehouse_transfer(uuid,text,text,text,text,timestamptz) from public,anon;
revoke all on function public.erp_r49_create_car_warehouse_transfer_batch(uuid,jsonb,uuid,text,text,timestamptz) from public,anon;
revoke all on function public.erp_r49_edit_car_warehouse_transfer(uuid,text,text,text,text,text) from public,anon;
revoke all on function public.erp_r49_reverse_car_warehouse_transfer(uuid,text,text) from public,anon;
grant execute on function public.erp_r49_create_inventory_product(uuid,text,jsonb,text,integer,jsonb,text) to authenticated,service_role;
grant execute on function public.erp_r49_update_inventory_product(uuid,text,jsonb,jsonb) to authenticated,service_role;
grant execute on function public.erp_r49_adjust_product_opening_balance(uuid,text,text,integer,text) to authenticated,service_role;
grant execute on function public.erp_r49_receive_inventory_stock(uuid,text,text,integer,numeric,numeric,numeric,numeric,numeric,text,text,text) to authenticated,service_role;
grant execute on function public.erp_r49_transfer_inventory_stock(uuid,text,text,text,integer,text) to authenticated,service_role;
grant execute on function public.erp_r49_transfer_inventory_stock_batch(uuid,jsonb,text,timestamptz) to authenticated,service_role;
grant execute on function public.erp_r49_create_car_warehouse_transfer(uuid,text,text,text,text,timestamptz) to authenticated,service_role;
grant execute on function public.erp_r49_create_car_warehouse_transfer_batch(uuid,jsonb,uuid,text,text,timestamptz) to authenticated,service_role;
grant execute on function public.erp_r49_edit_car_warehouse_transfer(uuid,text,text,text,text,text) to authenticated,service_role;
grant execute on function public.erp_r49_reverse_car_warehouse_transfer(uuid,text,text) to authenticated,service_role;

-- Remove direct browser access to the role-based historical implementations.
revoke execute on function public.erp_create_inventory_product(uuid,text,jsonb,text,integer,jsonb,text) from authenticated,anon,public;
revoke execute on function public.erp_update_inventory_product(uuid,text,jsonb,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_adjust_product_opening_balance(uuid,text,text,integer,text) from authenticated,anon,public;
revoke execute on function public.erp_receive_inventory_stock(uuid,text,text,integer,numeric,numeric,numeric,numeric,numeric,text,text,text) from authenticated,anon,public;
revoke execute on function public.erp_transfer_inventory_stock(uuid,text,text,text,integer,text) from authenticated,anon,public;
revoke execute on function public.erp_v2300_transfer_inventory_stock_batch(uuid,jsonb,text,timestamptz) from authenticated,anon,public;
revoke execute on function public.erp_v2300_create_car_warehouse_transfer(uuid,text,text,text,text,timestamptz) from authenticated,anon,public;
revoke execute on function public.erp_v2300_create_car_warehouse_transfer_batch(uuid,jsonb,uuid,text,text,timestamptz) from authenticated,anon,public;
revoke execute on function public.erp_edit_car_warehouse_transfer(uuid,text,text,text,text,text) from authenticated,anon,public;
revoke execute on function public.erp_reverse_car_warehouse_transfer(uuid,text,text) from authenticated,anon,public;
grant execute on function public.erp_create_inventory_product(uuid,text,jsonb,text,integer,jsonb,text) to service_role;
grant execute on function public.erp_update_inventory_product(uuid,text,jsonb,jsonb) to service_role;
grant execute on function public.erp_adjust_product_opening_balance(uuid,text,text,integer,text) to service_role;
grant execute on function public.erp_receive_inventory_stock(uuid,text,text,integer,numeric,numeric,numeric,numeric,numeric,text,text,text) to service_role;
grant execute on function public.erp_transfer_inventory_stock(uuid,text,text,text,integer,text) to service_role;
grant execute on function public.erp_v2300_transfer_inventory_stock_batch(uuid,jsonb,text,timestamptz) to service_role;
grant execute on function public.erp_v2300_create_car_warehouse_transfer(uuid,text,text,text,text,timestamptz) to service_role;
grant execute on function public.erp_v2300_create_car_warehouse_transfer_batch(uuid,jsonb,uuid,text,text,timestamptz) to service_role;
grant execute on function public.erp_edit_car_warehouse_transfer(uuid,text,text,text,text,text) to service_role;
grant execute on function public.erp_reverse_car_warehouse_transfer(uuid,text,text) to service_role;



-- Filter canonical master-data reads on the server instead of transferring a
-- whole table to Flutter and filtering it in memory. The canonical R15 list
-- function remains the source of truth and therefore retains its permission,
-- pending-delete and company-isolation rules.
create or replace function public.erp_r49_list_cloud_master_where(
  p_company_id uuid,p_table text,p_field text,p_value text
) returns setof jsonb
language plpgsql stable security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not (
    (p_table='erp_warehouse_stock' and p_field in ('productId','warehouseId'))
    or (p_table='erp_product_images' and p_field='productId')
    or (p_table='erp_cars' and p_field='warehouseId')
    or (p_table='erp_inventory' and p_field='groupId')
    or (p_table='erp_sales' and p_field='carId')
    or (p_table='erp_purchases' and p_field='supplierId')
    or (p_table='erp_purchase_items' and p_field='purchaseId')
  ) then
    raise exception 'unsupported_master_filter:%:%',coalesce(p_table,''),coalesce(p_field,'') using errcode='22023';
  end if;
  return query
  select row_value
  from public.erp_r15_list_cloud_master_records(p_company_id,p_table) as row_value
  where coalesce(row_value->>p_field,'')=coalesce(p_value,'');
end $$;
revoke all on function public.erp_r49_list_cloud_master_where(uuid,text,text,text) from public,anon;
grant execute on function public.erp_r49_list_cloud_master_where(uuid,text,text,text) to authenticated,service_role;



-- Legacy invoice registers are read/print-only in the current UI, but their
-- historical create/update RPCs must not remain a permission bypass. Keep them
-- callable through protected R49 facades for compatibility with repository
-- APIs, and reject stale edits rather than silently overwriting another user.
create or replace function public.erp_r49_create_cloud_sale(
  p_company_id uuid,p_sale jsonb,p_installments jsonb default '[]'::jsonb
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'sales.create') then
    raise exception 'permission_denied:sales.create' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','sales.create',true);
  perform public.erp_create_cloud_sale(p_company_id,p_sale,p_installments);
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

create or replace function public.erp_r49_create_cloud_resale(
  p_company_id uuid,p_sale jsonb
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'sales.create') then
    raise exception 'permission_denied:sales.create' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','sales.create',true);
  perform public.erp_create_cloud_resale(p_company_id,p_sale);
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

create or replace function public.erp_r49_update_cloud_sale(
  p_company_id uuid,p_sale jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_id text:=nullif(btrim(coalesce(p_sale->>'id','')),'');
  v_expected timestamptz;
  v_current timestamptz;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'sales.update') then
    raise exception 'permission_denied:sales.update' using errcode='42501';
  end if;
  if v_id is null then raise exception 'sale_id_required' using errcode='22023'; end if;
  begin v_expected:=nullif(btrim(coalesce(p_sale->>'updatedAt','')),'')::timestamptz;
  exception when others then raise exception 'stale_version_invalid' using errcode='22007'; end;
  if v_expected is null then raise exception 'stale_version_required' using errcode='40001'; end if;
  select updated_at into v_current from public.erp_sales
   where company_id=p_company_id and id=v_id and not is_deleted for update;
  if not found then raise exception 'sale_not_found'; end if;
  if v_current is distinct from v_expected then raise exception 'stale_record_conflict' using errcode='40001'; end if;
  perform set_config('qualityline.r49_master_permission','sales.update',true);
  perform public.erp_update_cloud_sale(p_company_id,p_sale);
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

create or replace function public.erp_r49_create_cloud_purchase(
  p_company_id uuid,p_purchase jsonb,p_items jsonb
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'purchases.create') then
    raise exception 'permission_denied:purchases.create' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','purchases.create',true);
  perform public.erp_create_cloud_purchase(p_company_id,p_purchase,p_items);
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

create or replace function public.erp_r49_update_cloud_purchase(
  p_company_id uuid,p_purchase jsonb,p_items jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare
  v_id text:=nullif(btrim(coalesce(p_purchase->>'id','')),'');
  v_expected timestamptz;
  v_current timestamptz;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'purchases.update') then
    raise exception 'permission_denied:purchases.update' using errcode='42501';
  end if;
  if v_id is null then raise exception 'purchase_id_required' using errcode='22023'; end if;
  begin v_expected:=nullif(btrim(coalesce(p_purchase->>'updatedAt','')),'')::timestamptz;
  exception when others then raise exception 'stale_version_invalid' using errcode='22007'; end;
  if v_expected is null then raise exception 'stale_version_required' using errcode='40001'; end if;
  select updated_at into v_current from public.erp_purchases
   where company_id=p_company_id and id=v_id and not is_deleted for update;
  if not found then raise exception 'purchase_not_found'; end if;
  if v_current is distinct from v_expected then raise exception 'stale_record_conflict' using errcode='40001'; end if;
  perform set_config('qualityline.r49_master_permission','purchases.update',true);
  perform public.erp_update_cloud_purchase(p_company_id,p_purchase,p_items);
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

revoke all on function public.erp_r49_create_cloud_sale(uuid,jsonb,jsonb) from public,anon;
revoke all on function public.erp_r49_create_cloud_resale(uuid,jsonb) from public,anon;
revoke all on function public.erp_r49_update_cloud_sale(uuid,jsonb) from public,anon;
revoke all on function public.erp_r49_create_cloud_purchase(uuid,jsonb,jsonb) from public,anon;
revoke all on function public.erp_r49_update_cloud_purchase(uuid,jsonb,jsonb) from public,anon;
grant execute on function public.erp_r49_create_cloud_sale(uuid,jsonb,jsonb) to authenticated,service_role;
grant execute on function public.erp_r49_create_cloud_resale(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r49_update_cloud_sale(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r49_create_cloud_purchase(uuid,jsonb,jsonb) to authenticated,service_role;
grant execute on function public.erp_r49_update_cloud_purchase(uuid,jsonb,jsonb) to authenticated,service_role;
revoke execute on function public.erp_create_cloud_sale(uuid,jsonb,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_create_cloud_resale(uuid,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_update_cloud_sale(uuid,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_create_cloud_purchase(uuid,jsonb,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_update_cloud_purchase(uuid,jsonb,jsonb) from authenticated,anon,public;
grant execute on function public.erp_create_cloud_sale(uuid,jsonb,jsonb) to service_role;
grant execute on function public.erp_create_cloud_resale(uuid,jsonb) to service_role;
grant execute on function public.erp_update_cloud_sale(uuid,jsonb) to service_role;
grant execute on function public.erp_create_cloud_purchase(uuid,jsonb,jsonb) to service_role;
grant execute on function public.erp_update_cloud_purchase(uuid,jsonb,jsonb) to service_role;



-- Notification read/archive state is per user. A broadcast notification must
-- never become read or archived for every employee because one employee opened
-- it. The server resolves the current user's identity and role; client-supplied
-- identity selectors are no longer trusted for reads.
create table if not exists public.erp_notification_user_states(
  company_id uuid not null,
  notification_id uuid not null,
  user_key text not null,
  is_read boolean not null default false,
  archived boolean not null default false,
  read_at timestamptz,
  archived_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key(company_id,notification_id,user_key)
);
alter table public.erp_notification_user_states enable row level security;
revoke all on table public.erp_notification_user_states from public,anon,authenticated;

create or replace function public.erp_r49_notification_user_key()
returns text language sql stable security invoker set search_path=public as $$
  select nullif(btrim(coalesce(auth.uid()::text,public.current_external_uid(),'')),'')
$$;

create or replace function public.erp_r49_notification_visible(
  p_company_id uuid,p_data jsonb
) returns boolean language plpgsql stable security definer set search_path=public as $$
declare
  v_key text:=public.erp_r49_notification_user_key();
  v_erp_user text;
  v_role_code text;
  v_role_id text;
  v_user_target text:=nullif(btrim(coalesce(p_data->>'userId','')),'');
  v_role_target text:=nullif(btrim(coalesce(p_data->>'roleId','')),'');
begin
  if v_key is null or not public.is_active_company_member(p_company_id) then return false; end if;
  v_erp_user:=public.erp_current_cloud_erp_user_id(p_company_id);
  select nullif(btrim(m.role_code),'') into v_role_code
  from public.company_memberships m
  where m.company_id=p_company_id
    and public.erp_membership_matches_current_user(m.user_id,m.user_uid)
    and m.is_active
  order by m.updated_at desc nulls last,m.created_at desc limit 1;
  if v_erp_user is not null then
    select nullif(btrim(r.payload->>'roleId'),'') into v_role_id
    from public.erp_records r
    join public.companies c on c.id=p_company_id and c.slug=r.company_id
    where r.entity_type='users' and r.record_id=v_erp_user and not r.is_deleted and r.deleted_at is null
    order by r.updated_at desc limit 1;
  end if;
  return (v_user_target is null and v_role_target is null)
      or v_user_target in (v_key,coalesce(v_erp_user,''))
      or v_role_target in (coalesce(v_role_code,''),coalesce(v_role_id,''));
end $$;

create or replace function public.erp_r49_create_cloud_notification(
  p_company_id uuid,p_user_id text,p_role_id text,p_title_ar text,p_title_en text,
  p_body_ar text,p_body_en text,p_type text,p_reference_type text,p_reference_id text
) returns uuid language plpgsql security definer set search_path=public as $$
declare
  v_id uuid:=gen_random_uuid();
  v_key text:=public.erp_r49_notification_user_key();
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id) then
    if nullif(btrim(coalesce(p_role_id,'')),'') is not null
       or nullif(btrim(coalesce(p_user_id,'')),'') is distinct from v_key then
      raise exception 'permission_denied:notification_target' using errcode='42501';
    end if;
  end if;
  insert into public.erp_enterprise_notifications(company_id,id,data)
  values(p_company_id,v_id,jsonb_build_object(
    'userId',nullif(btrim(coalesce(p_user_id,'')),''),
    'roleId',nullif(btrim(coalesce(p_role_id,'')),''),
    'titleAr',coalesce(p_title_ar,''),'titleEn',coalesce(p_title_en,''),
    'bodyAr',coalesce(p_body_ar,''),'bodyEn',coalesce(p_body_en,''),
    'type',coalesce(nullif(btrim(p_type),''),'info'),
    'referenceType',p_reference_type,'referenceId',p_reference_id,'createdAt',now()
  ));
  return v_id;
end $$;

create or replace function public.erp_r49_list_cloud_notifications(
  p_company_id uuid,p_unread_only boolean default false,p_limit integer default 100,p_offset integer default 0
) returns setof jsonb language plpgsql stable security definer set search_path=public as $$
declare v_key text:=public.erp_r49_notification_user_key();
begin
  perform public.erp_active_company_context(p_company_id);
  if v_key is null then raise exception 'notification_user_identity_required' using errcode='42501'; end if;
  return query
  select n.data||jsonb_build_object(
    'id',n.id,'createdAt',coalesce(n.data->>'createdAt',n.created_at::text),
    'updatedAt',n.updated_at::text,'isRead',coalesce(s.is_read,false)
  )
  from public.erp_enterprise_notifications n
  left join public.erp_notification_user_states s
    on s.company_id=n.company_id and s.notification_id=n.id and s.user_key=v_key
  where n.company_id=p_company_id and not n.is_deleted
    and public.erp_r49_notification_visible(p_company_id,n.data)
    and not coalesce(s.archived,false)
    and (not coalesce(p_unread_only,false) or not coalesce(s.is_read,false))
  order by coalesce(s.is_read,false),n.created_at desc
  limit greatest(1,least(coalesce(p_limit,100),500))
  offset greatest(coalesce(p_offset,0),0);
end $$;

create or replace function public.erp_r49_cloud_unread_notification_count(p_company_id uuid)
returns integer language plpgsql stable security definer set search_path=public as $$
declare v_key text:=public.erp_r49_notification_user_key(); v_count integer;
begin
  perform public.erp_active_company_context(p_company_id);
  if v_key is null then raise exception 'notification_user_identity_required' using errcode='42501'; end if;
  select count(*)::integer into v_count
  from public.erp_enterprise_notifications n
  left join public.erp_notification_user_states s
    on s.company_id=n.company_id and s.notification_id=n.id and s.user_key=v_key
  where n.company_id=p_company_id and not n.is_deleted
    and public.erp_r49_notification_visible(p_company_id,n.data)
    and not coalesce(s.archived,false) and not coalesce(s.is_read,false);
  return coalesce(v_count,0);
end $$;

create or replace function public.erp_r49_mark_cloud_notification_read(
  p_company_id uuid,p_notification_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare v_key text:=public.erp_r49_notification_user_key(); v_data jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  select data into v_data from public.erp_enterprise_notifications
   where company_id=p_company_id and id=p_notification_id and not is_deleted;
  if not found or not public.erp_r49_notification_visible(p_company_id,v_data) then
    raise exception 'notification_not_found_or_forbidden' using errcode='42501';
  end if;
  insert into public.erp_notification_user_states(company_id,notification_id,user_key,is_read,read_at,updated_at)
  values(p_company_id,p_notification_id,v_key,true,now(),now())
  on conflict(company_id,notification_id,user_key) do update
    set is_read=true,read_at=coalesce(erp_notification_user_states.read_at,excluded.read_at),updated_at=now();
end $$;

create or replace function public.erp_r49_mark_all_cloud_notifications_read(p_company_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_key text:=public.erp_r49_notification_user_key();
begin
  perform public.erp_active_company_context(p_company_id);
  insert into public.erp_notification_user_states(company_id,notification_id,user_key,is_read,read_at,updated_at)
  select p_company_id,n.id,v_key,true,now(),now()
  from public.erp_enterprise_notifications n
  where n.company_id=p_company_id and not n.is_deleted
    and public.erp_r49_notification_visible(p_company_id,n.data)
  on conflict(company_id,notification_id,user_key) do update
    set is_read=true,read_at=coalesce(erp_notification_user_states.read_at,excluded.read_at),updated_at=now();
end $$;

create or replace function public.erp_r49_archive_cloud_notification(
  p_company_id uuid,p_notification_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare v_key text:=public.erp_r49_notification_user_key(); v_data jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  select data into v_data from public.erp_enterprise_notifications
   where company_id=p_company_id and id=p_notification_id and not is_deleted;
  if not found or not public.erp_r49_notification_visible(p_company_id,v_data) then
    raise exception 'notification_not_found_or_forbidden' using errcode='42501';
  end if;
  insert into public.erp_notification_user_states(company_id,notification_id,user_key,archived,archived_at,updated_at)
  values(p_company_id,p_notification_id,v_key,true,now(),now())
  on conflict(company_id,notification_id,user_key) do update
    set archived=true,archived_at=coalesce(erp_notification_user_states.archived_at,excluded.archived_at),updated_at=now();
end $$;

revoke all on function public.erp_r49_notification_user_key() from public,anon;
revoke all on function public.erp_r49_notification_visible(uuid,jsonb) from public,anon,authenticated;
revoke all on function public.erp_r49_create_cloud_notification(uuid,text,text,text,text,text,text,text,text,text) from public,anon;
revoke all on function public.erp_r49_list_cloud_notifications(uuid,boolean,integer,integer) from public,anon;
revoke all on function public.erp_r49_cloud_unread_notification_count(uuid) from public,anon;
revoke all on function public.erp_r49_mark_cloud_notification_read(uuid,uuid) from public,anon;
revoke all on function public.erp_r49_mark_all_cloud_notifications_read(uuid) from public,anon;
revoke all on function public.erp_r49_archive_cloud_notification(uuid,uuid) from public,anon;
grant execute on function public.erp_r49_notification_user_key() to authenticated,service_role;
grant execute on function public.erp_r49_notification_visible(uuid,jsonb) to service_role;
grant execute on function public.erp_r49_create_cloud_notification(uuid,text,text,text,text,text,text,text,text,text) to authenticated,service_role;
grant execute on function public.erp_r49_list_cloud_notifications(uuid,boolean,integer,integer) to authenticated,service_role;
grant execute on function public.erp_r49_cloud_unread_notification_count(uuid) to authenticated,service_role;
grant execute on function public.erp_r49_mark_cloud_notification_read(uuid,uuid) to authenticated,service_role;
grant execute on function public.erp_r49_mark_all_cloud_notifications_read(uuid) to authenticated,service_role;
grant execute on function public.erp_r49_archive_cloud_notification(uuid,uuid) to authenticated,service_role;

revoke execute on function public.erp_create_cloud_notification(uuid,uuid,uuid,text,text,text,text,text,text,text) from authenticated,anon,public;
revoke execute on function public.erp_list_cloud_notifications(uuid,uuid,uuid,boolean,integer,integer) from authenticated,anon,public;
revoke execute on function public.erp_cloud_unread_notification_count(uuid,uuid,uuid) from authenticated,anon,public;
revoke execute on function public.erp_mark_cloud_notification_read(uuid,uuid) from authenticated,anon,public;
revoke execute on function public.erp_mark_all_cloud_notifications_read(uuid,uuid,uuid) from authenticated,anon,public;
revoke execute on function public.erp_archive_cloud_notification(uuid,uuid) from authenticated,anon,public;
grant execute on function public.erp_create_cloud_notification(uuid,uuid,uuid,text,text,text,text,text,text,text) to service_role;
grant execute on function public.erp_list_cloud_notifications(uuid,uuid,uuid,boolean,integer,integer) to service_role;
grant execute on function public.erp_cloud_unread_notification_count(uuid,uuid,uuid) to service_role;
grant execute on function public.erp_mark_cloud_notification_read(uuid,uuid) to service_role;
grant execute on function public.erp_mark_all_cloud_notifications_read(uuid,uuid,uuid) to service_role;
grant execute on function public.erp_archive_cloud_notification(uuid,uuid) to service_role;


-- Professional accounting write operations are granular permissions, not a
-- legacy role shortcut.  The historical implementations remain the proven
-- accounting logic and are reachable from the browser only through these R49
-- wrappers. The transaction-local bridge lets those implementations pass their
-- legacy can_manage_master_data() check only after the exact permission has
-- already been validated for the current company.
create or replace function public.erp_r49_assign_cloud_entry_dimensions(
  p_company_id uuid,p_entry_id text,p_entry_date timestamptz,
  p_cost_center_id text,p_project_id text
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'accounting.update') then
    raise exception 'permission_denied:accounting.update' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','accounting.update',true);
  perform public.erp_assign_cloud_entry_dimensions(
    p_company_id,p_entry_id,p_entry_date,p_cost_center_id,p_project_id
  );
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

create or replace function public.erp_r49_save_cloud_cost_center(
  p_company_id uuid,p_cost_center jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare v_id text:=nullif(btrim(coalesce(p_cost_center->>'id','')),''); v_permission text;
begin
  perform public.erp_active_company_context(p_company_id);
  v_permission:=case when v_id is not null and exists(
    select 1 from public.erp_cost_centers where company_id=p_company_id and id=v_id and not is_deleted
  ) then 'accounting.update' else 'accounting.create' end;
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,v_permission) then
    raise exception 'permission_denied:%',v_permission using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission',v_permission,true);
  perform public.erp_save_cloud_cost_center(p_company_id,p_cost_center);
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

create or replace function public.erp_r49_save_cloud_accounting_project(
  p_company_id uuid,p_project jsonb
) returns void language plpgsql security definer set search_path=public as $$
declare v_id text:=nullif(btrim(coalesce(p_project->>'id','')),''); v_permission text;
begin
  perform public.erp_active_company_context(p_company_id);
  v_permission:=case when v_id is not null and exists(
    select 1 from public.erp_accounting_projects where company_id=p_company_id and id=v_id and not is_deleted
  ) then 'accounting.update' else 'accounting.create' end;
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,v_permission) then
    raise exception 'permission_denied:%',v_permission using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission',v_permission,true);
  perform public.erp_save_cloud_accounting_project(p_company_id,p_project);
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

create or replace function public.erp_r49_post_cloud_recurring_template(
  p_company_id uuid,p_template_id text,p_posting_date timestamptz,p_user_id text
) returns text language plpgsql security definer set search_path=public as $$
declare v_result text;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'accounting.post') then
    raise exception 'permission_denied:accounting.post' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','accounting.post',true);
  v_result:=public.erp_post_cloud_recurring_template(p_company_id,p_template_id,p_posting_date,p_user_id);
  perform set_config('qualityline.r49_master_permission','',true);
  return v_result;
end $$;

create or replace function public.erp_r49_change_cloud_fiscal_period_status(
  p_company_id uuid,p_period_id text,p_new_status text,p_performed_by text,p_reason text
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'accounting.post') then
    raise exception 'permission_denied:accounting.post' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','accounting.post',true);
  perform public.erp_change_cloud_fiscal_period_status(
    p_company_id,p_period_id,p_new_status,p_performed_by,p_reason
  );
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

create or replace function public.erp_r49_close_cloud_fiscal_year(
  p_company_id uuid,p_fiscal_year_id text,p_retained_earnings_account_id text,p_user_id text
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id)
     and not public.erp_cloud_user_has_permission(p_company_id,'accounting.post') then
    raise exception 'permission_denied:accounting.post' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','accounting.post',true);
  perform public.erp_close_cloud_fiscal_year(
    p_company_id,p_fiscal_year_id,p_retained_earnings_account_id,p_user_id
  );
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

revoke all on function public.erp_r49_assign_cloud_entry_dimensions(uuid,text,timestamptz,text,text) from public,anon;
revoke all on function public.erp_r49_save_cloud_cost_center(uuid,jsonb) from public,anon;
revoke all on function public.erp_r49_save_cloud_accounting_project(uuid,jsonb) from public,anon;
revoke all on function public.erp_r49_post_cloud_recurring_template(uuid,text,timestamptz,text) from public,anon;
revoke all on function public.erp_r49_change_cloud_fiscal_period_status(uuid,text,text,text,text) from public,anon;
revoke all on function public.erp_r49_close_cloud_fiscal_year(uuid,text,text,text) from public,anon;
grant execute on function public.erp_r49_assign_cloud_entry_dimensions(uuid,text,timestamptz,text,text) to authenticated,service_role;
grant execute on function public.erp_r49_save_cloud_cost_center(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r49_save_cloud_accounting_project(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r49_post_cloud_recurring_template(uuid,text,timestamptz,text) to authenticated,service_role;
grant execute on function public.erp_r49_change_cloud_fiscal_period_status(uuid,text,text,text,text) to authenticated,service_role;
grant execute on function public.erp_r49_close_cloud_fiscal_year(uuid,text,text,text) to authenticated,service_role;

revoke execute on function public.erp_assign_cloud_entry_dimensions(uuid,text,timestamptz,text,text) from authenticated,anon,public;
revoke execute on function public.erp_save_cloud_cost_center(uuid,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_save_cloud_accounting_project(uuid,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_post_cloud_recurring_template(uuid,text,timestamptz,text) from authenticated,anon,public;
revoke execute on function public.erp_change_cloud_fiscal_period_status(uuid,text,text,text,text) from authenticated,anon,public;
revoke execute on function public.erp_close_cloud_fiscal_year(uuid,text,text,text) from authenticated,anon,public;
grant execute on function public.erp_assign_cloud_entry_dimensions(uuid,text,timestamptz,text,text) to service_role;
grant execute on function public.erp_save_cloud_cost_center(uuid,jsonb) to service_role;
grant execute on function public.erp_save_cloud_accounting_project(uuid,jsonb) to service_role;
grant execute on function public.erp_post_cloud_recurring_template(uuid,text,timestamptz,text) to service_role;
grant execute on function public.erp_change_cloud_fiscal_period_status(uuid,text,text,text,text) to service_role;
grant execute on function public.erp_close_cloud_fiscal_year(uuid,text,text,text) to service_role;


-- Canonical general-accounting browser writes.  R22/R9 already contain the
-- field-level guards; these R49 wrappers add fail-closed financial currency
-- validation and make the granular permission usable even for custom roles
-- that are not part of the historical can_manage_master_data role list.
create or replace function public.erp_r49_save_cloud_ledger_account(
  p_company_id uuid,p_account jsonb,p_require_existing boolean default false
) returns void language plpgsql security definer set search_path=public as $$
declare v_id text:=nullif(btrim(coalesce(p_account->>'id','')),''); v_permission text; v_currency text;
begin
  perform public.erp_active_company_context(p_company_id);
  v_currency:=upper(btrim(coalesce(p_account->>'currency','')));
  if v_currency not in ('USD','IQD','MULTI') then raise exception 'account_currency_required' using errcode='22023'; end if;
  v_permission:=case when v_id is not null and exists(
    select 1 from public.erp_accounts where organization_id=p_company_id and account_id=v_id
  ) then 'accounting.update' else 'accounting.create' end;
  if p_require_existing and v_permission<>'accounting.update' then raise exception 'account_not_found'; end if;
  if not public.is_company_admin(p_company_id) and not public.erp_cloud_user_has_permission(p_company_id,v_permission) then
    raise exception 'permission_denied:%',v_permission using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission',v_permission,true);
  perform public.erp_r22_save_cloud_ledger_account(p_company_id,p_account,p_require_existing);
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

create or replace function public.erp_r49_delete_cloud_ledger_account(p_company_id uuid,p_account_id text)
returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id) and not public.erp_cloud_user_has_permission(p_company_id,'accounting.delete') then
    raise exception 'permission_denied:accounting.delete' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','accounting.update',true);
  perform public.erp_delete_cloud_ledger_account(p_company_id,p_account_id);
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

create or replace function public.erp_r49_post_cloud_manual_journal(
  p_company_id uuid,p_entry jsonb,p_lines jsonb
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id) and not public.erp_cloud_user_has_permission(p_company_id,'accounting.create') then
    raise exception 'permission_denied:accounting.create' using errcode='42501';
  end if;
  if upper(btrim(coalesce(p_entry->>'currency',''))) not in ('USD','IQD') then
    raise exception 'journal_currency_required' using errcode='22023';
  end if;
  perform set_config('qualityline.r49_master_permission','accounting.create',true);
  perform public.erp_r22_post_cloud_manual_journal(p_company_id,p_entry,p_lines);
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

create or replace function public.erp_r49_update_cloud_manual_journal(
  p_company_id uuid,p_entry jsonb,p_lines jsonb
) returns void language plpgsql security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id) and not public.erp_cloud_user_has_permission(p_company_id,'accounting.update') then
    raise exception 'permission_denied:accounting.update' using errcode='42501';
  end if;
  if upper(btrim(coalesce(p_entry->>'currency',''))) not in ('USD','IQD') then
    raise exception 'journal_currency_required' using errcode='22023';
  end if;
  perform set_config('qualityline.r49_master_permission','accounting.update',true);
  perform public.erp_r22_update_cloud_manual_journal(p_company_id,p_entry,p_lines);
  perform set_config('qualityline.r49_master_permission','',true);
end $$;

create or replace function public.erp_r49_post_cloud_expense(p_company_id uuid,p_expense jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_result jsonb; v_currency text:=upper(btrim(coalesce(p_expense->>'currency','')));
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id) and not public.erp_cloud_user_has_permission(p_company_id,'accounting.create') then
    raise exception 'permission_denied:accounting.create' using errcode='42501';
  end if;
  if v_currency not in ('USD','IQD') then raise exception 'expense_currency_required' using errcode='22023'; end if;
  perform set_config('qualityline.r49_master_permission','accounting.create',true);
  v_result:=public.erp_r22_post_cloud_expense(p_company_id,p_expense);
  perform set_config('qualityline.r49_master_permission','',true);
  return v_result;
end $$;

create or replace function public.erp_r49_save_fixed_asset(p_company_id uuid,p_asset jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid:=public.erp_r49_try_uuid(p_asset->>'id'); v_permission text; v_result uuid; v_currency text;
begin
  perform public.erp_active_company_context(p_company_id);
  v_currency:=upper(btrim(coalesce(p_asset->>'currency','')));
  if v_currency not in ('USD','IQD') then raise exception 'fixed_asset_currency_required' using errcode='22023'; end if;
  if public.erp_try_date(p_asset->>'acquisitionDate',null) is null then
    raise exception 'fixed_asset_acquisition_date_required' using errcode='22023';
  end if;
  v_permission:=case when v_id is not null and exists(
    select 1 from public.erp_fixed_assets where company_id=p_company_id and id=v_id and not is_deleted
  ) then 'accounting.update' else 'accounting.create' end;
  if not public.is_company_admin(p_company_id) and not public.erp_cloud_user_has_permission(p_company_id,v_permission) then
    raise exception 'permission_denied:%',v_permission using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission',v_permission,true);
  v_result:=public.erp_r22_save_fixed_asset(p_company_id,p_asset);
  perform set_config('qualityline.r49_master_permission','',true);
  return v_result;
end $$;

create or replace function public.erp_r49_post_fixed_asset_depreciation_at(
  p_company_id uuid,p_asset_id uuid,p_effective_at timestamptz default now()
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_result uuid;
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id) and not public.erp_cloud_user_has_permission(p_company_id,'accounting.post') then
    raise exception 'permission_denied:accounting.post' using errcode='42501';
  end if;
  perform set_config('qualityline.r49_master_permission','accounting.post',true);
  v_result:=public.erp_r22_post_fixed_asset_depreciation_at(p_company_id,p_asset_id,p_effective_at);
  perform set_config('qualityline.r49_master_permission','',true);
  return v_result;
end $$;

revoke all on function public.erp_r49_save_cloud_ledger_account(uuid,jsonb,boolean) from public,anon;
revoke all on function public.erp_r49_delete_cloud_ledger_account(uuid,text) from public,anon;
revoke all on function public.erp_r49_post_cloud_manual_journal(uuid,jsonb,jsonb) from public,anon;
revoke all on function public.erp_r49_update_cloud_manual_journal(uuid,jsonb,jsonb) from public,anon;
revoke all on function public.erp_r49_post_cloud_expense(uuid,jsonb) from public,anon;
revoke all on function public.erp_r49_save_fixed_asset(uuid,jsonb) from public,anon;
revoke all on function public.erp_r49_post_fixed_asset_depreciation_at(uuid,uuid,timestamptz) from public,anon;
grant execute on function public.erp_r49_save_cloud_ledger_account(uuid,jsonb,boolean) to authenticated,service_role;
grant execute on function public.erp_r49_delete_cloud_ledger_account(uuid,text) to authenticated,service_role;
grant execute on function public.erp_r49_post_cloud_manual_journal(uuid,jsonb,jsonb) to authenticated,service_role;
grant execute on function public.erp_r49_update_cloud_manual_journal(uuid,jsonb,jsonb) to authenticated,service_role;
grant execute on function public.erp_r49_post_cloud_expense(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r49_save_fixed_asset(uuid,jsonb) to authenticated,service_role;
grant execute on function public.erp_r49_post_fixed_asset_depreciation_at(uuid,uuid,timestamptz) to authenticated,service_role;

-- No browser bypass around the R49 permission/currency boundary.
revoke execute on function public.erp_r22_save_cloud_ledger_account(uuid,jsonb,boolean) from authenticated,anon,public;
revoke execute on function public.erp_r22_post_cloud_manual_journal(uuid,jsonb,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_r22_update_cloud_manual_journal(uuid,jsonb,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_r22_post_cloud_expense(uuid,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_r22_save_fixed_asset(uuid,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_r22_post_fixed_asset_depreciation_at(uuid,uuid,timestamptz) from authenticated,anon,public;
revoke execute on function public.erp_r9_save_cloud_ledger_account(uuid,jsonb,boolean) from authenticated,anon,public;
revoke execute on function public.erp_r9_post_cloud_manual_journal(uuid,jsonb,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_r9_update_cloud_manual_journal(uuid,jsonb,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_r9_post_cloud_expense(uuid,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_r9_save_fixed_asset(uuid,jsonb) from authenticated,anon,public;
revoke execute on function public.erp_r9_post_fixed_asset_depreciation_at(uuid,uuid,timestamptz) from authenticated,anon,public;
revoke execute on function public.erp_delete_cloud_ledger_account(uuid,text) from authenticated,anon,public;
grant execute on function public.erp_r22_save_cloud_ledger_account(uuid,jsonb,boolean) to service_role;
grant execute on function public.erp_r22_post_cloud_manual_journal(uuid,jsonb,jsonb) to service_role;
grant execute on function public.erp_r22_update_cloud_manual_journal(uuid,jsonb,jsonb) to service_role;
grant execute on function public.erp_r22_post_cloud_expense(uuid,jsonb) to service_role;
grant execute on function public.erp_r22_save_fixed_asset(uuid,jsonb) to service_role;
grant execute on function public.erp_r22_post_fixed_asset_depreciation_at(uuid,uuid,timestamptz) to service_role;
grant execute on function public.erp_delete_cloud_ledger_account(uuid,text) to service_role;


-- Partner profile financial summaries are currency vectors.  The historical
-- scalar summary could add USD and IQD and also labelled missing legacy
-- currency as USD.  R49 preserves non-financial metadata from the proven
-- summary, but replaces monetary aggregates/documents with currency-explicit
-- values and never invents a currency.
create or replace function public.erp_r49_business_partner_card_summary(
  p_company_id uuid,p_partner_kind text,p_partner_id text
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
  v_kind text:=lower(btrim(coalesce(p_partner_kind,'')));
  v_base jsonb;
  v_partner jsonb:='{}'::jsonb;
  v_total jsonb:='{}'::jsonb;
  v_paid jsonb:='{}'::jsonb;
  v_outstanding jsonb:='{}'::jsonb;
  v_currencies jsonb:='[]'::jsonb;
  v_documents jsonb:='[]'::jsonb;
  v_default_currency text;
begin
  perform public.erp_active_company_context(p_company_id);
  if v_kind not in ('customer','supplier') then raise exception 'unsupported_partner_kind'; end if;
  v_base:=public.erp_business_partner_card_summary(p_company_id,v_kind,p_partner_id);

  if v_kind='customer' then
    select coalesce(data,'{}'::jsonb) into v_partner from public.erp_customers
      where company_id=p_company_id and id=p_partner_id and not is_deleted;
    select
      coalesce(jsonb_object_agg(currency,total_amount),'{}'::jsonb),
      coalesce(jsonb_object_agg(currency,paid_amount),'{}'::jsonb),
      coalesce(jsonb_object_agg(currency,outstanding_amount),'{}'::jsonb)
    into v_total,v_paid,v_outstanding
    from (
      select currency,
        sum(public.erp_try_numeric(coalesce(data->>'totalAmount',data->>'salePrice'),0)) total_amount,
        sum(public.erp_try_numeric(data->>'paidAmount',0)) paid_amount,
        sum(public.erp_try_numeric(data->>'remainingAmount',
          public.erp_try_numeric(coalesce(data->>'totalAmount',data->>'salePrice'),0)-public.erp_try_numeric(data->>'paidAmount',0))) outstanding_amount
      from (
        select data,
          case when upper(coalesce(nullif(data->>'currencyCode',''),nullif(data->>'currency',''))) in ('USD','IQD')
            then upper(coalesce(nullif(data->>'currencyCode',''),nullif(data->>'currency',''))) else null end currency
        from public.erp_sales where company_id=p_company_id and not is_deleted
          and coalesce(data->>'customerId',data->>'clientId','')=p_partner_id
      ) q where currency is not null group by currency
    ) totals;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.document_date desc),'[]'::jsonb) into v_documents from (
      select
        coalesce(nullif(data->>'invoiceNumber',''),nullif(data->>'saleNumber',''),id) document_number,
        coalesce(data->>'saleDate',data->>'createdAt',created_at::text) document_date,
        case when upper(coalesce(nullif(data->>'currencyCode',''),nullif(data->>'currency',''))) in ('USD','IQD')
          then upper(coalesce(nullif(data->>'currencyCode',''),nullif(data->>'currency',''))) else null end currency,
        public.erp_try_numeric(coalesce(data->>'totalAmount',data->>'salePrice'),0) total_amount,
        public.erp_try_numeric(data->>'paidAmount',0) paid_amount,
        public.erp_try_numeric(data->>'remainingAmount',public.erp_try_numeric(coalesce(data->>'totalAmount',data->>'salePrice'),0)-public.erp_try_numeric(data->>'paidAmount',0)) outstanding_amount,
        coalesce(nullif(data->>'paymentStatus',''),nullif(data->>'status',''),'open') status
      from public.erp_sales where company_id=p_company_id and not is_deleted
        and coalesce(data->>'customerId',data->>'clientId','')=p_partner_id
      order by coalesce(data->>'saleDate',data->>'createdAt',created_at::text) desc limit 12
    ) x;
  else
    select coalesce(data,'{}'::jsonb) into v_partner from public.erp_suppliers
      where company_id=p_company_id and id=p_partner_id and not is_deleted;
    select
      coalesce(jsonb_object_agg(currency,total_amount),'{}'::jsonb),
      coalesce(jsonb_object_agg(currency,paid_amount),'{}'::jsonb),
      coalesce(jsonb_object_agg(currency,outstanding_amount),'{}'::jsonb)
    into v_total,v_paid,v_outstanding
    from (
      select currency,
        sum(public.erp_try_numeric(data->>'totalAmount',0)) total_amount,
        sum(public.erp_try_numeric(data->>'paidAmount',0)) paid_amount,
        sum(public.erp_try_numeric(data->>'remainingAmount',public.erp_try_numeric(data->>'totalAmount',0)-public.erp_try_numeric(data->>'paidAmount',0))) outstanding_amount
      from (
        select data,
          case when upper(coalesce(nullif(data->>'currencyCode',''),nullif(data->>'currency',''))) in ('USD','IQD')
            then upper(coalesce(nullif(data->>'currencyCode',''),nullif(data->>'currency',''))) else null end currency
        from public.erp_purchases where company_id=p_company_id and not is_deleted and coalesce(data->>'supplierId','')=p_partner_id
      ) q where currency is not null group by currency
    ) totals;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.document_date desc),'[]'::jsonb) into v_documents from (
      select
        coalesce(nullif(data->>'invoiceNumber',''),nullif(data->>'purchaseNumber',''),id) document_number,
        coalesce(data->>'purchaseDate',data->>'createdAt',created_at::text) document_date,
        case when upper(coalesce(nullif(data->>'currencyCode',''),nullif(data->>'currency',''))) in ('USD','IQD')
          then upper(coalesce(nullif(data->>'currencyCode',''),nullif(data->>'currency',''))) else null end currency,
        public.erp_try_numeric(data->>'totalAmount',0) total_amount,
        public.erp_try_numeric(data->>'paidAmount',0) paid_amount,
        public.erp_try_numeric(data->>'remainingAmount',public.erp_try_numeric(data->>'totalAmount',0)-public.erp_try_numeric(data->>'paidAmount',0)) outstanding_amount,
        coalesce(nullif(data->>'paymentStatus',''),nullif(data->>'status',''),'open') status
      from public.erp_purchases where company_id=p_company_id and not is_deleted and coalesce(data->>'supplierId','')=p_partner_id
      order by coalesce(data->>'purchaseDate',data->>'createdAt',created_at::text) desc limit 12
    ) x;
  end if;

  select coalesce(jsonb_agg(key order by key),'[]'::jsonb) into v_currencies
  from (select key from jsonb_object_keys(v_total) key) c;
  v_default_currency:=case when upper(btrim(coalesce(v_partner->>'currency',''))) in ('USD','IQD')
    then upper(btrim(v_partner->>'currency')) else null end;

  return v_base||jsonb_build_object(
    'defaultCurrency',v_default_currency,'currencies',v_currencies,
    'transactionTotal',null,'paidTotal',null,'outstandingTotal',null,
    'transactionTotalByCurrency',v_total,'paidTotalByCurrency',v_paid,
    'outstandingTotalByCurrency',v_outstanding,'recentDocuments',v_documents
  );
end $$;
revoke all on function public.erp_r49_business_partner_card_summary(uuid,text,text) from public,anon;
grant execute on function public.erp_r49_business_partner_card_summary(uuid,text,text) to authenticated,service_role;
revoke execute on function public.erp_business_partner_card_summary(uuid,text,text) from authenticated,anon,public;
grant execute on function public.erp_business_partner_card_summary(uuid,text,text) to service_role;

-- Cashbox selection used by Sales/Purchases/Maintenance is read-only but must
-- fail closed: a missing active flag or currency cannot be converted into an
-- active USD cashbox by a legacy default.
create or replace function public.erp_r49_list_cloud_active_cash_accounts(p_company_id uuid)
returns setof jsonb language sql stable security definer set search_path=public as $$
  select jsonb_build_object('id',c.id,'name',coalesce(c.data->>'name',''),'currency',upper(c.data->>'currency'))
  from public.erp_cash_accounts c
  where c.company_id=p_company_id and not c.is_deleted
    and public.is_active_company_member(p_company_id)
    and public.erp_try_boolean(c.data->>'isActive',false)
    and upper(coalesce(c.data->>'currency','')) in ('USD','IQD')
  order by coalesce(c.data->>'name','')
$$;
revoke all on function public.erp_r49_list_cloud_active_cash_accounts(uuid) from public,anon;
grant execute on function public.erp_r49_list_cloud_active_cash_accounts(uuid) to authenticated,service_role;
revoke execute on function public.erp_list_cloud_active_cash_accounts(uuid) from authenticated,anon,public;
grant execute on function public.erp_list_cloud_active_cash_accounts(uuid) to service_role;


create or replace function public.erp_r49_list_cloud_active_warehouses(p_company_id uuid)
returns setof jsonb language plpgsql stable security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  return query
  select jsonb_build_object('id',w.id,'name',coalesce(w.data->>'name',''),'code',coalesce(w.data->>'code',''))
  from public.erp_warehouses w
  where w.company_id=p_company_id and not w.is_deleted
    and public.erp_try_boolean(w.data->>'isActive',false)
  order by coalesce(w.data->>'name','');
end $$;
revoke all on function public.erp_r49_list_cloud_active_warehouses(uuid) from public,anon;
grant execute on function public.erp_r49_list_cloud_active_warehouses(uuid) to authenticated,service_role;
revoke execute on function public.erp_list_cloud_active_warehouses(uuid) from authenticated,anon,public;
grant execute on function public.erp_list_cloud_active_warehouses(uuid) to service_role;

create or replace function public.erp_r49_list_partner_unapplied_payments(
  p_company_id uuid,p_party_type text,p_party_id text,p_currency text
) returns setof jsonb language plpgsql stable security definer set search_path=public as $$
declare v_currency text:=upper(btrim(coalesce(p_currency,'')));
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id) and not public.erp_cloud_user_has_permission(p_company_id,'accounting.view') then
    raise exception 'permission_denied:accounting.view' using errcode='42501';
  end if;
  if v_currency not in ('USD','IQD') then raise exception 'currency_required' using errcode='22023'; end if;
  return query
  select jsonb_build_object(
    'transaction_id',ct.id,
    'voucher_number',coalesce(ct.data->>'voucherNumber',ct.data->>'voucher_number',ct.id),
    'transaction_date',coalesce(ct.data->>'transactionDate',ct.data->>'transaction_date',ct.created_at::text),
    'amount',greatest(0,public.erp_v731_advance_original_amount(ct.data)-coalesce(a.allocated,0)),
    'original_amount',public.erp_v731_advance_original_amount(ct.data),
    'allocated_amount',coalesce(a.allocated,0),
    'currency',upper(coalesce(nullif(ct.data->>'accountCurrency',''),nullif(ct.data->>'invoiceCurrency',''),nullif(ct.data->>'currency',''))),
    'type',lower(coalesce(ct.data->>'type','')),'notes',coalesce(ct.data->>'notes',''),
    'party_type',coalesce(ct.data->>'partyType',ct.data->>'party_type'),
    'party_id',coalesce(ct.data->>'partyId',ct.data->>'party_id'),
    'detached_from_order_id',coalesce(ct.data->>'detachedFromOrderId',ct.data->>'detached_from_order_id'),
    'detached_from_maintenance_order_id',coalesce(ct.data->>'detachedFromMaintenanceOrderId',ct.data->>'detached_from_maintenance_order_id'),
    'journal_entry_id',coalesce(ct.data->>'journalEntryId',ct.data->>'journal_entry_id')
  )
  from public.erp_cash_transactions ct
  left join lateral (
    select coalesce(sum(x.amount),0) allocated from public.erp_partner_advance_allocations x
    where x.company_id=ct.company_id and x.cash_transaction_id=ct.id and not x.is_deleted
  ) a on true
  where ct.company_id=p_company_id and not ct.is_deleted
    and lower(coalesce(ct.data->>'referenceType',ct.data->>'reference_type',''))='partner_advance'
    and lower(coalesce(ct.data->>'partyType',ct.data->>'party_type',''))=lower(btrim(p_party_type))
    and coalesce(ct.data->>'partyId',ct.data->>'party_id','')=coalesce(p_party_id,'')
    and upper(coalesce(nullif(ct.data->>'accountCurrency',''),nullif(ct.data->>'invoiceCurrency',''),nullif(ct.data->>'currency','')))=v_currency
    and public.erp_v731_advance_original_amount(ct.data)-coalesce(a.allocated,0)>0.001
  order by coalesce(public.erp_try_timestamptz(ct.data->>'transactionDate',ct.created_at),ct.created_at) desc,ct.created_at desc;
end $$;
revoke all on function public.erp_r49_list_partner_unapplied_payments(uuid,text,text,text) from public,anon;
grant execute on function public.erp_r49_list_partner_unapplied_payments(uuid,text,text,text) to authenticated,service_role;
revoke execute on function public.erp_list_partner_unapplied_payments(uuid,text,text,text) from authenticated,anon,public;
grant execute on function public.erp_list_partner_unapplied_payments(uuid,text,text,text) to service_role;

create or replace function public.erp_r49_list_inventory_warehouse_transfers(p_company_id uuid)
returns setof jsonb language plpgsql stable security definer set search_path=public as $$
begin
  perform public.erp_active_company_context(p_company_id);
  if not public.is_company_admin(p_company_id) and not public.erp_cloud_user_has_permission(p_company_id,'inventory.view') then
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
  left join public.erp_warehouse_transfer_items i on i.company_id=t.company_id and coalesce(i.data->>'transferId',i.data->>'transfer_id')=t.id and not i.is_deleted
  left join public.erp_inventory p on p.company_id=t.company_id and p.id=coalesce(i.data->>'productId',i.data->>'product_id') and not p.is_deleted
  left join public.erp_warehouses wf on wf.company_id=t.company_id and wf.id=coalesce(t.data->>'fromWarehouseId',t.data->>'from_warehouse_id') and not wf.is_deleted
  left join public.erp_warehouses wt on wt.company_id=t.company_id and wt.id=coalesce(t.data->>'toWarehouseId',t.data->>'to_warehouse_id') and not wt.is_deleted
  where t.company_id=p_company_id and not t.is_deleted
  group by t.company_id,t.id,t.data,t.created_at,wf.data,wt.data
  order by coalesce(public.erp_try_timestamptz(t.data->>'transferDate',t.created_at),t.created_at) desc,t.created_at desc;
end $$;
revoke all on function public.erp_r49_list_inventory_warehouse_transfers(uuid) from public,anon;
grant execute on function public.erp_r49_list_inventory_warehouse_transfers(uuid) to authenticated,service_role;
revoke execute on function public.erp_list_inventory_warehouse_transfers(uuid) from authenticated,anon,public;
grant execute on function public.erp_list_inventory_warehouse_transfers(uuid) to service_role;


create or replace function public.erp_r49_get_commercial_order_allocation_context(
  p_company_id uuid,p_order_id uuid,p_module text
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_context jsonb; v_warehouses jsonb;
begin
  perform public.erp_active_company_context(p_company_id);
  if p_module='sales' then
    if not public.is_company_admin(p_company_id) and not public.erp_cloud_user_has_permission(p_company_id,'sales.view') then raise exception 'permission_denied:sales.view' using errcode='42501'; end if;
  elsif p_module='purchases' then
    if not public.is_company_admin(p_company_id) and not public.erp_cloud_user_has_permission(p_company_id,'purchases.view') then raise exception 'permission_denied:purchases.view' using errcode='42501'; end if;
  else raise exception 'invalid workflow module'; end if;
  v_context:=public.erp_get_commercial_order_allocation_context(p_company_id,p_order_id,p_module);
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',w.id,'name',coalesce(w.data->>'name',w.data->>'code',w.id),'code',w.data->>'code','address',w.data->>'address'
  ) order by coalesce(w.data->>'name',w.data->>'code',w.id)),'[]'::jsonb)
  into v_warehouses from public.erp_warehouses w
  where w.company_id=p_company_id and not w.is_deleted and public.erp_try_boolean(w.data->>'isActive',false);
  return jsonb_set(v_context,'{warehouses}',v_warehouses,true);
end $$;
revoke all on function public.erp_r49_get_commercial_order_allocation_context(uuid,uuid,text) from public,anon;
grant execute on function public.erp_r49_get_commercial_order_allocation_context(uuid,uuid,text) to authenticated,service_role;
revoke execute on function public.erp_get_commercial_order_allocation_context(uuid,uuid,text) from authenticated,anon,public;
grant execute on function public.erp_get_commercial_order_allocation_context(uuid,uuid,text) to service_role;

-- The current Maintenance UI uses the linked-cashbox batch payment contract.
-- Retire the older auto-cashbox single-payment endpoint from the browser so it
-- cannot bypass the linked payment/FX routing rules.
revoke execute on function public.erp_record_cloud_maintenance_payment(uuid,uuid,numeric,text,numeric,text) from authenticated,anon,public;
grant execute on function public.erp_record_cloud_maintenance_payment(uuid,uuid,numeric,text,numeric,text) to service_role;


-- R49 final car projection: only an explicitly completed/reversed transfer may
-- become the authoritative warehouse source. Missing status is not success, and
-- returned car data is filtered through the canonical cars.view/field boundary.
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
revoke execute on function public.erp_list_cloud_cars_with_warehouse(uuid) from authenticated,anon,public;
grant execute on function public.erp_list_cloud_cars_with_warehouse(uuid) to service_role;

notify pgrst,'reload schema';
commit;
