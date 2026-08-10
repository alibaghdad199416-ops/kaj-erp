-- Quality Line ERP Enterprise 1.2 - Cloud Foundation
-- Paste this complete file into Supabase SQL Editor and press Run once.
-- It is safe to re-run: objects use IF NOT EXISTS or idempotent policies.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Multi-company and multi-branch foundation
-- ---------------------------------------------------------------------------
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

create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  code text not null,
  name_ar text not null,
  name_en text not null,
  phone text,
  address text,
  is_main boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(company_id, code)
);

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  avatar_path text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.company_memberships (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  default_branch_id uuid references public.branches(id) on delete set null,
  role_code text not null default 'user',
  is_system_admin boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(company_id, user_id)
);

create table if not exists public.currencies (
  code text primary key,
  name_ar text not null,
  name_en text not null,
  decimal_places smallint not null default 2,
  is_active boolean not null default true
);

insert into public.currencies(code, name_ar, name_en, decimal_places)
values
  ('IQD', 'الدينار العراقي', 'Iraqi Dinar', 0),
  ('USD', 'الدولار الأمريكي', 'US Dollar', 2)
on conflict (code) do update set
  name_ar = excluded.name_ar,
  name_en = excluded.name_en,
  decimal_places = excluded.decimal_places;

create table if not exists public.exchange_rates (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  rate_date date not null default current_date,
  base_currency_code text not null references public.currencies(code),
  quote_currency_code text not null references public.currencies(code),
  rate numeric(20,8) not null check(rate > 0),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique(company_id, rate_date, base_currency_code, quote_currency_code),
  check(base_currency_code <> quote_currency_code)
);

-- Seed the first company. The UUID remains stable across repeated runs.
insert into public.companies(id, slug, name_ar, name_en, default_currency_code)
values (
  '11111111-1111-4111-8111-111111111111',
  'quality-line',
  'خط الجودة',
  'Quality Line',
  'IQD'
)
on conflict (slug) do update set
  name_ar = excluded.name_ar,
  name_en = excluded.name_en,
  default_currency_code = excluded.default_currency_code;

insert into public.branches(
  id, company_id, code, name_ar, name_en, is_main
)
values (
  '22222222-2222-4222-8222-222222222222',
  '11111111-1111-4111-8111-111111111111',
  'MAIN',
  'الفرع الرئيسي',
  'Main Branch',
  true
)
on conflict (company_id, code) do update set
  name_ar = excluded.name_ar,
  name_en = excluded.name_en,
  is_main = excluded.is_main;

-- ---------------------------------------------------------------------------
-- Shared record synchronization (compatibility layer for existing Flutter DB)
-- ---------------------------------------------------------------------------
create table if not exists public.erp_records (
  company_id text not null,
  entity_type text not null,
  record_id text not null,
  branch_id text,
  payload jsonb not null default '{}'::jsonb,
  payload_hash text,
  created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (company_id, entity_type, record_id)
);

alter table public.erp_records add column if not exists branch_id text;
alter table public.erp_records add column if not exists created_by uuid references auth.users(id) on delete set null;

create index if not exists erp_records_company_entity_idx
  on public.erp_records(company_id, entity_type);
create index if not exists erp_records_company_branch_idx
  on public.erp_records(company_id, branch_id);
create index if not exists erp_records_updated_at_idx
  on public.erp_records(updated_at desc);

-- ---------------------------------------------------------------------------
-- Security helpers
-- ---------------------------------------------------------------------------
create or replace function public.is_company_member(company_slug text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.company_memberships membership
    join public.companies company on company.id = membership.company_id
    where membership.user_id = auth.uid()
      and membership.is_active
      and company.is_active
      and company.slug = company_slug
  );
$$;

create or replace function public.is_company_admin(company_uuid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.company_memberships membership
    where membership.user_id = auth.uid()
      and membership.company_id = company_uuid
      and membership.is_active
      and membership.is_system_admin
  );
$$;

-- ---------------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------------
alter table public.companies enable row level security;
alter table public.branches enable row level security;
alter table public.profiles enable row level security;
alter table public.company_memberships enable row level security;
alter table public.exchange_rates enable row level security;
alter table public.erp_records enable row level security;

drop policy if exists companies_member_select on public.companies;
create policy companies_member_select on public.companies
for select to authenticated
using (
  exists (
    select 1 from public.company_memberships membership
    where membership.company_id = companies.id
      and membership.user_id = auth.uid()
      and membership.is_active
  )
);

drop policy if exists branches_member_select on public.branches;
create policy branches_member_select on public.branches
for select to authenticated
using (
  exists (
    select 1 from public.company_memberships membership
    where membership.company_id = branches.company_id
      and membership.user_id = auth.uid()
      and membership.is_active
  )
);

drop policy if exists profiles_self_select on public.profiles;
create policy profiles_self_select on public.profiles
for select to authenticated using (id = auth.uid());

drop policy if exists profiles_self_update on public.profiles;
create policy profiles_self_update on public.profiles
for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists memberships_self_select on public.company_memberships;
create policy memberships_self_select on public.company_memberships
for select to authenticated using (user_id = auth.uid());

drop policy if exists exchange_rates_member_select on public.exchange_rates;
create policy exchange_rates_member_select on public.exchange_rates
for select to authenticated
using (
  exists (
    select 1 from public.company_memberships membership
    where membership.company_id = exchange_rates.company_id
      and membership.user_id = auth.uid()
      and membership.is_active
  )
);

drop policy if exists exchange_rates_admin_write on public.exchange_rates;
create policy exchange_rates_admin_write on public.exchange_rates
for all to authenticated
using (public.is_company_admin(company_id))
with check (public.is_company_admin(company_id));

-- Authenticated tenant isolation for application records.
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

-- Temporary bootstrap policies keep the current app operational before the
-- Auth screen is migrated. Remove these four policies after the first system
-- administrator is created and Supabase Auth is enabled in Flutter.
drop policy if exists erp_records_bootstrap_select on public.erp_records;
create policy erp_records_bootstrap_select on public.erp_records
for select to anon using (company_id = 'quality-line');

drop policy if exists erp_records_bootstrap_insert on public.erp_records;
create policy erp_records_bootstrap_insert on public.erp_records
for insert to anon with check (company_id = 'quality-line');

drop policy if exists erp_records_bootstrap_update on public.erp_records;
create policy erp_records_bootstrap_update on public.erp_records
for update to anon
using (company_id = 'quality-line')
with check (company_id = 'quality-line');

drop policy if exists erp_records_bootstrap_delete on public.erp_records;
create policy erp_records_bootstrap_delete on public.erp_records
for delete to anon using (company_id = 'quality-line');

-- ---------------------------------------------------------------------------
-- Storage buckets
-- Paths must follow: <company-slug>/<branch-id-or-shared>/<file-name>
-- ---------------------------------------------------------------------------
insert into storage.buckets(id, name, public)
values
  ('car-images', 'car-images', false),
  ('user-avatars', 'user-avatars', false),
  ('erp-documents', 'erp-documents', false)
on conflict (id) do update set public = false;

-- Realtime compatibility table.
do $$
begin
  alter publication supabase_realtime add table public.erp_records;
exception when duplicate_object then null;
end $$;

select jsonb_build_object(
  'ok', true,
  'migration', '20260718_001_enterprise_cloud_foundation',
  'company', 'Quality Line',
  'tenant_slug', 'quality-line'
) as result;
