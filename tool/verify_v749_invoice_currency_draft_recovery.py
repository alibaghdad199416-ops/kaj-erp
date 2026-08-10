from pathlib import Path
root = Path(__file__).resolve().parents[1]
checks = {
    'migration': root/'supabase/migrations/20260806130000_v749_invoice_currency_preflight_and_draft_delete.sql',
    'dialog': root/'lib/features/sales/workflow/pages/order_details_dialog.dart',
    'pubspec': root/'pubspec.yaml',
    'release': root/'lib/core/release/app_release_info.dart',
}
for name,p in checks.items():
    if not p.exists(): raise SystemExit(f'FAIL missing {name}: {p}')
read=lambda p:p.read_text(encoding='utf-8')
m=read(checks['migration']); d=read(checks['dialog'])
required=[
 'erp_v749_prepare_order_invoice_accounts',
 "p_company_id,'sales',p_order_id,o.currency",
 "p_company_id,'purchases',p_order_id,o.currency",
 'order currency independent from item cost currency',
 'erp_approve_cloud_sales_workflow_invoice',
 'erp_approve_cloud_purchase_workflow_invoice',
]
for x in required:
    if x not in m: raise SystemExit(f'FAIL migration marker missing: {x}')
for x in ['حذف مسودة فاتورة البيع','Delete sales invoice draft',"componentType: 'invoice'","action: 'delete'"]:
    if x not in d: raise SystemExit(f'FAIL UI marker missing: {x}')
if not any(v in read(checks['pubspec']) for v in ['version: 18.9.19+189190','version: 22.9.8+229008']): raise SystemExit('FAIL pubspec version')
if not any(v in read(checks['release']) for v in ["static const String version = '18.9.19';","static const String version = '22.9.8';"]): raise SystemExit('FAIL release version')
print('PASS V7.4.9 invoice currency preflight, approval repair, and draft deletion')
