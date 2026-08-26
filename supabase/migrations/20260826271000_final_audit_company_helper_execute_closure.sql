begin;

-- Final cross-stage hardening: the audit company-id parser is an internal
-- SECURITY DEFINER helper used by the audit trigger. It accepts arbitrary JSON
-- and can resolve a company UUID from either a UUID or a company slug. It is
-- not a browser API and must not be callable by authenticated users directly,
-- otherwise it becomes a cross-tenant company-existence oracle.
--
-- The trigger continues to work because erp_capture_audit_change() is itself
-- SECURITY DEFINER and invokes this helper server-side.

revoke all on function public.erp_audit_company_id_from_payload(jsonb)
  from public, anon, authenticated;

grant execute on function public.erp_audit_company_id_from_payload(jsonb)
  to service_role;

notify pgrst, 'reload schema';
commit;
