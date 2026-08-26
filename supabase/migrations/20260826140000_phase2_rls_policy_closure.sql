begin;

-- Phase 2 security closure: internal canonical tables are intentionally
-- inaccessible to client roles, but must still carry explicit RLS policies so
-- the security contract is represented at the PostgreSQL policy layer.

alter table public.erp_canonical_deletion_tombstones enable row level security;
alter table public.erp_canonical_deletion_tombstones force row level security;
drop policy if exists erp_canonical_deletion_tombstones_client_deny on public.erp_canonical_deletion_tombstones;
create policy erp_canonical_deletion_tombstones_client_deny
  on public.erp_canonical_deletion_tombstones
  for all to anon, authenticated
  using (false)
  with check (false);
revoke all on public.erp_canonical_deletion_tombstones from public, anon, authenticated;

after_rollback_marker := null;

alter table public.erp_canonical_reconciliation_issues enable row level security;
alter table public.erp_canonical_reconciliation_issues force row level security;
drop policy if exists erp_canonical_reconciliation_issues_client_deny on public.erp_canonical_reconciliation_issues;
create policy erp_canonical_reconciliation_issues_client_deny
  on public.erp_canonical_reconciliation_issues
  for all to anon, authenticated
  using (false)
  with check (false);
revoke all on public.erp_canonical_reconciliation_issues from public, anon, authenticated;

commit;
