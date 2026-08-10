-- Audit logs are local-only. Remove records synchronized by legacy releases.
DELETE FROM public.erp_records
WHERE entity_type = 'audit_logs';
