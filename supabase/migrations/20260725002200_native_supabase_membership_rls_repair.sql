-- Quality Line ERP: native Supabase Auth membership and RLS repair.
--
-- Earlier migrations supported both Firebase-style `user_uid` identities and
-- native Supabase Auth `user_id` identities, but a few canonical authorization
-- helpers still checked only `user_id`. Current application login resolves the
-- tenant through `user_uid`, so those helpers denied valid native sessions.
-- This migration makes the identity columns compatible, repairs the helpers,
-- and keeps future admin-created memberships synchronized.

begin;

-- Keep the two identity columns synchronized for native Supabase Auth users.
-- External identities that do not exist in auth.users remain supported through
-- user_uid and are not forced into the user_id foreign key.
create or replace function public.erp_sync_company_membership_identity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
begin
  if new.user_uid is null or btrim(new.user_uid) = '' then
    if new.user_id is not null then
      new.user_uid := new.user_id::text;
    end if;
  elsif new.user_id is null
        and new.user_uid ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    v_uid := new.user_uid::uuid;
    if exists (select 1 from auth.users u where u.id = v_uid) then
      new.user_id := v_uid;
    end if;
  end if;

  if new.user_id is not null then
    new.user_uid := new.user_id::text;
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists erp_company_membership_identity_sync
  on public.company_memberships;
create trigger erp_company_membership_identity_sync
before insert or update of user_id, user_uid
on public.company_memberships
for each row execute function public.erp_sync_company_membership_identity();

-- Backfill native Supabase identities already created before this repair.
update public.company_memberships m
set user_id = m.user_uid::uuid,
    updated_at = now()
where m.user_id is null
  and m.user_uid ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  and exists (
    select 1 from auth.users u where u.id = m.user_uid::uuid
  )
  and not exists (
    select 1
    from public.company_memberships duplicate
    where duplicate.id <> m.id
      and duplicate.company_id = m.company_id
      and duplicate.user_id = m.user_uid::uuid
  );

update public.company_memberships
set user_uid = user_id::text,
    updated_at = now()
where user_id is not null
  and coalesce(btrim(user_uid), '') = '';

-- One canonical predicate for both native Supabase Auth and legacy external
-- identities. Security definer avoids RLS recursion on company_memberships.
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
  select auth.uid() is not null
     and (
       p_user_id = auth.uid()
       or nullif(btrim(p_user_uid), '') = auth.uid()::text
     );
$$;

create or replace function public.is_active_company_member(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.company_memberships m
    join public.companies c on c.id = m.company_id
    where m.company_id = p_company_id
      and public.erp_membership_matches_current_user(m.user_id, m.user_uid)
      and m.is_active
      and c.is_active
  );
$$;

create or replace function public.can_manage_master_data(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.company_memberships m
    join public.companies c on c.id = m.company_id
    where m.company_id = p_company_id
      and public.erp_membership_matches_current_user(m.user_id, m.user_uid)
      and m.is_active
      and c.is_active
      and (
        m.is_system_admin
        or m.role_code in (
          'owner', 'admin', 'manager', 'sales', 'warehouse', 'accountant'
        )
      )
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
    from public.company_memberships m
    join public.companies c on c.id = m.company_id
    where m.company_id = company_uuid
      and public.erp_membership_matches_current_user(m.user_id, m.user_uid)
      and m.is_active
      and c.is_active
      and (m.is_system_admin or m.role_code in ('owner', 'admin'))
  );
$$;

create or replace function public.has_permission(
  p_company_id uuid,
  p_permission_code text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.company_memberships m
    join public.companies c on c.id = m.company_id
    join public.role_permissions rp on rp.role_code = m.role_code
    where m.company_id = p_company_id
      and public.erp_membership_matches_current_user(m.user_id, m.user_uid)
      and m.is_active
      and c.is_active
      and rp.permission_code = p_permission_code
  ) or public.is_company_admin(p_company_id);
$$;

create or replace function public.current_organization_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select m.company_id
  from public.company_memberships m
  join public.companies c on c.id = m.company_id
  where public.erp_membership_matches_current_user(m.user_id, m.user_uid)
    and m.is_active
    and c.is_active
  order by m.is_system_admin desc,
           case when m.role_code = 'owner' then 0
                when m.role_code = 'admin' then 1
                else 2 end,
           m.created_at asc
  limit 1;
$$;

create or replace function public.has_role(p_role text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.company_memberships m
    join public.companies c on c.id = m.company_id
    where public.erp_membership_matches_current_user(m.user_id, m.user_uid)
      and m.company_id = public.current_organization_id()
      and m.is_active
      and c.is_active
      and (m.is_system_admin or m.role_code = p_role)
  );
$$;

create or replace function public.erp_active_company_context()
returns table(
  company_uuid uuid,
  company_slug text,
  role_code text,
  is_admin boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select c.id,
         c.slug,
         m.role_code,
         (m.is_system_admin or m.role_code in ('owner', 'admin'))
  from public.company_memberships m
  join public.companies c on c.id = m.company_id
  where public.erp_membership_matches_current_user(m.user_id, m.user_uid)
    and m.is_active
    and c.is_active
  order by m.is_system_admin desc,
           case when m.role_code = 'owner' then 0
                when m.role_code = 'admin' then 1
                else 2 end,
           m.created_at asc
  limit 1;
$$;

-- Rebind compatibility aliases to the repaired canonical predicate.
create or replace function public.erp_user_belongs_to_company(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_active_company_member(p_company_id);
$$;

create or replace function public.erp_is_company_member(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_active_company_member(p_company_id);
$$;

create or replace function public.erp_is_active_company_member(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_active_company_member(p_company_id);
$$;

create or replace function public.is_company_member(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_active_company_member(p_company_id);
$$;

create or replace function public.erp_active_company_context(p_company_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_company_id is null
     or not public.is_active_company_member(p_company_id) then
    raise exception 'membership_not_found' using errcode = '42501';
  end if;
  return p_company_id;
end;
$$;

-- Policies created before the identity model was finalized are replaced with
-- the repaired helpers. Existing master-data policies automatically pick up
-- the new function bodies, but these core policies contained inline checks.
drop policy if exists companies_member_select on public.companies;
create policy companies_member_select on public.companies
for select to authenticated
using (public.is_active_company_member(id));

drop policy if exists memberships_self_select on public.company_memberships;
create policy memberships_self_select on public.company_memberships
for select to authenticated
using (public.erp_membership_matches_current_user(user_id, user_uid));

-- Ensure normalized master-data policies are exactly aligned with the fixed
-- authorization predicates, including the tables shown in the production UI.
do $$
declare
  t text;
begin
  foreach t in array array['erp_cars', 'erp_customers', 'erp_suppliers'] loop
    execute format('drop policy if exists %I_select on public.%I', t, t);
    execute format('drop policy if exists %I_insert on public.%I', t, t);
    execute format('drop policy if exists %I_update on public.%I', t, t);
    execute format('drop policy if exists %I_delete on public.%I', t, t);
    execute format(
      'create policy %I_select on public.%I for select to authenticated using (public.is_active_company_member(company_id))',
      t, t
    );
    execute format(
      'create policy %I_insert on public.%I for insert to authenticated with check (public.can_manage_master_data(company_id) and created_by = auth.uid() and updated_by = auth.uid())',
      t, t
    );
    execute format(
      'create policy %I_update on public.%I for update to authenticated using (public.can_manage_master_data(company_id)) with check (public.can_manage_master_data(company_id) and updated_by = auth.uid())',
      t, t
    );
    execute format(
      'create policy %I_delete on public.%I for delete to authenticated using (public.can_manage_master_data(company_id))',
      t, t
    );
  end loop;
end $$;

revoke all on function public.erp_sync_company_membership_identity() from public, anon;
revoke all on function public.erp_membership_matches_current_user(uuid, text) from public, anon;
revoke all on function public.is_active_company_member(uuid) from public, anon;
revoke all on function public.can_manage_master_data(uuid) from public, anon;
revoke all on function public.is_company_admin(uuid) from public, anon;
revoke all on function public.has_permission(uuid, text) from public, anon;
revoke all on function public.current_organization_id() from public, anon;
revoke all on function public.has_role(text) from public, anon;
revoke all on function public.erp_active_company_context() from public, anon;
revoke all on function public.erp_active_company_context(uuid) from public, anon;
revoke all on function public.erp_user_belongs_to_company(uuid) from public, anon;
revoke all on function public.erp_is_company_member(uuid) from public, anon;
revoke all on function public.erp_is_active_company_member(uuid) from public, anon;
revoke all on function public.is_company_member(uuid) from public, anon;

grant execute on function public.erp_membership_matches_current_user(uuid, text)
  to authenticated, service_role;
grant execute on function public.is_active_company_member(uuid)
  to authenticated, service_role;
grant execute on function public.can_manage_master_data(uuid)
  to authenticated, service_role;
grant execute on function public.is_company_admin(uuid)
  to authenticated, service_role;
grant execute on function public.has_permission(uuid, text)
  to authenticated, service_role;
grant execute on function public.current_organization_id()
  to authenticated, service_role;
grant execute on function public.has_role(text)
  to authenticated, service_role;
grant execute on function public.erp_active_company_context()
  to authenticated, service_role;
grant execute on function public.erp_active_company_context(uuid)
  to authenticated, service_role;
grant execute on function public.erp_user_belongs_to_company(uuid)
  to authenticated, service_role;
grant execute on function public.erp_is_company_member(uuid)
  to authenticated, service_role;
grant execute on function public.erp_is_active_company_member(uuid)
  to authenticated, service_role;
grant execute on function public.is_company_member(uuid)
  to authenticated, service_role;

commit;
