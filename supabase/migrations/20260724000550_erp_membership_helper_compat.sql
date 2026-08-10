-- Compatibility helper required by payment, reversal, and reconciliation migrations.
-- Keep this migration ordered after is_active_company_member() (00200) and
-- before the first erp_is_active_member() consumer (00600).

create or replace function public.erp_is_active_member(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_active_company_member(p_organization_id);
$$;

revoke all on function public.erp_is_active_member(uuid) from public, anon;
grant execute on function public.erp_is_active_member(uuid) to authenticated, service_role;
