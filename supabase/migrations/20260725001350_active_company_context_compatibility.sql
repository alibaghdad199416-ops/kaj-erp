-- Compatibility overload for tenant-scoped cloud modules.
-- The zero-argument public.erp_active_company_context() remains unchanged.
-- Later HR, projects, assets, and maintenance migrations call the UUID
-- overload as both an authorization assertion and an RLS predicate.

begin;

create or replace function public.erp_active_company_context(p_company_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if p_company_id is null then
    raise exception 'membership_not_found'
      using errcode = '42501';
  end if;

  if not public.erp_user_belongs_to_company(p_company_id) then
    raise exception 'membership_not_found'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.companies c
    where c.id = p_company_id
      and c.is_active
  ) then
    raise exception 'company_inactive'
      using errcode = '42501';
  end if;

  return p_company_id;
end;
$$;

-- Governance migration 01800 uses this legacy boolean alias.
create or replace function public.erp_is_active_company_member(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.erp_user_belongs_to_company(p_company_id);
$$;

revoke all on function public.erp_active_company_context(uuid) from public, anon;
revoke all on function public.erp_is_active_company_member(uuid) from public, anon;

grant execute on function public.erp_active_company_context(uuid)
  to authenticated, service_role;
grant execute on function public.erp_is_active_company_member(uuid)
  to authenticated, service_role;

commit;
