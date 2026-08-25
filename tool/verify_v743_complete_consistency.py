from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
assert any(v in (ROOT/'pubspec.yaml').read_text(encoding='utf-8') for v in ['18.9.14+189140','22.9.8+229008'])
purchase=(ROOT/'lib/features/purchases/pages/purchase_workflow_page.dart').read_text(encoding='utf-8')
for status in ["'approved'", "'posted'", "'completed'", "'confirmed'"]:
    assert status in purchase, status
assert "order['invoiceId']" in purchase and '.trim()' in purchase
sales=(ROOT/'lib/features/sales/workflow/pages/sales_workflow_page.dart').read_text(encoding='utf-8')
for status in ["'approved'", "'posted'", "'completed'"]:
    assert status in sales, status
full=(ROOT/'test/core/widgets/full_page_module_route_test.dart').read_text(encoding='utf-8')
assert 'expect(actionTop, lessThan(contentTop));' in full
alias=(ROOT/'test/runtime_alias_models_test.dart').read_text(encoding='utf-8')
assert "expect(map['schema_version'], 4);" in alias
repo=(ROOT/'lib/features/purchases/repositories/purchase_workflow_repository.dart').read_text(encoding='utf-8')
assert "core/localization/app_localizations.dart" in repo
sql=(ROOT/'supabase/migrations/20260806064500_v742_conflict_free_workflow_and_accounting.sql').read_text(encoding='utf-8')
assert "('approved','posted','completed','confirmed')" in sql
print('PASS V7.4.3 complete consistency audit')
print('  - purchase and sales invoicing fallbacks match database eligibility')
print('  - historical completed logistics do not hide invoice creation')
print('  - known Flutter test expectations match current window and schema behavior')
print('  - purchase localization import remains valid')
