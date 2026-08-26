begin;

-- Phase 2 security closure: sensitive tenant-scoped tables must remain
-- protected even for table owners. This is intentionally forward-only and
-- data-preserving; it does not change rows or grant client DML access.

alter table if exists public.erp_audit_log enable row level security;
alter table if exists public.erp_audit_log force row level security;

alter table if exists public.erp_document_processing_jobs enable row level security;
alter table if exists public.erp_document_processing_jobs force row level security;

-- The document-processing table already has its canonical tenant policy from
-- R53. Reassert it idempotently so a disposable reset cannot depend on
-- migration ordering side effects.
do $$
begin
  if to_regclass('public.erp_document_processing_jobs') is not null then
    drop policy if exists tenant_access on public.erp_document_processing_jobs;
    create policy tenant_access
      on public.erp_document_processing_jobs
      for all
      to authenticated
      using (public.erp_user_belongs_to_company(company_id))
      with check (public.erp_user_belongs_to_company(company_id));
  end if;
end $$;

-- Audit rows are never directly writable by client roles. Keep the existing
-- admin-only read boundary and make the RLS requirement explicit.
do $$
begin
  if to_regclass('public.erp_audit_log') is not null then
    drop policy if exists erp_audit_log_admin_select on public.erp_audit_log;
    create policy erp_audit_log_admin_select
      on public.erp_audit_log
      for select
      to authenticated
      using (public.is_company_admin(company_id));
    revoke all on public.erp_audit_log from anon, authenticated;
    grant select on public.erp_audit_log to authenticated;
  end if;
end $$;

notify pgrst,'reload schema';
commit;
