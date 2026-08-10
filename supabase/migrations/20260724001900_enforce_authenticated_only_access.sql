-- Defense in depth after retiring the anonymous/local authentication bridge.
begin;

-- Keep the removal idempotent even when environments applied only part of the
-- historical migration sequence before this production stabilization pass.
drop policy if exists erp_records_bootstrap_select on public.erp_records;
drop policy if exists erp_records_bootstrap_insert on public.erp_records;
drop policy if exists erp_records_bootstrap_update on public.erp_records;
drop policy if exists erp_records_bootstrap_delete on public.erp_records;

revoke all privileges on table public.erp_records from anon;
revoke all privileges on table public.companies from anon;
revoke all privileges on table public.company_memberships from anon;
revoke all privileges on table public.cloud_profiles from anon;

revoke all on function public.is_company_member(text) from public, anon;
revoke all on function public.is_company_admin(uuid) from public, anon;
grant execute on function public.is_company_member(text) to authenticated;
grant execute on function public.is_company_admin(uuid) to authenticated;

commit;
