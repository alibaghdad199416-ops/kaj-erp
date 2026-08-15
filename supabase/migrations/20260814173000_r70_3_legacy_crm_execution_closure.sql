-- Quality Line ERP R70.3 — legacy CRM execution closure.
begin;

-- R70 is now the sole browser-facing Opportunity authority. R49 and the old
-- R9 Phase-26 facade still contain historical mark_won compatibility branches;
-- keeping EXECUTE on either for `authenticated` would allow a crafted RPC to
-- bypass the R70 Sales-draft lifecycle even though current Flutter never calls
-- them directly.
revoke execute on function public.erp_r49_opportunity_command(text,jsonb)
  from public,anon,authenticated;
grant execute on function public.erp_r49_opportunity_command(text,jsonb)
  to service_role;

revoke execute on function public.erp_r9_phase26_cloud_command(text,text,jsonb)
  from public,anon,authenticated;
grant execute on function public.erp_r9_phase26_cloud_command(text,text,jsonb)
  to service_role;

-- The true Phase-26 implementation was already server-only; restate the
-- boundary so a fresh chain cannot regain browser execution through defaults.
revoke execute on function public.erp_phase26_cloud_command(text,text,jsonb)
  from public,anon,authenticated;
grant execute on function public.erp_phase26_cloud_command(text,text,jsonb)
  to service_role;

-- Browser CRM remains available only through the current stable facade/R70.
revoke all on function public.erp_r70_opportunity_command(text,jsonb)
  from public,anon;
grant execute on function public.erp_r70_opportunity_command(text,jsonb)
  to authenticated,service_role;
revoke all on function public.erp_r37_cloud_command(text,text,jsonb)
  from public,anon;
grant execute on function public.erp_r37_cloud_command(text,text,jsonb)
  to authenticated,service_role;

notify pgrst,'reload schema';
commit;
