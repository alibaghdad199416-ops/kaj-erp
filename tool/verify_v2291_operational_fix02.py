from pathlib import Path

root = Path(__file__).resolve().parents[1]
checks = {
    'version': 'version: 22.9.1+229001' in (root / 'pubspec.yaml').read_text(encoding='utf-8'),
    'sales draft order id guard': 'final orderId = widget.orderId?.trim();' in (root / 'lib/features/sales/workflow/pages/sales_order_draft_page.dart').read_text(encoding='utf-8'),
    'purchase draft order id guard': 'final orderId = widget.orderId?.trim();' in (root / 'lib/features/purchases/pages/purchase_order_draft_page.dart').read_text(encoding='utf-8'),
    'attachment bytes guard': 'if (bytes == null || bytes.isEmpty)' in (root / 'lib/features/sales/workflow/pages/order_details_dialog.dart').read_text(encoding='utf-8'),
    'maintenance item guard': 'final item = _item(productId);' in (root / 'lib/features/maintenance/pages/add_maintenance_order_page.dart').read_text(encoding='utf-8'),
    'purchase supplier guard': 'final supplier = _supplier;' in (root / 'lib/features/purchases/pages/add_purchase_page.dart').read_text(encoding='utf-8'),
    'resell buyer guard': 'final buyer = _buyer;' in (root / 'lib/features/sales/pages/resell_car_page.dart').read_text(encoding='utf-8'),
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit('FAIL V22.9.1 operational fix 02: ' + ', '.join(failed))

risk_patterns = [
    'currentState!', 'widget.orderId!', 'file.bytes!', "document['versionId']!",
    '_supplier!', '_buyer!', '_carId!', 'existing!', 'onResell!',
]
scopes = [root / 'lib/features/sales', root / 'lib/features/purchases', root / 'lib/features/maintenance']
violations = []
for scope in scopes:
    for path in scope.rglob('*.dart'):
        text = path.read_text(encoding='utf-8')
        for pattern in risk_patterns:
            if pattern in text:
                violations.append(f'{path.relative_to(root)}: {pattern}')
if violations:
    raise SystemExit('FAIL unsafe null assertions remain:\n' + '\n'.join(violations))

print('PASS V22.9.1 operational fix 02 null-safety verification')
print(f'- {len(checks)} targeted null-safety contracts verified')
print('- no targeted unsafe null assertions remain in sales, purchases, or maintenance')
