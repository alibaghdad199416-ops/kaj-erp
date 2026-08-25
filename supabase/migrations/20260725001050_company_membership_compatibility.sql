-- Compatibility aliases for tenant membership checks used by later migrations.
-- The canonical implementation is public.is_active_company_member(uuid).

begin;

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

-- Keep the existing text overload intact and add the UUID overload required
-- by dashboard/report migrations.
create or replace function public.is_company_member(p_company_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_active_company_member(p_company_id);
$$;

revoke all on function public.erp_user_belongs_to_company(uuid) from public;
revoke all on function public.erp_is_company_member(uuid) from public;
revoke all on function public.is_company_member(uuid) from public;

grant execute on function public.erp_user_belongs_to_company(uuid) to authenticated, service_role;
grant execute on function public.erp_is_company_member(uuid) to authenticated, service_role;
grant execute on function public.is_company_member(uuid) to authenticated, service_role;

commit;
