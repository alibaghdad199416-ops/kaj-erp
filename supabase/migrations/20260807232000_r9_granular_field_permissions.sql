-- R9 complete closure: granular field permissions.
-- Keeps existing module permissions backward compatible while allowing roles
-- and user-specific overrides to store arbitrary field permission codes.

create or replace function public.erp_set_cloud_role_permissions(
  p_role_id text,
  p_permission_codes text[]
) returns void
language plpgsql security definer set search_path=public
as $$
declare
  v_slug text;
  v_admin boolean;
  v_code text;
  v_permission_id text;
  v_module text;
begin
  select company_slug,is_admin into v_slug,v_admin
  from public.erp_active_company_context();
  if v_slug is null then raise exception 'membership_not_found'; end if;
  if not v_admin then raise exception 'permission_denied'; end if;

  update public.erp_records
     set is_deleted=true,deleted_at=now(),updated_at=now()
   where company_id=v_slug
     and entity_type='role_permissions'
     and payload->>'roleId'=p_role_id
     and deleted_at is null;

  foreach v_code in array coalesce(p_permission_codes,array[]::text[]) loop
    v_code := trim(v_code);
    if v_code='' then continue; end if;

    v_permission_id := null;
    select record_id into v_permission_id
      from public.erp_records
     where company_id=v_slug
       and entity_type='permissions'
       and payload->>'code'=v_code
       and deleted_at is null
       and not is_deleted
     limit 1;

    if v_permission_id is null then
      v_permission_id := 'perm-'||substr(md5(v_code),1,24);
      v_module := split_part(v_code,'.',1);
      insert into public.erp_records(
        company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at
      ) values(
        v_slug,'permissions',v_permission_id,
        jsonb_build_object(
          'id',v_permission_id,
          'code',v_code,
          'name',v_code,
          'module',v_module,
          'description','صلاحية تشغيلية/حقلية مخصصة'
        ),false,null,now()
      )
      on conflict(company_id,entity_type,record_id) do update
        set payload=excluded.payload,
            is_deleted=false,
            deleted_at=null,
            updated_at=now();
    end if;

    insert into public.erp_records(
      company_id,entity_type,record_id,payload,is_deleted,deleted_at,updated_at
    ) values(
      v_slug,'role_permissions',p_role_id||'::'||v_permission_id,
      jsonb_build_object('roleId',p_role_id,'permissionId',v_permission_id),
      false,null,now()
    )
    on conflict(company_id,entity_type,record_id) do update
      set payload=excluded.payload,
          is_deleted=false,
          deleted_at=null,
          updated_at=now();
  end loop;
end;
$$;

revoke all on function public.erp_set_cloud_role_permissions(text,text[]) from public,anon;
grant execute on function public.erp_set_cloud_role_permissions(text,text[]) to authenticated;

-- SQL-side helpers for RPCs that need to enforce the same field policy. The
-- resource remains legacy-compatible until `<resource>.fields.restrict` is
-- present. In restricted mode unknown/ungranted fields are default-deny.
create or replace function public.erp_cloud_user_can_view_field(
  p_company_id uuid,
  p_resource text,
  p_field text,
  p_base_permission text default null
) returns boolean
language plpgsql stable security definer set search_path=public
as $$
declare
  v_restrict text := trim(p_resource)||'.fields.restrict';
  v_view text := trim(p_resource)||'.fields.'||trim(p_field)||'.view';
  v_edit text := trim(p_resource)||'.fields.'||trim(p_field)||'.edit';
begin
  if p_base_permission is not null
     and trim(p_base_permission)<>''
     and not public.erp_cloud_user_has_permission(p_company_id,trim(p_base_permission)) then
    return false;
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,v_restrict) then
    return true;
  end if;
  return public.erp_cloud_user_has_permission(p_company_id,v_view)
      or public.erp_cloud_user_has_permission(p_company_id,v_edit);
end;
$$;

create or replace function public.erp_cloud_user_can_edit_field(
  p_company_id uuid,
  p_resource text,
  p_field text,
  p_base_permission text default null
) returns boolean
language plpgsql stable security definer set search_path=public
as $$
declare
  v_restrict text := trim(p_resource)||'.fields.restrict';
  v_edit text := trim(p_resource)||'.fields.'||trim(p_field)||'.edit';
begin
  if p_base_permission is not null
     and trim(p_base_permission)<>''
     and not public.erp_cloud_user_has_permission(p_company_id,trim(p_base_permission)) then
    return false;
  end if;
  if not public.erp_cloud_user_has_permission(p_company_id,v_restrict) then
    return true;
  end if;
  return public.erp_cloud_user_has_permission(p_company_id,v_edit);
end;
$$;

revoke all on function public.erp_cloud_user_can_view_field(uuid,text,text,text) from public,anon;
revoke all on function public.erp_cloud_user_can_edit_field(uuid,text,text,text) from public,anon;
grant execute on function public.erp_cloud_user_can_view_field(uuid,text,text,text) to authenticated;
grant execute on function public.erp_cloud_user_can_edit_field(uuid,text,text,text) to authenticated;
