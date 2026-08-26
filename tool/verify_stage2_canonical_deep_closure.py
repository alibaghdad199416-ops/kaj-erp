from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[1]
def read(p): return (ROOT/p).read_text(encoding='utf-8')
m=read('supabase/migrations/20260826140000_phase2_rls_policy_closure.sql')
q='\n'.join(line for line in m.splitlines() if not line.strip().startswith('--'))
checks={
 'transactional migration':'begin;' in m and 'commit;' in m,
 'no executable quality-line dependency':'quality line' not in q.lower() and 'qualityline.' not in q.lower(),
 'tombstone RLS enabled':'erp_canonical_deletion_tombstones enable row level security' in q,
 'tombstone RLS forced':'erp_canonical_deletion_tombstones force row level security' in q,
 'tombstone client deny policy':'erp_canonical_deletion_tombstones_client_deny' in q and 'using (false)' in q and 'with check (false)' in q,
 'tombstone client grants revoked':'revoke all on public.erp_canonical_deletion_tombstones from public, anon, authenticated' in q,
 'reconciliation RLS enabled':'erp_canonical_reconciliation_issues enable row level security' in q,
 'reconciliation RLS forced':'erp_canonical_reconciliation_issues force row level security' in q,
 'reconciliation client deny policy':'erp_canonical_reconciliation_issues_client_deny' in q,
 'reconciliation client grants revoked':'revoke all on public.erp_canonical_reconciliation_issues from public, anon, authenticated' in q,
}
for n,v in checks.items(): print(('PASS' if v else 'FAIL'),n)
if not all(checks.values()): sys.exit(1)
print(f'PASS Stage 2 deep canonical security closure — {len(checks)} gates')
