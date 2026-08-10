from pathlib import Path
import json, sys
ROOT = Path(__file__).resolve().parents[1]
checks = {
  'phase6 components': ROOT/'lib/design_system/kaj_phase6_components.dart',
  'accounting center': ROOT/'lib/features/accounting/pages/accounting_center_page.dart',
  'cashboxes': ROOT/'lib/features/accounting/cashbox/pages/cashbox_page.dart',
  'expenses': ROOT/'lib/features/accounting/expenses/pages/expenses_page.dart',
  'installments': ROOT/'lib/features/accounting/installments/pages/installments_page.dart',
  'fixed assets': ROOT/'lib/features/accounting/fixed_assets/fixed_assets_page.dart',
  'settings hub': ROOT/'lib/features/settings/pages/settings_hub_page.dart',
  'users': ROOT/'lib/features/settings/access/pages/users_page.dart',
  'reports': ROOT/'lib/features/settings/reports/pages/reports_page.dart',
  'monitor': ROOT/'lib/features/settings/system_monitor/pages/system_monitor_page.dart',
  'recycle bin': ROOT/'lib/features/settings/recycle_bin/pages/recycle_bin_page.dart',
}
missing=[name for name,path in checks.items() if not path.exists()]
if missing: raise SystemExit('Missing Phase 6 files: '+', '.join(missing))
component=(checks['phase6 components']).read_text(encoding='utf-8')
accounting=(checks['accounting center']).read_text(encoding='utf-8')
settings=(checks['settings hub']).read_text(encoding='utf-8')
pub=(ROOT/'pubspec.yaml').read_text(encoding='utf-8')
pkg=json.loads((ROOT/'package.json').read_text(encoding='utf-8'))
contracts=[
 ('version', 'version: 21.5.0+215000' in pub),
 ('npm version', pkg.get('version')=='21.5.0'),
 ('hero', 'class KajExecutiveHero' in component),
 ('section frame', 'class KajExecutiveSectionFrame' in component),
 ('status badge', 'class KajExecutiveStatusBadge' in component),
 ('accounting localized sections', "'Chart of Accounts'" in accounting and 'section.en' in accounting),
 ('accounting hero', 'KajExecutiveHero' in accounting),
 ('settings hero', 'KajExecutiveHero' in settings),
 ('settings bilingual', 'Settings & Control Center' in settings),
]
failed=[name for name,ok in contracts if not ok]
if failed: raise SystemExit('FAIL V21.5 Phase 6: '+', '.join(failed))
print('PASS V21.5 Phase 6 finance and administration luxury verification')
print(f'PASS {len(contracts)} finance/admin design, release and localization contracts')
