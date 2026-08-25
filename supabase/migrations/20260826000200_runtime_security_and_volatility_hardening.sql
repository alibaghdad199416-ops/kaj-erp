begin;

-- The repaired state-health functions call routines that read mutable tables and
-- therefore must not advertise STABLE semantics to the planner.
alter function public.erp_r15_current_state_health(uuid) volatile;
alter function public.erp_r16_current_state_health(uuid) volatile;

-- R9 readers and the R49 search facade are read-only from the caller's point of
-- view, but they are SECURITY DEFINER entry points. Keep execution explicit.
revoke all on function public.erp_r9_list_cloud_master_records(uuid,text) from public, anon;
grant execute on function public.erp_r9_list_cloud_master_records(uuid,text) to authenticated, service_role;

revoke all on function public.erp_r9_get_cloud_master_record(uuid,text,text) from public, anon;
grant execute on function public.erp_r9_get_cloud_master_record(uuid,text,text) to authenticated, service_role;

revoke all on function public.erp_r49_cloud_global_search(uuid,text,integer) from public, anon;
grant execute on function public.erp_r49_cloud_global_search(uuid,text,integer) to authenticated, service_role;

revoke all on function public.erp_r15_current_state_health(uuid) from public, anon;
grant execute on function public.erp_r15_current_state_health(uuid) to authenticated, service_role;

revoke all on function public.erp_r15_reconcile_company_state(uuid) from public, anon;
grant execute on function public.erp_r15_reconcile_company_state(uuid) to authenticated, service_role;

revoke all on function public.erp_r16_current_state_health(uuid) from public, anon;
grant execute on function public.erp_r16_current_state_health(uuid) to authenticated, service_role;

revoke all on function public.erp_r16_reconcile_company_state(uuid) from public, anon;
grant execute on function public.erp_r16_reconcile_company_state(uuid) to authenticated, service_role;

revoke all on function public.erp_phase2_post_scrap(uuid,text,text,text,jsonb,text) from public, anon;
grant execute on function public.erp_phase2_post_scrap(uuid,text,text,text,jsonb,text) to authenticated, service_role;

-- Document-processing jobs are tenant rows. Keep RLS enabled and make the
-- policy explicit even when this migration is applied to an older database.
alter table public.erp_document_processing_jobs enable row level security;
drop policy if exists tenant_access on public.erp_document_processing_jobs;
create policy tenant_access on public.erp_document_processing_jobs
  for all
  using (public.erp_user_belongs_to_company(company_id))
  with check (public.erp_user_belongs_to_company(company_id));

notify pgrst, 'reload schema';
commit;
