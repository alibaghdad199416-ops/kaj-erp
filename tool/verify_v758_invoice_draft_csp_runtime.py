from pathlib import Path

root = Path(__file__).resolve().parents[1]
pub = (root / 'pubspec.yaml').read_text(encoding='utf-8')
release = (root / 'lib/core/release/app_release_info.dart').read_text(encoding='utf-8')
fire = (root / 'firebase.json').read_text(encoding='utf-8')
sql = (root / 'supabase/migrations/20260806230000_v758_invoice_draft_csp_runtime.sql').read_text(encoding='utf-8')
repo = (root / 'lib/features/sales/workflow/repositories/sales_workflow_repository.dart').read_text(encoding='utf-8')

assert ('version: 18.9.28+189280' in pub) or ('version: 22.9.8+229008' in pub)
assert ("18.9.28-v758-invoice-draft-csp-runtime" in release) or ("static const String version = '22.9.8'" in release)
assert "frame-src 'self' blob:" in fire
assert 'erp_v758_active_logistics' in sql
assert "('approved','partially_executed','completed','confirmed')" in sql
assert 'accountPreflightWarning' in sql
assert 'pg_advisory_xact_lock' in sql
assert 'if v_existing is not null then return v_existing' in sql
assert 'erp_create_cloud_sales_workflow_invoice' in repo
print('PASS V7.5.8 resilient invoice draft creation and blob-frame CSP runtime')
