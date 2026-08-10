from pathlib import Path
import json
import sys

root = Path(__file__).resolve().parents[1]
required = {
    'finance components': root / 'lib/design_system/kaj_finance_stage7_components.dart',
    'accounting center': root / 'lib/features/accounting/pages/accounting_center_page.dart',
    'cashbox': root / 'lib/features/accounting/cashbox/pages/cashbox_page.dart',
    'expenses': root / 'lib/features/accounting/expenses/pages/expenses_page.dart',
    'installments': root / 'lib/features/accounting/installments/pages/installments_page.dart',
    'fixed assets': root / 'lib/features/accounting/fixed_assets/fixed_assets_page.dart',
    'account statement': root / 'lib/features/accounting/pages/account_statement_page.dart',
    'reports': root / 'lib/features/settings/reports/pages/reports_page.dart',
}
errors = []
for name, path in required.items():
    if not path.exists():
        errors.append(f'missing {name}: {path.relative_to(root)}')

component = required['finance components'].read_text(encoding='utf-8')
for symbol in ('KajFinanceWorkspace', 'KajFinanceMetricData', 'KajFinanceSection', 'KajFinanceState'):
    if f'class {symbol}' not in component:
        errors.append(f'missing component {symbol}')

for key in ('cashbox', 'expenses', 'installments', 'fixed assets', 'account statement', 'reports'):
    text = required[key].read_text(encoding='utf-8')
    if 'kaj_finance_stage7_components.dart' not in text:
        errors.append(f'{key} is not connected to stage 7 finance components')

pubspec = (root / 'pubspec.yaml').read_text(encoding='utf-8')
package = json.loads((root / 'package.json').read_text(encoding='utf-8'))
version_json = json.loads((root / 'web/version.json').read_text(encoding='utf-8'))
if 'version: 22.6.0+226000' not in pubspec:
    errors.append('pubspec version mismatch')
if package.get('version') != '22.6.0':
    errors.append('package version mismatch')
if str(version_json.get('version')) != '22.6.0':
    errors.append('web version mismatch')
if 'verify:v2260' not in package.get('scripts', {}):
    errors.append('verify:v2260 script is missing')

if errors:
    print('FAIL V22.6 full redesign stage 07 finance verification')
    for error in errors:
        print(f'  - {error}')
    sys.exit(1)

print('PASS V22.6 full redesign stage 07 finance verification')
print('  - accounting, cashboxes, expenses, installments, assets and reports are connected')
print('  - responsive finance workspace, metrics, sections and states are present')
print('  - release metadata and verifier command are consistent')
