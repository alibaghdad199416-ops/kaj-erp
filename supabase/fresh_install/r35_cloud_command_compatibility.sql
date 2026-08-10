-- FRESH-INSTALL COMPATIBILITY ONLY.
--
-- Historical R37 creates a SQL wrapper whose body resolves this signature
-- before the canonical R35 migration creates it. Applied historical migrations
-- are immutable, so the supported local fresh-install orchestrator loads this
-- exact prerequisite into an empty LOCAL database before replay begins.
--
-- This function is deliberately SECURITY INVOKER, has no browser grants, and
-- always fails closed. The later canonical R35 CREATE OR REPLACE must replace
-- it; final-state verification rejects any surviving placeholder.
create or replace function public.erp_r35_cloud_command(
  p_area text,
  p_action text,
  p_payload jsonb
) returns jsonb
language plpgsql
security invoker
set search_path=public
as $$
begin
  raise exception 'fresh_install_r35_compatibility_must_not_execute'
    using errcode='55000';
end;
$$;

revoke all on function public.erp_r35_cloud_command(text,text,jsonb)
  from public,anon,authenticated,service_role;
