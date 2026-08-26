begin;

-- Truthful PostgreSQL volatility contracts for routines that read changing
-- database state or call routines with volatile behavior.
do $$
declare
  v_name text;
  v_args text;
begin
  foreach v_name in array array[
    'erp_search_cloud_documents',
    'erp_r22_cash_health',
    'erp_v2300_get_commercial_order_complete_details',
    'erp_r9_cloud_reports_summary',
    'erp_r9_cloud_cash_currency_summary',
    'erp_r9_cloud_trial_balance',
    'erp_r9_cloud_account_balance_before',
    'erp_r9_cloud_detailed_accounting_report',
    'erp_r9_cloud_cash_flow_hierarchy',
    'erp_r9_cloud_contextual_report',
    'erp_r9_cloud_model_report',
    'erp_r9_cloud_customer_service_report',
    'erp_r9_cloud_report_audit',
    'erp_r15_current_state_health',
    'erp_r16_current_state_health',
    'erp_r49_get_sales_order_draft',
    'erp_r49_get_purchase_order_draft',
    'erp_r9_cloud_dashboard_snapshot',
    'erp_get_cloud_current_document_blob',
    'erp_get_cloud_document',
    'erp_list_cloud_document_versions',
    'erp_list_cloud_document_permissions',
    'erp_r49_cloud_global_search'
  ] loop
    for v_args in
      select pg_get_function_identity_arguments(p.oid)
      from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_name
    loop
      execute format('alter function public.%I(%s) volatile',v_name,v_args);
    end loop;
  end loop;
end $$;

-- Date/time parsing may depend on session configuration; STABLE is the safe
-- contract and avoids the incorrect IMMUTABLE promise reported by db lint.
do $$
declare
  v_name text;
  v_args text;
begin
  foreach v_name in array array['erp_try_date','erp_try_timestamptz'] loop
    for v_args in
      select pg_get_function_identity_arguments(p.oid)
      from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_name
    loop
      execute format('alter function public.%I(%s) stable',v_name,v_args);
    end loop;
  end loop;
end $$;

-- Repaired SECURITY DEFINER entry points must not be callable anonymously.
do $$
begin
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
end $$;

-- Document-processing jobs remain tenant-scoped. This preserves the existing
-- contract-master storage model while making the RLS policy explicit.
alter table public.erp_document_processing_jobs enable row level security;
drop policy if exists tenant_access on public.erp_document_processing_jobs;
create policy tenant_access on public.erp_document_processing_jobs
  for all
  using (public.erp_user_belongs_to_company(company_id))
  with check (public.erp_user_belongs_to_company(company_id));

notify pgrst,'reload schema';
commit;
