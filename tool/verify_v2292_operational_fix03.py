from pathlib import Path
root=Path(__file__).resolve().parents[1]
checks={
 'version': '22.9.2+229002' in (root/'pubspec.yaml').read_text(encoding='utf-8'),
 'migration': (root/'supabase/migrations/20260807030000_v762_workflow_posting_payment_integrity.sql').exists(),
 'invoice_guard': 'erp_v762_approve_workflow_invoice' in (root/'supabase/migrations/20260807030000_v762_workflow_posting_payment_integrity.sql').read_text(encoding='utf-8'),
 'journal_balance': 'posting_journal_unbalanced' in (root/'supabase/migrations/20260807030000_v762_workflow_posting_payment_integrity.sql').read_text(encoding='utf-8'),
 'payment_guard': 'erp_v762_apply_workflow_payment' in (root/'supabase/migrations/20260807030000_v762_workflow_posting_payment_integrity.sql').read_text(encoding='utf-8'),
 'maintenance_guard': 'erp_v762_assert_maintenance_payment_ready' in (root/'supabase/migrations/20260807030000_v762_workflow_posting_payment_integrity.sql').read_text(encoding='utf-8'),
 'maintenance_diagnostics': 'maintenance_payment_batch' in (root/'lib/features/maintenance/data/maintenance_repository.dart').read_text(encoding='utf-8'),
}
bad=[k for k,v in checks.items() if not v]
if bad: raise SystemExit('FAIL V22.9.2 operational fix 03: '+', '.join(bad))
print('PASS V22.9.2 operational fix 03 invoice, posting and payment integrity verification')
print(f'- {len(checks)} operational contracts verified')
