-- Quality Line ERP v15.81.2
-- Hardens Firebase/Supabase tenant bootstrap and fixes UPSERT constraints.

begin;

-- The previous partial unique index could not be inferred by
-- ON CONFLICT (company_id, user_uid) without repeating its predicate.
drop index if exists public.company_memberships_company_firebase_uid;

create unique index if not exists company_memberships_company_user_uid_key
  on public.company_memberships(company_id, user_uid);

create unique index if not exists company_memberships_company_email_key
  on public.company_memberships(company_id, lower(user_email))
  where user_email is not null and btrim(user_email) <> '';

create unique index if not exists cloud_profiles_email_key
  on public.cloud_profiles(lower(email))
  where email is not null and btrim(email) <> '';

create table if not exists public.roles (
  code text primary key,
  name_ar text not null,
  name_en text not null,
  is_system boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.permissions (
  code text primary key,
  name_ar text not null,
  name_en text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.role_permissions (
  role_code text not null references public.roles(code) on delete cascade,
  permission_code text not null references public.permissions(code) on delete cascade,
  primary key(role_code, permission_code)
);

insert into public.roles(code, name_ar, name_en, is_system) values
  ('owner', 'مالك الشركة', 'Company Owner', true),
  ('admin', 'مدير النظام', 'System Administrator', true),
  ('user', 'مستخدم', 'User', true)
on conflict (code) do update set
  name_ar = excluded.name_ar,
  name_en = excluded.name_en,
  is_system = excluded.is_system;

insert into public.permissions(code, name_ar, name_en) values
  ('company.manage', 'إدارة الشركة', 'Manage company'),
  ('users.manage', 'إدارة المستخدمين', 'Manage users'),
  ('roles.manage', 'إدارة الأدوار', 'Manage roles'),
  ('cars.read', 'عرض السيارات', 'Read cars'),
  ('cars.create', 'إضافة السيارات', 'Create cars'),
  ('cars.update', 'تعديل السيارات', 'Update cars'),
  ('cars.transfer', 'نقل السيارات', 'Transfer cars'),
  ('sales.create', 'إنشاء المبيعات', 'Create sales'),
  ('sales.approve', 'اعتماد المبيعات', 'Approve sales'),
  ('cashbox.transfer', 'التحويل بين الصناديق', 'Transfer between cashboxes'),
  ('accounting.post', 'ترحيل القيود', 'Post accounting entries'),
  ('reports.export', 'تصدير التقارير', 'Export reports')
on conflict (code) do update set
  name_ar = excluded.name_ar,
  name_en = excluded.name_en;

insert into public.role_permissions(role_code, permission_code)
select 'owner', code from public.permissions
on conflict do nothing;

insert into public.role_permissions(role_code, permission_code)
select 'admin', code from public.permissions
on conflict do nothing;

create or replace function public.has_permission(
  p_company_id uuid,
  p_permission_code text
) returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.company_memberships m
    join public.role_permissions rp on rp.role_code = m.role_code
    where m.company_id = p_company_id
      and m.user_uid = public.current_external_uid()
      and m.is_active
      and rp.permission_code = p_permission_code
  ) or exists (
    select 1
    from public.company_memberships m
    where m.company_id = p_company_id
      and m.user_uid = public.current_external_uid()
      and m.is_active
      and m.is_system_admin
  );
$$;

-- Administrative bootstrap function. It is intentionally unavailable to
-- browser roles and is used only by trusted database migrations/setup tools.
create or replace function public.bootstrap_company_admin(
  p_company_id uuid,
  p_user_uid text,
  p_email text,
  p_full_name text,
  p_local_user_id text default null,
  p_role_code text default 'owner'
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_company public.companies%rowtype;
begin
  if p_user_uid is null or btrim(p_user_uid) = '' then
    raise exception 'Firebase UID is required';
  end if;
  if p_email is null or btrim(p_email) = '' then
    raise exception 'Email is required';
  end if;

  select * into v_company
  from public.companies
  where id = p_company_id and is_active;

  if not found then
    raise exception 'Active company % was not found', p_company_id;
  end if;

  insert into public.cloud_profiles(
    user_uid, email, full_name, is_active, updated_at
  ) values (
    btrim(p_user_uid), lower(btrim(p_email)), coalesce(nullif(btrim(p_full_name), ''), lower(btrim(p_email))), true, now()
  )
  on conflict (user_uid) do update set
    email = excluded.email,
    full_name = excluded.full_name,
    is_active = true,
    updated_at = now();

  insert into public.company_memberships(
    company_id, user_uid, user_email, local_user_id,
    role_code, is_system_admin, is_active, updated_at
  ) values (
    p_company_id, btrim(p_user_uid), lower(btrim(p_email)), nullif(btrim(coalesce(p_local_user_id, '')), ''),
    p_role_code, true, true, now()
  )
  on conflict (company_id, user_uid) do update set
    user_email = excluded.user_email,
    local_user_id = coalesce(excluded.local_user_id, public.company_memberships.local_user_id),
    role_code = excluded.role_code,
    is_system_admin = true,
    is_active = true,
    updated_at = now();

  return jsonb_build_object(
    'ok', true,
    'company_id', p_company_id,
    'company_slug', v_company.slug,
    'user_uid', btrim(p_user_uid),
    'email', lower(btrim(p_email)),
    'role_code', p_role_code
  );
end;
$$;

revoke all on function public.bootstrap_company_admin(uuid, text, text, text, text, text) from public;
revoke all on function public.bootstrap_company_admin(uuid, text, text, text, text, text) from anon;
revoke all on function public.bootstrap_company_admin(uuid, text, text, text, text, text) from authenticated;
grant execute on function public.bootstrap_company_admin(uuid, text, text, text, text, text) to postgres;

alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;

drop policy if exists roles_authenticated_select on public.roles;
create policy roles_authenticated_select on public.roles
for select to authenticated using (true);

drop policy if exists permissions_authenticated_select on public.permissions;
create policy permissions_authenticated_select on public.permissions
for select to authenticated using (true);

drop policy if exists role_permissions_authenticated_select on public.role_permissions;
create policy role_permissions_authenticated_select on public.role_permissions
for select to authenticated using (true);

grant select on public.roles, public.permissions, public.role_permissions to authenticated;

commit;

select jsonb_build_object(
  'ok', true,
  'migration', '20260723_003_cloud_bootstrap_hardening'
) as result;
