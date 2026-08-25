-- Quality Line ERP 17.20.4
-- Remove PL/pgSQL functions that belonged exclusively to modules retired by
-- 20260728001200_accepted_module_cleanup.sql. PostgreSQL does not record table
-- dependencies found only inside PL/pgSQL function bodies, so DROP TABLE ...
-- CASCADE cannot remove every such function. Leaving them behind causes
-- supabase db lint to fail with 42P01 after the retired tables are removed.

begin;

-- Business intelligence and generic workflow/document processing.
drop function if exists public.erp_acknowledge_cloud_bi_alert(uuid, text) cascade;
drop function if exists public.erp_submit_cloud_generic_approval(uuid, uuid, text, text) cascade;
drop function if exists public.erp_decide_cloud_generic_approval(uuid, uuid, boolean, text, text) cascade;
drop function if exists public.erp_enqueue_cloud_document_processing(uuid, uuid, text, text, text, text) cascade;
drop function if exists public.erp_complete_cloud_document_extraction(uuid, uuid, text, jsonb) cascade;
drop function if exists public.erp_fail_cloud_document_processing(uuid, uuid, text) cascade;

-- Retired security/governance operations.
drop function if exists public.erp_revoke_cloud_user_sessions(uuid, text, text) cascade;
drop function if exists public.erp_seed_cloud_security_baseline(uuid) cascade;
drop function if exists public.erp_request_cloud_governance_approval(uuid, text, text, text, numeric, text, text) cascade;
drop function if exists public.erp_review_cloud_governance_approval(uuid, uuid, boolean, text, text) cascade;

-- Retired contract and warranty modules.
drop function if exists public.erp_create_cloud_contract_warranty(uuid, jsonb) cascade;
drop function if exists public.erp_submit_cloud_warranty_claim(uuid, jsonb) cascade;
drop function if exists public.erp_create_cloud_contract_installment_plan(uuid, jsonb) cascade;
drop function if exists public.erp_record_cloud_contract_payment(uuid, jsonb) cascade;
drop function if exists public.erp_submit_cloud_contract_approval(uuid, uuid, text) cascade;
drop function if exists public.erp_reschedule_cloud_contract_plan(uuid, uuid, jsonb, text, text) cascade;
drop function if exists public.erp_contract_event(uuid, uuid, text, text, text, text, text) cascade;
drop function if exists public.erp_transition_cloud_contract(uuid, uuid, text, text, text) cascade;
drop function if exists public.erp_request_cloud_contract_review(uuid, uuid, text, text, text) cascade;
drop function if exists public.erp_complete_cloud_contract_review(uuid, uuid, boolean, text, text) cascade;
drop function if exists public.erp_decide_cloud_contract_approval(uuid, uuid, boolean, text, text) cascade;
drop function if exists public.erp_request_cloud_contract_signature(uuid, uuid, text, text, text, text, text) cascade;
drop function if exists public.erp_complete_cloud_contract_signature(uuid, uuid, text, text) cascade;
drop function if exists public.erp_reject_cloud_contract_signature(uuid, uuid, text, text) cascade;
drop function if exists public.erp_renew_cloud_contract(uuid, uuid, timestamptz, timestamptz, numeric, text, text) cascade;
drop function if exists public.erp_run_cloud_contract_lifecycle(uuid, timestamptz) cascade;
drop function if exists public.erp_create_cloud_contract_master(uuid, jsonb, jsonb) cascade;
drop function if exists public.erp_add_cloud_contract_version(uuid, uuid, jsonb, text, text, boolean) cascade;
drop function if exists public.erp_add_cloud_contract_clause(uuid, uuid, int, jsonb) cascade;
drop function if exists public.erp_link_cloud_contract_entity(uuid, uuid, jsonb) cascade;

-- Retired human resources and payroll module.
drop function if exists public.erp_cloud_hr_dashboard_summary(uuid, date) cascade;
drop function if exists public.erp_create_cloud_hr_employee(uuid, text, text, text, text, numeric, date) cascade;
drop function if exists public.erp_generate_cloud_payroll(uuid, date, date) cascade;
drop function if exists public.erp_save_cloud_hr_attendance(uuid, uuid, date, text, timestamptz, timestamptz, text) cascade;
drop function if exists public.erp_create_cloud_hr_leave_request(uuid, uuid, text, date, date, text) cascade;
drop function if exists public.erp_decide_cloud_hr_leave_request(uuid, uuid, boolean) cascade;

-- Retired projects and fixed-assets modules.
drop function if exists public.erp_create_cloud_project(uuid, text, text, date, date, numeric, numeric) cascade;
drop function if exists public.erp_cloud_projects_dashboard(uuid, date) cascade;
drop function if exists public.erp_add_cloud_project_task(uuid, uuid, text, date, date, numeric) cascade;
drop function if exists public.erp_cloud_project_profitability(uuid, uuid) cascade;
drop function if exists public.erp_cloud_assets_dashboard(uuid, date) cascade;
drop function if exists public.erp_create_cloud_fixed_asset(uuid, text, text, date, numeric) cascade;
drop function if exists public.erp_create_cloud_asset_work_order(uuid, uuid, text) cascade;
drop function if exists public.erp_generate_cloud_asset_depreciation(uuid, date) cascade;
drop function if exists public.erp_refresh_cloud_bi_snapshots(uuid, date, date) cascade;

commit;
