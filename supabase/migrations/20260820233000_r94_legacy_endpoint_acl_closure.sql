-- Quality Line ERP / KAJ ERP R94
-- Forward-only ACL closure for Phase 11 legacy RPC bypasses.
--
-- PostgreSQL functions grant EXECUTE to PUBLIC by default. R90 correctly
-- revoked the authenticated role explicitly, but an inherited PUBLIC grant can
-- still make has_function_privilege('authenticated', ..., 'EXECUTE') true.
-- This migration removes every browser-facing legacy bypass from PUBLIC, anon,
-- and authenticated while retaining service_role access for governed SECURITY
-- DEFINER wrappers and administrative/internal execution.

begin;

-- Commercial unfiltered/internal detail readers.
revoke all on function public.erp_r28_get_commercial_order_complete_details(uuid,uuid,boolean)
  from public, anon, authenticated;
revoke all on function public.erp_r57_commercial_reconciliation(uuid,uuid,text)
  from public, anon, authenticated;
revoke all on function public.erp_r62_get_commercial_order_snapshot(uuid,uuid,boolean)
  from public, anon, authenticated;

-- Maintenance unfiltered/internal detail readers.
revoke all on function public.erp_r57_maintenance_cost_reconciliation(uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.erp_r57_maintenance_material_issue_state(uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.erp_r64_get_maintenance_order_snapshot(uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.erp_r88_list_maintenance_payments(uuid,uuid)
  from public, anon, authenticated;
revoke all on function public.erp_r88_vehicle_service_card(uuid,text)
  from public, anon, authenticated;

-- Cashbox low-level readers/mutations now owned by R90 guarded wrappers.
revoke all on function public.erp_r42_list_cash_accounts(uuid)
  from public, anon, authenticated;
revoke all on function public.erp_r22_cloud_cash_account_balances(uuid)
  from public, anon, authenticated;
revoke all on function public.erp_r22_cloud_cash_ledger_reconciliation(uuid)
  from public, anon, authenticated;
revoke all on function public.erp_r42_save_cash_account(uuid,jsonb)
  from public, anon, authenticated;
revoke all on function public.erp_delete_cloud_cash_account(uuid,text)
  from public, anon, authenticated;
revoke all on function public.erp_r22_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text)
  from public, anon, authenticated;
revoke all on function public.erp_r22_post_cloud_cash_transaction(uuid,jsonb,boolean)
  from public, anon, authenticated;
revoke all on function public.erp_delete_cloud_cash_transaction(uuid,text)
  from public, anon, authenticated;
revoke all on function public.erp_delete_cloud_cash_transfer(uuid,text)
  from public, anon, authenticated;

-- Preserve explicit internal execution. SECURITY DEFINER wrappers are owned by
-- the migration owner, but keeping service_role explicit documents and guards
-- the intended non-browser boundary.
grant execute on function public.erp_r28_get_commercial_order_complete_details(uuid,uuid,boolean)
  to service_role;
grant execute on function public.erp_r57_commercial_reconciliation(uuid,uuid,text)
  to service_role;
grant execute on function public.erp_r62_get_commercial_order_snapshot(uuid,uuid,boolean)
  to service_role;
grant execute on function public.erp_r57_maintenance_cost_reconciliation(uuid,uuid)
  to service_role;
grant execute on function public.erp_r57_maintenance_material_issue_state(uuid,uuid)
  to service_role;
grant execute on function public.erp_r64_get_maintenance_order_snapshot(uuid,uuid)
  to service_role;
grant execute on function public.erp_r88_list_maintenance_payments(uuid,uuid)
  to service_role;
grant execute on function public.erp_r88_vehicle_service_card(uuid,text)
  to service_role;
grant execute on function public.erp_r42_list_cash_accounts(uuid)
  to service_role;
grant execute on function public.erp_r22_cloud_cash_account_balances(uuid)
  to service_role;
grant execute on function public.erp_r22_cloud_cash_ledger_reconciliation(uuid)
  to service_role;
grant execute on function public.erp_r42_save_cash_account(uuid,jsonb)
  to service_role;
grant execute on function public.erp_delete_cloud_cash_account(uuid,text)
  to service_role;
grant execute on function public.erp_r22_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text)
  to service_role;
grant execute on function public.erp_r22_post_cloud_cash_transaction(uuid,jsonb,boolean)
  to service_role;
grant execute on function public.erp_delete_cloud_cash_transaction(uuid,text)
  to service_role;
grant execute on function public.erp_delete_cloud_cash_transfer(uuid,text)
  to service_role;

commit;
