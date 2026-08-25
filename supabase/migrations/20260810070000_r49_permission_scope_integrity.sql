begin;

-- R49 final permission-scope integrity closure.
-- Keep user-profile editing separate from permission-scope administration.
-- Delegated scope managers may inspect and manage another user inside the same
-- company; ordinary users may only inspect their own effective permissions.

create or replace function public.erp_get_cloud_user_permission_override(
  p_user_id text
) returns jsonb
language plpgsql stable security definer set search_path=public
as $$
declare
  v_company uuid;
  v_slug text;
  v_admin boolean;
  v_self_id text;
  v_can_manage boolean := false;
  v_has_override boolean := false;
  v_codes text[] := array[]::text[];
begin
  select company_uuid,company_slug,is_admin into v_company,v_slug,v_admin
  from public.erp_active_company_context();
  if v_slug is null or v_company is null then raise exception 'membership_not_found'; end if;

  select local_user_id into v_self_id
  from public.company_memberships
  where company_id=v_company and user_uid=auth.uid()::text and is_active
  limit 1;
  v_self_id := coalesce(v_self_id,auth.uid()::text);
  v_can_manage := v_admin or public.erp_cloud_user_has_permission(v_company,'permissions.scopes.manage');

  if p_user_id is distinct from v_self_id and not v_can_manage then
    raise exception 'permission_denied' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.erp_records
    where company_id=v_slug and entity_type='users' and record_id=p_user_id
      and deleted_at is null and not is_deleted
  ) then
    raise exception 'user_not_found';
  end if;

  select exists(
    select 1 from public.erp_records
    where company_id=v_slug
      and entity_type='user_permission_overrides'
      and record_id=p_user_id
      and deleted_at is null
      and not is_deleted
  ) into v_has_override;

  if v_has_override then
    select coalesce(array_agg(p.payload->>'code' order by p.payload->>'code'),array[]::text[])
      into v_codes
    from public.erp_records up
    join public.erp_records p
      on p.company_id=v_slug
     and p.entity_type='permissions'
     and p.record_id=up.payload->>'permissionId'
     and p.deleted_at is null
     and not p.is_deleted
    where up.company_id=v_slug
      and up.entity_type='user_permissions'
      and up.payload->>'userId'=p_user_id
      and up.deleted_at is null
      and not up.is_deleted;
  end if;

  return jsonb_build_object(
    'hasOverride',v_has_override,
    'codes',to_jsonb(coalesce(v_codes,array[]::text[]))
  );
end $$;

create or replace function public.erp_get_cloud_user_permissions(p_user_id text)
returns text[]
language plpgsql stable security definer set search_path=public
as $$
declare
  v_company uuid;
  v_slug text;
  v_admin boolean;
  v_self_id text;
  v_can_manage boolean := false;
  v_role_id text;
  v_result text[];
  v_override jsonb;
begin
  select company_uuid,company_slug,is_admin into v_company,v_slug,v_admin
  from public.erp_active_company_context();
  if v_slug is null or v_company is null then raise exception 'membership_not_found'; end if;

  select local_user_id into v_self_id
  from public.company_memberships
  where company_id=v_company and user_uid=auth.uid()::text and is_active
  limit 1;
  v_self_id := coalesce(v_self_id,auth.uid()::text);
  v_can_manage := v_admin or public.erp_cloud_user_has_permission(v_company,'permissions.scopes.manage');

  if p_user_id is distinct from v_self_id and not v_can_manage then
    raise exception 'permission_denied' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.erp_records
    where company_id=v_slug and entity_type='users' and record_id=p_user_id
      and deleted_at is null and not is_deleted
  ) then
    raise exception 'user_not_found';
  end if;

  v_override := public.erp_get_cloud_user_permission_override(p_user_id);
  if coalesce((v_override->>'hasOverride')::boolean,false) then
    return array(
      select jsonb_array_elements_text(coalesce(v_override->'codes','[]'::jsonb))
    );
  end if;

  select payload->>'roleId' into v_role_id
  from public.erp_records
  where company_id=v_slug
    and entity_type='users'
    and record_id=p_user_id
    and deleted_at is null
    and not is_deleted
  limit 1;

  select array_agg(p.payload->>'code' order by p.payload->>'code') into v_result
  from public.erp_records rp
  join public.erp_records p
    on p.company_id=v_slug
   and p.entity_type='permissions'
   and p.record_id=rp.payload->>'permissionId'
   and p.deleted_at is null
   and not p.is_deleted
  where rp.company_id=v_slug
    and rp.entity_type='role_permissions'
    and rp.payload->>'roleId'=v_role_id
    and rp.deleted_at is null
    and not rp.is_deleted;
  return coalesce(v_result,array[]::text[]);
end $$;

create or replace function public.erp_set_cloud_user_permissions(
  p_user_id text,
  p_permission_codes text[]
) returns void
language plpgsql security definer set search_path=public
as $$
declare
  v_company uuid;
  v_slug text;
  v_admin boolean;
  v_code text;
  v_permission_id text;
  v_module text;
begin
  select company_uuid,company_slug,is_admin into v_company,v_slug,v_admin
  from public.erp_active_company_context();
  if v_slug is null or v_company is null then raise exception 'membership_not_found'; end if;
  if not v_admin
     and not public.erp_cloud_user_has_permission(v_company,'permissions.scopes.manage') then
    raise exception 'permission_denied' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.erp_records
    where company_id=v_slug and entity_type='users' and record_id=p_user_id
      and deleted_at is null and not is_deleted
  ) then
    raise exception 'user_not_found';
  end if;

  insert into public.erp_records(company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at)
  values(v_slug,'user_permission_overrides',p_user_id,
    jsonb_build_object('userId',p_user_id,'enabled',true),false,null,now())
  on conflict(company_id,entity_type,record_id) do update
    set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();

  update public.erp_records set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=v_slug and entity_type='user_permissions'
    and payload->>'userId'=p_user_id and deleted_at is null;

  foreach v_code in array coalesce(p_permission_codes,array[]::text[]) loop
    v_code := trim(v_code);
    if v_code='' then continue; end if;
    select record_id into v_permission_id
    from public.erp_records
    where company_id=v_slug and entity_type='permissions'
      and payload->>'code'=v_code and deleted_at is null and not is_deleted
    limit 1;
    if v_permission_id is null then
      v_permission_id := 'perm-'||substr(md5(v_code),1,24);
      v_module := split_part(v_code,'.',1);
      insert into public.erp_records(company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at)
      values(v_slug,'permissions',v_permission_id,
        jsonb_build_object(
          'id',v_permission_id,'code',v_code,'name',v_code,
          'module',v_module,'description','صلاحية تشغيلية مخصصة'
        ),false,null,now())
      on conflict(company_id,entity_type,record_id) do update
        set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();
    end if;
    insert into public.erp_records(company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at)
    values(v_slug,'user_permissions',p_user_id||'::'||v_permission_id,
      jsonb_build_object('userId',p_user_id,'permissionId',v_permission_id),false,null,now())
    on conflict(company_id,entity_type,record_id) do update
      set payload=excluded.payload,is_deleted=false,deleted_at=null,updated_at=now();
  end loop;
end $$;

create or replace function public.erp_clear_cloud_user_permissions(p_user_id text)
returns void
language plpgsql security definer set search_path=public
as $$
declare v_company uuid; v_slug text; v_admin boolean;
begin
  select company_uuid,company_slug,is_admin into v_company,v_slug,v_admin
  from public.erp_active_company_context();
  if v_slug is null or v_company is null then raise exception 'membership_not_found'; end if;
  if not v_admin
     and not public.erp_cloud_user_has_permission(v_company,'permissions.scopes.manage') then
    raise exception 'permission_denied' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.erp_records
    where company_id=v_slug and entity_type='users' and record_id=p_user_id
      and deleted_at is null and not is_deleted
  ) then
    raise exception 'user_not_found';
  end if;

  update public.erp_records set is_deleted=true,deleted_at=now(),updated_at=now()
  where company_id=v_slug and entity_type in ('user_permission_overrides','user_permissions')
    and (record_id=p_user_id or payload->>'userId'=p_user_id) and deleted_at is null;
end $$;

revoke all on function public.erp_get_cloud_user_permission_override(text) from public,anon;
grant execute on function public.erp_get_cloud_user_permission_override(text) to authenticated,service_role;
revoke all on function public.erp_get_cloud_user_permissions(text) from public,anon;
grant execute on function public.erp_get_cloud_user_permissions(text) to authenticated,service_role;
revoke all on function public.erp_set_cloud_user_permissions(text,text[]) from public,anon;
grant execute on function public.erp_set_cloud_user_permissions(text,text[]) to authenticated,service_role;
revoke all on function public.erp_clear_cloud_user_permissions(text) from public,anon;
grant execute on function public.erp_clear_cloud_user_permissions(text) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
