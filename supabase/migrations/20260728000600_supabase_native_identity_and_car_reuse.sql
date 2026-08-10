-- Quality Line ERP: native Supabase identity only + reusable deleted car keys.
-- Firebase remains an optional static hosting target only; it is not an auth,
-- database, storage, or runtime dependency.

begin;

-- Preserve a visible audit trail for legacy memberships that cannot be mapped
-- to a native Supabase Auth user instead of silently treating them as active.
create table if not exists public.supabase_identity_migration_issues (
  membership_id uuid primary key,
  company_id uuid not null references public.companies(id) on delete cascade,
  legacy_user_uid text,
  user_email text,
  reason text not null,
  detected_at timestamptz not null default now(),
  resolved_at timestamptz
);

revoke all on table public.supabase_identity_migration_issues from public, anon, authenticated;
grant select, insert, update, delete on table public.supabase_identity_migration_issues to service_role;

-- Map legacy UUID-shaped identities to auth.users where possible.
update public.company_memberships m
set user_id = m.user_uid::uuid,
    updated_at = now()
where m.user_id is null
  and coalesce(m.user_uid, '') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and exists (select 1 from auth.users u where u.id = m.user_uid::uuid)
  and not exists (
    select 1 from public.company_memberships d
    where d.id <> m.id
      and d.company_id = m.company_id
      and d.user_id = m.user_uid::uuid
  );

-- Email is the second deterministic mapping path for previously external users.
update public.company_memberships m
set user_id = u.id,
    updated_at = now()
from auth.users u
where m.user_id is null
  and coalesce(btrim(m.user_email), '') <> ''
  and lower(btrim(m.user_email)) = lower(coalesce(u.email, ''))
  and not exists (
    select 1 from public.company_memberships d
    where d.id <> m.id
      and d.company_id = m.company_id
      and d.user_id = u.id
  );

insert into public.supabase_identity_migration_issues(
  membership_id, company_id, legacy_user_uid, user_email, reason, detected_at
)
select m.id, m.company_id, m.user_uid, m.user_email,
       'No matching Supabase Auth user; membership was deactivated', now()
from public.company_memberships m
where m.user_id is null and m.is_active
on conflict (membership_id) do update
set legacy_user_uid = excluded.legacy_user_uid,
    user_email = excluded.user_email,
    reason = excluded.reason,
    detected_at = excluded.detected_at,
    resolved_at = null;

update public.company_memberships
set is_active = false,
    updated_at = now()
where user_id is null and is_active;

-- Keep the legacy column only as a read-compatibility shadow while all runtime
-- authorization and writes use user_id. It can no longer identify another
-- provider or activate a membership without auth.users.
update public.company_memberships
set user_uid = user_id::text,
    updated_at = now()
where user_id is not null
  and user_uid is distinct from user_id::text;

alter table public.company_memberships
  drop constraint if exists company_memberships_active_native_user_check;
alter table public.company_memberships
  add constraint company_memberships_active_native_user_check
  check (not is_active or user_id is not null) not valid;
alter table public.company_memberships
  validate constraint company_memberships_active_native_user_check;

create unique index if not exists company_memberships_company_user_id_key
  on public.company_memberships(company_id, user_id)
  where user_id is not null;

drop index if exists public.company_memberships_company_firebase_uid;
drop index if exists public.company_memberships_company_user_uid_key;

create or replace function public.erp_sync_company_membership_identity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_active and new.user_id is null then
    raise exception 'supabase_user_id_required' using errcode = '23502';
  end if;
  if new.user_id is not null then
    new.user_uid := new.user_id::text;
  else
    new.user_uid := null;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists erp_company_membership_identity_sync on public.company_memberships;
create trigger erp_company_membership_identity_sync
before insert or update of user_id, user_uid, is_active
on public.company_memberships
for each row execute function public.erp_sync_company_membership_identity();

-- Preserve the historical function signature for old SQL callers, but ignore
-- the legacy text argument completely. Native auth.uid() is authoritative.
create or replace function public.erp_membership_matches_current_user(
  p_user_id uuid,
  p_user_uid text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and p_user_id = auth.uid();
$$;

create or replace function public.current_external_uid()
returns text
language sql
stable
as $$
  select auth.uid()::text;
$$;

-- Migrate the obsolete external profile table into the native Supabase profile.
with mapped as (
  select distinct on (u.id)
         u.id,
         coalesce(nullif(btrim(cp.full_name), ''), coalesce(u.email, '')) as full_name,
         cp.avatar_path,
         cp.is_active,
         cp.created_at,
         cp.updated_at
  from public.cloud_profiles cp
  join auth.users u
    on u.id = case
      when cp.user_uid ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then cp.user_uid::uuid
      else null
    end
    or lower(coalesce(u.email, '')) = lower(coalesce(cp.email, ''))
  order by u.id, cp.updated_at desc
)
insert into public.profiles(id, full_name, avatar_path, is_active, created_at, updated_at)
select id, full_name, avatar_path, is_active, created_at, updated_at
from mapped
on conflict (id) do update
set full_name = excluded.full_name,
    avatar_path = coalesce(excluded.avatar_path, public.profiles.avatar_path),
    is_active = excluded.is_active,
    updated_at = greatest(public.profiles.updated_at, excluded.updated_at);

-- Retire the Firebase-era bootstrap contract and replace it with a native UUID contract.
drop function if exists public.bootstrap_company_admin(uuid, text, text, text, text, text);

create or replace function public.bootstrap_company_admin(
  p_company_id uuid,
  p_user_id uuid,
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
  if p_user_id is null or not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'Supabase Auth user is required';
  end if;

  select * into v_company
  from public.companies
  where id = p_company_id and is_active;
  if not found then
    raise exception 'Active company % was not found', p_company_id;
  end if;

  insert into public.profiles(id, full_name, is_active, updated_at)
  values (
    p_user_id,
    coalesce(nullif(btrim(p_full_name), ''), lower(btrim(p_email))),
    true,
    now()
  )
  on conflict (id) do update
  set full_name = excluded.full_name,
      is_active = true,
      updated_at = now();

  insert into public.company_memberships(
    company_id, user_id, user_uid, user_email, local_user_id,
    role_code, is_system_admin, is_active, updated_at
  ) values (
    p_company_id, p_user_id, p_user_id::text, lower(btrim(p_email)),
    nullif(btrim(coalesce(p_local_user_id, '')), ''),
    p_role_code, true, true, now()
  )
  on conflict (company_id, user_id) do update
  set user_uid = excluded.user_uid,
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
    'user_id', p_user_id,
    'email', lower(btrim(p_email)),
    'role_code', p_role_code
  );
end;
$$;

revoke all on function public.bootstrap_company_admin(uuid, uuid, text, text, text, text)
  from public, anon, authenticated;
grant execute on function public.bootstrap_company_admin(uuid, uuid, text, text, text, text)
  to postgres, service_role;

-- cloud_profiles and its self policies are no longer used by application code.
drop table if exists public.cloud_profiles;

-- A logically deleted vehicle must not reserve its chassis or plate forever.
drop index if exists public.erp_cars_company_chassis_key;
drop index if exists public.erp_cars_company_plate_key;

create unique index erp_cars_company_chassis_key
  on public.erp_cars(company_id, lower(btrim(data->>'chassis')))
  where not is_deleted
    and coalesce(btrim(data->>'chassis'), '') <> '';

create unique index erp_cars_company_plate_key
  on public.erp_cars(company_id, lower(btrim(data->>'plate_number')))
  where not is_deleted
    and coalesce(btrim(data->>'plate_number'), '') <> '';

-- Product master edits and image replacement are committed as one Supabase
-- transaction so sales/purchase pickers never observe partially updated data.
create or replace function public.erp_update_inventory_product(
  p_company_id uuid,
  p_product_id text,
  p_product jsonb,
  p_images jsonb default '[]'::jsonb
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_image text;
  v_index integer := 0;
begin
  if not public.can_manage_master_data(p_company_id) then
    raise exception 'permission_denied' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.erp_inventory
    where company_id = p_company_id and id = p_product_id and not is_deleted
    for update
  ) then
    raise exception 'product_not_found';
  end if;
  if exists (
    select 1 from public.erp_inventory
    where company_id = p_company_id
      and id <> p_product_id
      and not is_deleted
      and lower(btrim(data->>'code')) = lower(btrim(p_product->>'code'))
  ) then
    raise exception 'product_code_already_exists' using errcode = '23505';
  end if;

  update public.erp_inventory
  set data = p_product || jsonb_build_object(
        'id', p_product_id,
        'updatedAt', now(),
        'updated_at', now()
      ),
      is_deleted = false,
      deleted_at = null,
      updated_at = now()
  where company_id = p_company_id and id = p_product_id and not is_deleted;

  update public.erp_product_images
  set is_deleted = true, deleted_at = now(), updated_at = now()
  where company_id = p_company_id
    and data->>'productId' = p_product_id
    and not is_deleted;

  if jsonb_typeof(p_images) = 'array' then
    for v_image in select jsonb_array_elements_text(p_images) loop
      insert into public.erp_product_images(company_id,id,data,created_by,updated_by)
      values (
        p_company_id,
        gen_random_uuid()::text,
        jsonb_build_object(
          'productId', p_product_id,
          'imageBase64', v_image,
          'sortOrder', v_index,
          'createdAt', now(),
          'updatedAt', now()
        ),
        auth.uid(),
        auth.uid()
      );
      v_index := v_index + 1;
    end loop;
  end if;
end;
$$;

revoke all on function public.erp_update_inventory_product(uuid,text,jsonb,jsonb)
  from public, anon;
grant execute on function public.erp_update_inventory_product(uuid,text,jsonb,jsonb)
  to authenticated, service_role;

comment on column public.company_memberships.user_uid is
  'Deprecated compatibility shadow of Supabase Auth user_id; never authoritative.';

commit;
