-- Quality Line ERP v15.81.1
-- Firebase Auth -> Supabase Third-Party Auth tenant foundation.
-- Run after enabling Firebase Third-Party Auth in Supabase.

create extension if not exists pgcrypto;

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name_ar text not null,
  name_en text not null,
  default_currency_code text not null default 'IQD',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.company_memberships (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_uid text,
  user_email text,
  local_user_id text,
  default_branch_id uuid,
  role_code text not null default 'user',
  is_system_admin boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.company_memberships add column if not exists user_uid text;
alter table public.company_memberships add column if not exists user_email text;
alter table public.company_memberships add column if not exists local_user_id text;
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'company_memberships'
      and column_name = 'user_id'
  ) then
    alter table public.company_memberships alter column user_id drop not null;
  end if;
end $$;

create unique index if not exists company_memberships_company_firebase_uid
  on public.company_memberships(company_id, user_uid)
  where user_uid is not null and user_uid <> '';

create table if not exists public.cloud_profiles (
  user_uid text primary key,
  email text,
  full_name text not null default '',
  avatar_path text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.current_external_uid()
returns text language sql stable as $$
  select nullif(auth.jwt()->>'sub', '');
$$;

create or replace function public.current_external_email()
returns text language sql stable as $$
  select coalesce(auth.jwt()->>'email', '');
$$;

create or replace function public.is_company_member(company_slug text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.company_memberships m
    join public.companies c on c.id = m.company_id
    where m.user_uid = public.current_external_uid()
      and m.is_active and c.is_active and c.slug = company_slug
  );
$$;

create or replace function public.is_company_admin(company_uuid uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.company_memberships m
    where m.user_uid = public.current_external_uid()
      and m.company_id = company_uuid
      and m.is_active and m.is_system_admin
  );
$$;

alter table public.companies enable row level security;
alter table public.company_memberships enable row level security;
alter table public.cloud_profiles enable row level security;
alter table public.erp_records enable row level security;

drop policy if exists companies_member_select on public.companies;
create policy companies_member_select on public.companies
for select to authenticated using (
  exists (select 1 from public.company_memberships m
          where m.company_id = companies.id
            and m.user_uid = public.current_external_uid()
            and m.is_active)
);

drop policy if exists memberships_self_select on public.company_memberships;
create policy memberships_self_select on public.company_memberships
for select to authenticated using (user_uid = public.current_external_uid());

drop policy if exists cloud_profiles_self_select on public.cloud_profiles;
create policy cloud_profiles_self_select on public.cloud_profiles
for select to authenticated using (user_uid = public.current_external_uid());

drop policy if exists cloud_profiles_self_update on public.cloud_profiles;
create policy cloud_profiles_self_update on public.cloud_profiles
for update to authenticated
using (user_uid = public.current_external_uid())
with check (user_uid = public.current_external_uid());

-- Remove unsafe anonymous bootstrap access now that Firebase signs requests.
drop policy if exists erp_records_bootstrap_select on public.erp_records;
drop policy if exists erp_records_bootstrap_insert on public.erp_records;
drop policy if exists erp_records_bootstrap_update on public.erp_records;
drop policy if exists erp_records_bootstrap_delete on public.erp_records;

drop policy if exists erp_records_member_select on public.erp_records;
create policy erp_records_member_select on public.erp_records
for select to authenticated using (public.is_company_member(company_id));

drop policy if exists erp_records_member_insert on public.erp_records;
create policy erp_records_member_insert on public.erp_records
for insert to authenticated with check (public.is_company_member(company_id));

drop policy if exists erp_records_member_update on public.erp_records;
create policy erp_records_member_update on public.erp_records
for update to authenticated
using (public.is_company_member(company_id))
with check (public.is_company_member(company_id));

drop policy if exists erp_records_member_delete on public.erp_records;
create policy erp_records_member_delete on public.erp_records
for delete to authenticated using (public.is_company_member(company_id));

grant select on public.companies, public.company_memberships, public.cloud_profiles to authenticated;
grant update on public.cloud_profiles to authenticated;
grant select, insert, update, delete on public.erp_records to authenticated;

insert into public.companies(id, slug, name_ar, name_en, default_currency_code)
values ('11111111-1111-4111-8111-111111111111', 'quality-line', 'خط الجودة', 'Quality Line', 'IQD')
on conflict (slug) do update set name_ar = excluded.name_ar, name_en = excluded.name_en;

-- IMPORTANT: after creating the first Firebase user, replace the placeholders
-- below and execute the INSERT manually once.
-- insert into public.company_memberships(
--   company_id, user_uid, user_email, local_user_id, role_code,
--   is_system_admin, is_active
-- ) values (
--   '11111111-1111-4111-8111-111111111111',
--   '<FIREBASE_UID>', '<EMAIL>', '<LOCAL_ERP_USER_ID>',
--   'admin', true, true
-- ) on conflict (company_id, user_uid) do update set
--   user_email = excluded.user_email,
--   local_user_id = excluded.local_user_id,
--   role_code = excluded.role_code,
--   is_system_admin = excluded.is_system_admin,
--   is_active = true;

select jsonb_build_object(
  'ok', true,
  'migration', '20260723_002_firebase_third_party_tenant_auth'
) as result;
