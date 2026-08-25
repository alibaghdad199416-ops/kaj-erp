-- Quality Line ERP v15.84.0
-- Tenant-scoped login bootstrap for ERP users created inside the application.
-- Apply this migration in Supabase before testing a second browser/device.

create extension if not exists pgcrypto;

create or replace function public.authenticate_local_erp_user(
  p_company_id text,
  p_username text,
  p_password_hash text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user jsonb;
  v_role jsonb;
  v_permissions jsonb;
  v_role_permissions jsonb;
  v_role_id text;
begin
  if coalesce(trim(p_company_id), '') = ''
     or coalesce(trim(p_username), '') = ''
     or p_password_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok', false);
  end if;

  select r.payload into v_user
  from public.erp_records r
  where r.company_id = p_company_id
    and r.entity_type = 'users'
    and r.deleted_at is null
    and lower(r.payload->>'username') = lower(trim(p_username))
    and r.payload->>'passwordHash' = p_password_hash
    and coalesce((r.payload->>'isActive')::int, 0) = 1
  limit 1;

  if v_user is null then
    perform pg_sleep(0.35);
    return jsonb_build_object('ok', false);
  end if;

  v_role_id := v_user->>'roleId';
  select r.payload into v_role
  from public.erp_records r
  where r.company_id = p_company_id
    and r.entity_type = 'roles'
    and r.record_id = v_role_id
    and r.deleted_at is null
    and coalesce((r.payload->>'isActive')::int, 0) = 1
  limit 1;

  if v_role is null then
    return jsonb_build_object('ok', false);
  end if;

  select coalesce(jsonb_agg(r.payload), '[]'::jsonb) into v_role_permissions
  from public.erp_records r
  where r.company_id = p_company_id
    and r.entity_type = 'role_permissions'
    and r.deleted_at is null
    and r.payload->>'roleId' = v_role_id;

  select coalesce(jsonb_agg(r.payload), '[]'::jsonb) into v_permissions
  from public.erp_records r
  where r.company_id = p_company_id
    and r.entity_type = 'permissions'
    and r.deleted_at is null
    and exists (
      select 1
      from jsonb_array_elements(v_role_permissions) rp
      where rp->>'permissionId' = r.record_id
         or rp->>'permissionCode' = r.payload->>'code'
    );

  return jsonb_build_object(
    'ok', true,
    'user', v_user,
    'role', v_role,
    'permissions', v_permissions,
    'role_permissions', v_role_permissions
  );
end;
$$;

revoke all on function public.authenticate_local_erp_user(text,text,text) from public;
grant execute on function public.authenticate_local_erp_user(text,text,text) to anon, authenticated;
