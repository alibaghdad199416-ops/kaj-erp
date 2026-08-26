from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / 'supabase' / 'migrations' / '20260826220000_r57_stage11_state_health_closure.sql'

text = MIGRATION.read_text(encoding='utf-8')

required_fragments = (
    "create or replace function public.erp_r16_current_state_health(p_company_id uuid)",
    "from public.erp_canonical_reconciliation_issues",
    "from public.erp_canonical_deletion_tombstones",
    "'persistentDeletionConflictCount'",
    "'permanentDeletionTombstoneCount'",
    "'unresolvedCanonicalReconciliationIssueCount'",
    "'openCanonicalIssues'",
    "'canonicalStateVersion', 16",
    "grant execute on function public.erp_r16_current_state_health(uuid) to authenticated, service_role",
)

for fragment in required_fragments:
    assert fragment in text, f'missing Stage 11 health contract fragment: {fragment}'

assert "public.erp_r15_reconcile_company_state(p_company_id)" not in text, (
    'Stage 11 health must remain read-only and must not call the admin-only '
    'mutating reconciliation RPC.'
)
assert re.search(r"v_conflicts\s*:=\s*v_conflicts\s*\+", text), (
    'persistent deletion conflicts must be cumulative across all participating tables'
)
assert "raise exception 'company_membership_required'" in text
assert "revoke all on function public.erp_r16_current_state_health(uuid) from anon" in text

print('PASS Stage 11 full-program state-health closure source audit')
