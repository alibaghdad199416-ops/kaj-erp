begin;

-- These routines read mutable tenant state and/or call VOLATILE routines.
-- Their volatility contract must therefore be VOLATILE; claiming STABLE can
-- allow PostgreSQL to reuse a result beyond the intended statement semantics.
do $$
declare
  r record;
  v_names text[] := array[
    'erp_search_cloud_documents',
    'erp_r22_cash_health',
    'erp_v2300_get_commercial_order_complete_details',
    'erp_r9_cloud_reports_summary',
    'erp_r9_cloud_dashboard_snapshot',
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
    'erp_r49_get_sales_order_draft',
    'erp_r49_get_purchase_order_draft',
    'erp_get_cloud_current_document_blob',
    'erp_get_cloud_document',
    'erp_list_cloud_document_versions',
    'erp_list_cloud_document_permissions'
  ];
begin
  for r in
    select p.oid::regprocedure::text as signature
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname=any(v_names)
      and p.provolatile <> 'v'
  loop
    execute format('alter function %s volatile',r.signature);
  end loop;
end $$;

notify pgrst,'reload schema';
commit;
