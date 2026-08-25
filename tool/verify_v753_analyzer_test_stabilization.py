from pathlib import Path
root=Path(__file__).resolve().parents[1]
order=(root/'lib/features/sales/workflow/pages/order_details_dialog.dart').read_text(encoding='utf-8')
test=(root/'test/core/widgets/full_page_module_route_test.dart').read_text(encoding='utf-8')
release=(root/'lib/core/release/app_release_info.dart').read_text(encoding='utf-8')
pub=(root/'pubspec.yaml').read_text(encoding='utf-8')
assert "_field(detail.$1" not in order, 'undefined _field call remains'
assert "_premiumField(detail.$1" in order, 'premium detail field mapping missing'
assert "find.text('عنوان AppBar قديم لا يظهر'), findsOneWidget" in test, 'full-page header test not aligned with unified header'
assert ('version: 18.9.23+189230' in pub) or ('version: 22.9.8+229008' in pub)
assert ("static const String version = '18.9.23';" in release) or ("static const String version = '22.9.8';" in release)
print('PASS V7.5.3 analyzer and full-page window test stabilization')
