begin;

-- Security closure for the repaired runtime surface. Browser clients use RPCs;
-- the processing queue is not a direct-write API.
revoke all on table public.erp_document_processing_jobs from public, anon, authenticated;
grant select on table public.erp_document_processing_jobs to service_role;

revoke all on function public.erp_r9_list_cloud_master_records(uuid,text) from public, anon;
grant execute on function public.erp_r9_list_cloud_master_records(uuid,text) to authenticated, service_role;

revoke all on function public.erp_r9_get_cloud_master_record(uuid,text,text) from public, anon;
grant execute on function public.erp_r9_get_cloud_master_record(uuid,text,text) to authenticated, service_role;

revoke all on function public.erp_r15_current_state_health(uuid) from public, anon;
grant execute on function public.erp_r15_current_state_health(uuid) to authenticated, service_role;

revoke all on function public.erp_r15_reconcile_company_state(uuid) from public, anon;
grant execute on function public.erp_r15_reconcile_company_state(uuid) to authenticated, service_role;

revoke all on function public.erp_r16_current_state_health(uuid) from public, anon;
grant execute on function public.erp_r16_current_state_health(uuid) to authenticated, service_role;

revoke all on function public.erp_r16_reconcile_company_state(uuid) from public, anon;
grant execute on function public.erp_r16_reconcile_company_state(uuid) to authenticated, service_role;

notify pgrst,'reload schema';
commit;
