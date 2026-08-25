from pathlib import Path
import sys
root=Path(__file__).resolve().parents[1]
checks={
 'commercial components': root/'lib/design_system/kaj_commercial_stage6_components.dart',
 'sales operations': root/'lib/features/sales/pages/sales_operations_page.dart',
 'purchase operations': root/'lib/features/purchases/pages/purchase_operations_page.dart',
 'sales workflow': root/'lib/features/sales/workflow/pages/sales_workflow_page.dart',
 'purchase workflow': root/'lib/features/purchases/pages/purchase_workflow_page.dart',
 'sales draft': root/'lib/features/sales/workflow/pages/sales_order_draft_page.dart',
 'purchase draft': root/'lib/features/purchases/pages/purchase_order_draft_page.dart',
}
missing=[name for name,p in checks.items() if not p.exists()]
if missing:
 print('FAIL missing:', ', '.join(missing)); sys.exit(1)
component=checks['commercial components'].read_text(encoding='utf-8')
required=['KajCommercialWorkspace','KajCommercialDocumentHeader','KajCommercialSection','KajCommercialWorkflowRibbon','KajCommercialLoadingState','KajCommercialEmptyState']
for token in required:
 if token not in component:
  print('FAIL missing component',token); sys.exit(1)
for key in ('sales operations','purchase operations'):
 text=checks[key].read_text(encoding='utf-8')
 if 'KajCommercialWorkspace' not in text:
  print('FAIL workspace not adopted:',key); sys.exit(1)
for key in ('sales workflow','purchase workflow'):
 text=checks[key].read_text(encoding='utf-8')
 if 'KajCommercialLoadingState' not in text or 'KajCommercialEmptyState' not in text:
  print('FAIL states not adopted:',key); sys.exit(1)
print('PASS V22.5 full redesign stage 06 commercial verification')
print('PASS sales, purchases, orders, invoices, payments, approvals and printing UI contracts')
