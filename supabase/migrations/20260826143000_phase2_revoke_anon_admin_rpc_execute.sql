begin;

-- Phase 2 security closure: privileged SECURITY DEFINER command surfaces must
-- never be executable by anon. Authenticated callers must pass the function's
-- own authorization checks; anonymous callers get no execution privilege.
revoke execute on function public.erp_open_cloud_service_case(uuid, text, text, text) from public, anon;
revoke execute on function public.erp_r9_cloud_customer_service_report(uuid, uuid, text, text, text, text) from public, anon;
revoke execute on function public.erp_reject_service_stock_movement(uuid, text) from public, anon;

commit;
