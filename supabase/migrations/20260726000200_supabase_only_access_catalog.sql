-- Quality Line ERP: Supabase-only access catalog and fresh-device bootstrap.
-- Removes the last runtime dependency on access records historically copied
-- from a local database. PostgreSQL now creates and serves the access catalog.

begin;

insert into public.permissions(code, name_ar, name_en)
select code, code, code
from unnest(array[
  'accounting.view','approvals.decide','approvals.view','assets.view','audit.view',
  'cars.create','cars.delete','cars.update','cars.view','cashbox.view',
  'contracts.view','customer_service.create','customer_service.view',
  'customers.create','customers.delete','customers.update','customers.view',
  'dashboard.view','documents.view','expenses.view','hr.view',
  'installments.view','inventory.view','maintenance.view','opportunities.view',
  'periods.close','periods.reopen','periods.view','permissions.scopes.manage',
  'projects.view','purchases.create','purchases.delete','purchases.view',
  'reports.export','reports.view','reservations.view','sales.create',
  'sales.delete','sales.update','sales.view','settings.backup',
  'settings.restore','settings.view','suppliers.create','suppliers.delete',
  'suppliers.update','suppliers.view','users.create','users.delete',
  'users.update','users.view'
]::text[]) as catalog(code)
on conflict (code) do nothing;

insert into public.role_permissions(role_code, permission_code)
select role_code, permission.code
from (values ('owner'), ('admin')) as role(role_code)
cross join public.permissions permission
on conflict do nothing;

insert into public.role_permissions(role_code, permission_code)
select 'user', permission.code
from public.permissions permission
where permission.code like '%.view'
on conflict do nothing;

create or replace function public.erp_seed_access_catalog(p_company_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_slug text;
  v_permission record;
begin
  select c.slug into v_slug
  from public.companies c
  where c.id = p_company_id and c.is_active;

  if v_slug is null then
    raise exception 'company_not_found';
  end if;

  if auth.uid() is not null
     and not public.is_active_company_member(p_company_id) then
    raise exception 'membership_not_found' using errcode = '42501';
  end if;

  insert into public.erp_records(
    company_id, entity_type, record_id, payload, updated_at, deleted_at
  ) values
    (
      v_slug, 'roles', 'role-admin',
      jsonb_build_object(
        'id','role-admin','name','مدير النظام',
        'description','صلاحيات الإدارة الكاملة عبر Supabase',
        'isSystem',1,'isActive',1
      ), now(), null
    ),
    (
      v_slug, 'roles', 'role-user',
      jsonb_build_object(
        'id','role-user','name','مستخدم',
        'description','صلاحيات العرض الأساسية',
        'isSystem',1,'isActive',1
      ), now(), null
    )
  on conflict (company_id, entity_type, record_id) do update
  set deleted_at = null,
      updated_at = greatest(public.erp_records.updated_at, excluded.updated_at),
      payload = case
        when public.erp_records.deleted_at is not null then excluded.payload
        else public.erp_records.payload
      end;

  for v_permission in
    select p.code
    from public.permissions p
    order by p.code
  loop
    insert into public.erp_records(
      company_id, entity_type, record_id, payload, updated_at, deleted_at
    ) values (
      v_slug,
      'permissions',
      v_permission.code,
      jsonb_build_object(
        'id', v_permission.code,
        'code', v_permission.code,
        'name', v_permission.code,
        'module', split_part(v_permission.code,'.',1),
        'description', ''
      ),
      now(),
      null
    )
    on conflict (company_id, entity_type, record_id) do update
    set deleted_at = null,
        updated_at = greatest(public.erp_records.updated_at, excluded.updated_at),
        payload = excluded.payload;

    if exists (
      select 1 from public.role_permissions rp
      where rp.role_code in ('owner','admin')
        and rp.permission_code = v_permission.code
    ) then
      insert into public.erp_records(
        company_id, entity_type, record_id, payload, updated_at, deleted_at
      ) values (
        v_slug,
        'role_permissions',
        'role-admin::' || v_permission.code,
        jsonb_build_object(
          'roleId','role-admin','permissionId',v_permission.code
        ),
        now(),
        null
      )
      on conflict (company_id, entity_type, record_id) do update
      set payload = excluded.payload, deleted_at = null, updated_at = now();
    end if;

    if exists (
      select 1 from public.role_permissions rp
      where rp.role_code = 'user'
        and rp.permission_code = v_permission.code
    ) then
      insert into public.erp_records(
        company_id, entity_type, record_id, payload, updated_at, deleted_at
      ) values (
        v_slug,
        'role_permissions',
        'role-user::' || v_permission.code,
        jsonb_build_object(
          'roleId','role-user','permissionId',v_permission.code
        ),
        now(),
        null
      )
      on conflict (company_id, entity_type, record_id) do update
      set payload = excluded.payload, deleted_at = null, updated_at = now();
    end if;
  end loop;
end;
$$;

-- Seed all companies that already exist. Future logins call the same helper.
do $$
declare v_company record;
begin
  for v_company in select id from public.companies loop
    perform public.erp_seed_access_catalog(v_company.id);
  end loop;
end $$;

create or replace function public.erp_bootstrap_current_user_access()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_email text := lower(coalesce(auth.jwt()->>'email', ''));
  v_company_id uuid;
  v_company_slug text;
  v_local_user_id text;
  v_membership_role text;
  v_is_admin boolean := false;
  v_user jsonb;
  v_role jsonb;
  v_permissions jsonb := '[]'::jsonb;
  v_role_permissions jsonb := '[]'::jsonb;
  v_role_id text;
  v_now text := now()::text;
begin
  if v_uid is null then
    raise exception 'unauthenticated';
  end if;

  select c.id, c.slug, m.local_user_id, m.role_code,
         (m.is_system_admin or m.role_code in ('owner','admin'))
    into v_company_id, v_company_slug, v_local_user_id,
         v_membership_role, v_is_admin
  from public.company_memberships m
  join public.companies c on c.id = m.company_id
  where (m.user_id = v_uid or m.user_uid = v_uid::text)
    and m.is_active = true
    and c.is_active = true
  order by m.is_system_admin desc,
           case when m.role_code='owner' then 0 when m.role_code='admin' then 1 else 2 end,
           m.created_at
  limit 1;

  if v_company_id is null then
    raise exception 'membership_not_found';
  end if;

  perform public.erp_seed_access_catalog(v_company_id);

  v_local_user_id := coalesce(nullif(v_local_user_id,''), v_uid::text);
  v_role_id := case when v_is_admin then 'role-admin' else 'role-user' end;

  select r.payload into v_user
  from public.erp_records r
  where r.company_id = v_company_slug
    and r.entity_type = 'users'
    and r.deleted_at is null
    and (
      r.record_id = v_local_user_id
      or r.payload->>'cloudAuthUid' = v_uid::text
      or lower(coalesce(r.payload->>'email','')) = v_email
    )
  order by case when r.record_id=v_local_user_id then 0 else 1 end,
           r.updated_at desc
  limit 1;

  if v_user is null then
    v_user := jsonb_build_object(
      'id', v_local_user_id,
      'username', v_email,
      'fullName', coalesce(
        auth.jwt()->'user_metadata'->>'full_name',
        auth.jwt()->'user_metadata'->>'display_name',
        v_email
      ),
      'email', v_email,
      'phone', '',
      'roleId', v_role_id,
      'passwordHash', '',
      'cloudAuthUid', v_uid::text,
      'authProvider', 'supabase',
      'cloudEmailVerified', 1,
      'isActive', 1,
      'createdAt', v_now,
      'updatedAt', v_now
    );

    insert into public.erp_records(
      company_id, entity_type, record_id, payload, created_by, updated_at, deleted_at
    ) values (
      v_company_slug, 'users', v_local_user_id, v_user, v_uid, now(), null
    )
    on conflict (company_id, entity_type, record_id) do update
    set payload = excluded.payload, deleted_at = null, updated_at = now();

    update public.company_memberships
    set local_user_id = v_local_user_id, updated_at = now()
    where company_id = v_company_id
      and (user_id = v_uid or user_uid = v_uid::text);
  elsif lower(coalesce(v_user->>'isActive','1')) not in ('1','true') then
    raise exception 'erp_user_not_found_or_inactive';
  end if;

  v_role_id := coalesce(nullif(v_user->>'roleId',''), v_role_id);

  select r.payload into v_role
  from public.erp_records r
  where r.company_id = v_company_slug
    and r.entity_type = 'roles'
    and r.record_id = v_role_id
    and r.deleted_at is null
  limit 1;

  if v_role is null then
    v_role_id := case when v_is_admin then 'role-admin' else 'role-user' end;
    select r.payload into v_role
    from public.erp_records r
    where r.company_id = v_company_slug
      and r.entity_type = 'roles'
      and r.record_id = v_role_id
      and r.deleted_at is null
    limit 1;
    v_user := jsonb_set(v_user, '{roleId}', to_jsonb(v_role_id), true);
  end if;

  if v_role is null then
    raise exception 'erp_role_not_found_or_inactive';
  end if;

  select coalesce(jsonb_agg(r.payload order by r.record_id), '[]'::jsonb)
    into v_role_permissions
  from public.erp_records r
  where r.company_id = v_company_slug
    and r.entity_type = 'role_permissions'
    and r.deleted_at is null
    and r.payload->>'roleId' = v_role_id;

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
    'company_id', v_company_id,
    'membership_role', v_membership_role,
    'is_system_admin', v_is_admin,
    'user', v_user,
    'role', v_role,
    'permissions', v_permissions,
    'role_permissions', v_role_permissions
  );
end;
$$;

revoke all on function public.erp_seed_access_catalog(uuid) from public, anon;
grant execute on function public.erp_seed_access_catalog(uuid)
  to authenticated, service_role;
revoke all on function public.erp_bootstrap_current_user_access() from public, anon;
grant execute on function public.erp_bootstrap_current_user_access()
  to authenticated;

commit;
