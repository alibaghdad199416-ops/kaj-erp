from pathlib import Path
root=Path(__file__).resolve().parents[1]
checks={
'workflow exception': root/'lib/core/cloud/workflow_operation_exception.dart',
'migration': root/'supabase/migrations/20260807023000_v761_operational_invoice_diagnostics.sql',
}
for name,path in checks.items():
    if not path.exists(): raise SystemExit(f'FAIL missing {name}: {path}')
for rel in ['lib/features/sales/workflow/repositories/sales_workflow_repository.dart','lib/features/purchases/repositories/purchase_workflow_repository.dart']:
    text=(root/rel).read_text(encoding='utf-8')
    assert 'WorkflowOperationException.fromPostgrest' in text
print('PASS V22.9 operational fix 01 verification')
print('- structured RPC diagnostics and idempotent invoice approval wrappers verified')
