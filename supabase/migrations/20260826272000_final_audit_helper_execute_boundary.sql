begin;

-- Re-assert the final EXECUTE boundary for the audit payload helper.
-- This helper is an implementation detail of SECURITY DEFINER audit capture;
-- it must never be a browser-callable tenant/company lookup primitive.
revoke all on function public.erp_audit_company_id_from_payload(jsonb)
  from public, anon, authenticated;

grant execute on function public.erp_audit_company_id_from_payload(jsonb)
  to service_role;

commit;
