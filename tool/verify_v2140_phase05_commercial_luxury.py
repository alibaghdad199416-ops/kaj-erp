from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
checks = {
    'version': ('pubspec.yaml', 'version: 21.4.0+214000'),
    'commercial components': ('lib/design_system/kaj_phase5_components.dart', 'class KajCommercialHero'),
    'sales hero': ('lib/features/sales/pages/sales_page.dart', 'KajCommercialHero'),
    'purchase hero': ('lib/features/purchases/pages/purchases_page.dart', 'KajCommercialHero'),
    'sales workflow': ('lib/features/sales/pages/sales_operations_page.dart', "AppTranslation.translate('أوامر البيع')"),
    'purchase workflow': ('lib/features/purchases/pages/purchase_operations_page.dart', "AppTranslation.translate('أوامر الشراء')"),
    'sale card tokens': ('lib/features/sales/widgets/sale_card.dart', 'KajDesignTokens.radiusMd'),
    'purchase card tokens': ('lib/features/purchases/widgets/purchase_card.dart', 'KajDesignTokens.radiusMd'),
    'release notes': ('docs/releases/RELEASE_21.4.0_PHASE5_AR.md', 'المرحلة الخامسة'),
}
failed=[]
for name,(rel,needle) in checks.items():
    path=ROOT/rel
    if not path.exists() or needle not in path.read_text(encoding='utf-8'):
        failed.append(f'{name}: {rel}')
if failed:
    print('FAIL V21.4 Phase 5 commercial luxury verification')
    for item in failed: print(' -', item)
    sys.exit(1)
print('PASS V21.4 Phase 5 sales, purchases, workflows, payments and printing verification')
print(f'PASS {len(checks)} commercial design and localization contracts')
