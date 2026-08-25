-- Quality Line ERP P16: authenticated access bootstrap for fresh devices.
begin;

alter table public.erp_records
  add column if not exists is_deleted boolean not null default false;

create or replace function public.erp_bootstrap_current_user_access()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_uid text := nullif(auth.jwt()->>'sub', '');
  v_email text := lower(coalesce(auth.jwt()->>'email', ''));
  v_company_slug text;
  v_local_user_id text;
  v_user jsonb;
  v_role jsonb;
  v_permissions jsonb := '[]'::jsonb;
  v_role_permissions jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'unauthenticated';
  end if;

  select c.slug, m.local_user_id
    into v_company_slug, v_local_user_id
  from public.company_memberships m
  join public.companies c on c.id = m.company_id
  where m.user_uid = v_uid
    and m.is_active = true
    and c.is_active = true
  order by m.is_system_admin desc, m.created_at
  limit 1;

  if v_company_slug is null then
    raise exception 'membership_not_found';
  end if;

  select r.payload
    into v_user
  from public.erp_records r
  where r.company_id = v_company_slug
    and r.entity_type = 'users'
    and r.deleted_at is null
    and (
      (v_local_user_id is not null and r.record_id = v_local_user_id)
      or r.payload->>'cloudAuthUid' = v_uid
      or (
        coalesce(r.payload->>'cloudAuthUid', '') = ''
        and lower(coalesce(r.payload->>'email', '')) = v_email
      )
    )
  order by
    case when r.record_id = v_local_user_id then 0
         when r.payload->>'cloudAuthUid' = v_uid then 1
         else 2 end,
    r.updated_at desc
  limit 1;

  if v_user is null or lower(coalesce(v_user->>'isActive', '0')) not in ('1', 'true') then
    raise exception 'erp_user_not_found_or_inactive';
  end if;

  select r.payload
    into v_role
  from public.erp_records r
  where r.company_id = v_company_slug
    and r.entity_type = 'roles'
    and r.record_id = v_user->>'roleId'
    and r.deleted_at is null
  limit 1;

  if v_role is null or lower(coalesce(v_role->>'isActive', '0')) not in ('1', 'true') then
    raise exception 'erp_role_not_found_or_inactive';
  end if;

  select coalesce(jsonb_agg(r.payload order by r.record_id), '[]'::jsonb)
    into v_role_permissions
  from public.erp_records r
  where r.company_id = v_company_slug
    and r.entity_type = 'role_permissions'
    and r.deleted_at is null
    and r.payload->>'roleId' = v_user->>'roleId';

  select coalesce(jsonb_agg(p.payload order by p.record_id), '[]'::jsonb)
    into v_permissions
  from public.erp_records p
  where p.company_id = v_company_slug
    and p.entity_type = 'permissions'
    and p.deleted_at is null
    and p.record_id in (
      select rp.value->>'permissionId'
      from jsonb_array_elements(v_role_permissions) rp(value)
    );

  return jsonb_build_object(
    'ok', true,
    'company_slug', v_company_slug,
    'user', v_user,
    'role', v_role,
    'permissions', v_permissions,
    'role_permissions', v_role_permissions
  );
end;
$$;

revoke all on function public.erp_bootstrap_current_user_access() from public, anon;
grant execute on function public.erp_bootstrap_current_user_access() to authenticated;

commit;
