-- Quality Line ERP v17 P1: native Supabase Auth and multi-device identity.
begin;

-- Native Supabase Auth and third-party JWTs both expose the user id in `sub`.
create or replace function public.current_external_uid()
returns text language sql stable as $$
  select nullif(auth.jwt()->>'sub', '');
$$;

-- The legacy username/password RPC exposed password hashes through a browser
-- callable path. New devices must authenticate through Supabase Auth instead.
revoke all on function public.authenticate_local_erp_user(text,text,text)
  from public, anon, authenticated;

-- Ensure old anonymous compatibility policies can never be restored by a
-- partial migration run.
drop policy if exists erp_records_bootstrap_select on public.erp_records;
drop policy if exists erp_records_bootstrap_insert on public.erp_records;
drop policy if exists erp_records_bootstrap_update on public.erp_records;
drop policy if exists erp_records_bootstrap_delete on public.erp_records;

create unique index if not exists company_memberships_company_local_user_key
  on public.company_memberships(company_id, local_user_id)
  where local_user_id is not null and btrim(local_user_id) <> '';

commit;
