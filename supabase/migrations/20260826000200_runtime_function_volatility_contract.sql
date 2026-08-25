begin;

-- These routines read database state and/or call routines that can change state.
-- Marking them VOLATILE is the truthful PostgreSQL contract and prevents the
-- planner from reusing a result across statements where that would be unsafe.
do $$
declare
  v_name text;
  v_oid oid;
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
    'erp_r49_cloud_global_search',
    'erp_r49_get_sales_order_draft',
    'erp_r49_get_purchase_order_draft'
  ] loop
    for v_oid, v_args in
      select p.oid, pg_get_function_identity_arguments(p.oid)
      from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_name
    loop
      execute format('alter function public.%I(%s) volatile',v_name,v_args);
    end loop;
  end loop;
end $$;

-- The date/time parsing helpers may depend on session configuration, so they
-- must not promise IMMUTABLE semantics.
do $$
declare
  v_name text;
  v_oid oid;
  v_args text;
begin
  foreach v_name in array array['erp_try_date','erp_try_timestamptz'] loop
    for v_oid, v_args in
      select p.oid, pg_get_function_identity_arguments(p.oid)
      from pg_proc p
      join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname=v_name
    loop
      execute format('alter function public.%I(%s) stable',v_name,v_args);
    end loop;
  end loop;
end $$;

commit;
