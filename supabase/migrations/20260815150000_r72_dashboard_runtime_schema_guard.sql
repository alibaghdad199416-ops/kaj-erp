-- R72: fail-closed deployment guard for the authoritative Dashboard runtime.
-- This migration is intentionally non-destructive. A normal chronological push
-- must apply the R65 chain before reaching this guard. If migration history says
-- R65 was applied while the function is absent, abort instead of masking drift.
begin;

do $$
begin
  if to_regprocedure(
    'public.erp_r65_get_authoritative_dashboard_snapshot(uuid,date,date)'
  ) is null then
    raise exception
      'r72_dashboard_contract_missing: erp_r65_get_authoritative_dashboard_snapshot(uuid,date,date)';
  end if;
end;
$$;

alter function public.erp_r65_get_authoritative_dashboard_snapshot(uuid,date,date)
  volatile;

revoke all on function public.erp_r65_get_authoritative_dashboard_snapshot(uuid,date,date)
  from public,anon,authenticated;
grant execute on function public.erp_r65_get_authoritative_dashboard_snapshot(uuid,date,date)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
