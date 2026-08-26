begin;

-- Final independent audit pass: PostgreSQL grants EXECUTE on newly-created
-- functions to PUBLIC by default. Earlier release migrations added explicit
-- authenticated grants but several SECURITY DEFINER reporting/audit functions
-- never revoked PUBLIC/anon, leaving browser-callable privileged surfaces.
-- Close the concrete discovered surfaces without changing signatures.

revoke all on function public.erp_v759_accounting_integrity_audit(uuid) from public,anon;
grant execute on function public.erp_v759_accounting_integrity_audit(uuid) to authenticated,service_role;

revoke all on function public.erp_v761_accounting_integrity_audit(uuid) from public,anon;
grant execute on function public.erp_v761_accounting_integrity_audit(uuid) to authenticated,service_role;

revoke all on function public.erp_cloud_trial_balance(uuid,text) from public,anon;
grant execute on function public.erp_cloud_trial_balance(uuid,text) to authenticated,service_role;

revoke all on function public.erp_v762_approve_workflow_invoice(uuid,uuid,text) from public,anon;
grant execute on function public.erp_v762_approve_workflow_invoice(uuid,uuid,text) to authenticated,service_role;
revoke all on function public.erp_v762_apply_workflow_payment(uuid,uuid,text,jsonb) from public,anon;
grant execute on function public.erp_v762_apply_workflow_payment(uuid,uuid,text,jsonb) to authenticated,service_role;
revoke all on function public.erp_v762_assert_maintenance_payment_ready(uuid,uuid) from public,anon;
grant execute on function public.erp_v762_assert_maintenance_payment_ready(uuid,uuid) to authenticated,service_role;
revoke all on function public.erp_approve_cloud_sales_workflow_invoice(uuid,uuid) from public,anon;
grant execute on function public.erp_approve_cloud_sales_workflow_invoice(uuid,uuid) to authenticated,service_role;
revoke all on function public.erp_approve_cloud_purchase_workflow_invoice(uuid,uuid) from public,anon;
grant execute on function public.erp_approve_cloud_purchase_workflow_invoice(uuid,uuid) to authenticated,service_role;
revoke all on function public.erp_pay_cloud_sales_workflow_invoice(uuid,uuid,jsonb) from public,anon;
grant execute on function public.erp_pay_cloud_sales_workflow_invoice(uuid,uuid,jsonb) to authenticated,service_role;
revoke all on function public.erp_pay_cloud_purchase_workflow_invoice(uuid,uuid,jsonb) from public,anon;
grant execute on function public.erp_pay_cloud_purchase_workflow_invoice(uuid,uuid,jsonb) to authenticated,service_role;
revoke all on function public.erp_pay_cloud_sales_workflow_invoice_batch(uuid,uuid,jsonb) from public,anon;
grant execute on function public.erp_pay_cloud_sales_workflow_invoice_batch(uuid,uuid,jsonb) to authenticated,service_role;
revoke all on function public.erp_pay_cloud_purchase_workflow_invoice_batch(uuid,uuid,jsonb) from public,anon;
grant execute on function public.erp_pay_cloud_purchase_workflow_invoice_batch(uuid,uuid,jsonb) to authenticated,service_role;

notify pgrst,'reload schema';
commit;
