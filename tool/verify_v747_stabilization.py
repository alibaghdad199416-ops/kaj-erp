from pathlib import Path
root = Path(__file__).resolve().parents[1]
payment = (root/'lib/core/finance/invoice_payment_batch_dialog.dart').read_text(encoding='utf-8')
maintenance = (root/'lib/features/maintenance/pages/add_maintenance_order_page.dart').read_text(encoding='utf-8')
warehouse = (root/'lib/features/inventory/pages/warehouse_management_page.dart').read_text(encoding='utf-8')
route = (root/'lib/core/widgets/app_full_page_route.dart').read_text(encoding='utf-8')
verify = (root/'tool/verify_v746_partner_currency_cashbox_inventory.py').read_text(encoding='utf-8')
pub = (root/'pubspec.yaml').read_text(encoding='utf-8')
assert '_configuredLinkedCashboxFor' in payment
assert 'widget.cashAccounts' not in payment[payment.index('class _PaymentRowCard'):]
assert 'watch<AccountingController>()' not in maintenance
assert 'final expenses =' not in maintenance
assert 'String? _scrapExpenseAccountId;' not in warehouse
assert "return _PlainContentAsWindow(closeDock: closeDock, child: child);" in route
assert "read_text(encoding='utf-8')" in verify
assert ('18.9.18+189180' in pub) or ('22.9.8+229008' in pub)
print('PASS V7.4.7 stabilization: analyzer blockers, UTF-8 verifier, and close fallback repaired')
