from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
errors = []

def read(path):
    return (ROOT / path).read_text(encoding='utf-8', errors='replace')

def need(condition, message):
    if not condition:
        errors.append(message)

sql = read('tool/final_deep_audit.sql')
workflow = read('.github/workflows/stage3-final-deep-audit.yml')

need('\\set ON_ERROR_STOP on' in sql, 'runtime audit is not fail-closed on SQL errors')
need('FINAL_DEEP_AUDIT_RUNTIME_PASS' in sql, 'runtime audit has no terminal PASS marker')
need('erp_v2300_create_sales_order' in sql and 'erp_v2300_create_purchase_order' in sql, 'sales/purchases runtime coverage missing')
need('sales retry not idempotent' in sql, 'sales idempotency assertion missing')
need('purchase retry not idempotent' in sql, 'purchase idempotency assertion missing')
need('customer_not_found' in sql and 'sales rollback left partial state' in sql, 'sales rollback assertion missing')
need('stale_record_conflict' in sql and 'expected_updated_at' in sql, 'optimistic-concurrency assertion missing')
need('invalid_document_storage_path' in sql and 'storagePath' in sql, 'document storage boundary assertion missing')
need('erp_r22_approve_workflow_invoice' in sql, 'R22 accounting approval runtime contract missing')
need('RLS_DISABLED' in sql and 'DIRECT_DML_GRANTS' in sql, 'database security invariants missing')

# Catch malformed PL/pgSQL assignment patterns in the executable harness.
need(not re.search(r'(?m)^\s*payload\s*=\s*jsonb_build_object', sql), 'malformed PL/pgSQL assignment payload = jsonb_build_object')
need(not re.search(r'(?m)^\s*payload\s*=\s*jsonb_set', sql), 'malformed PL/pgSQL assignment payload = jsonb_set')

need('supabase db reset --yes' in workflow, 'Stage 3 does not replay the database from zero')
need('tool/phase2_database_security_audit.sql' in workflow, 'Stage 2 security regression is not part of Stage 3')
need('tool/final_deep_audit.sql' in workflow, 'transactional runtime audit is not executed by Stage 3')
need('flutter analyze' in workflow and 'flutter test' in workflow and 'flutter build web --release' in workflow, 'Flutter closure gates incomplete')
need('supabase db lint' in workflow, 'database lint is missing from Stage 3')
need('stage3-final-deep-audit' in workflow, 'Stage 3 active branch is not covered by its push trigger')

if errors:
    print('FAILED STAGE 3 FINAL DEEP AUDIT HARNESS')
    for error in errors:
        print(' -', error)
    raise SystemExit(1)

print('PASS STAGE 3 FINAL DEEP AUDIT HARNESS')
print('- fail-closed transactional gate')
print('- sales/purchases idempotency and rollback assertions')
print('- concurrency, document storage, accounting and tenant-security assertions')
print('- malformed PL/pgSQL assignment patterns rejected')
print('- database reset, security regression, Flutter and lint gates enforced')
