from pathlib import Path
import json, sys

ROOT = Path(__file__).resolve().parents[1]
checks = []

def read(path):
    p = ROOT / path
    return p.read_text(encoding='utf-8') if p.exists() else ''

def need(name, ok):
    checks.append((name, bool(ok)))

pubspec = read('pubspec.yaml')
package = read('package.json')
phase5 = read('lib/design_system/kaj_phase5_components.dart')
sales = read('lib/features/sales/pages/sales_page.dart')
purchases = read('lib/features/purchases/pages/purchases_page.dart')
sales_ops = read('lib/features/sales/pages/sales_operations_page.dart')
purchase_ops = read('lib/features/purchases/pages/purchase_operations_page.dart')
sales_card = read('lib/features/sales/widgets/sale_card.dart')
purchase_card = read('lib/features/purchases/widgets/purchase_card.dart')

# Stage 5 is the commercial/sales/purchasing domain. Acceptance is based on
# source invariants and independent contracts; Quality Line output is never a
# pass/fail dependency.
need('current package version', 'version: 22.9.8+229008' in pubspec)
try:
    need('current npm package version', json.loads(package).get('version') == '22.9.8')
except Exception:
    need('current npm package version', False)

need('commercial hero exists', 'class KajCommercialHero' in phase5)
need('commercial metrics are presentation-only', 'class KajCommercialMetricData' in phase5)
need('commercial workflow exists', 'class KajCommercialWorkflow' in phase5)
need('hero avoids narrow two-column overflow', 'constraints.maxWidth < 1180' in phase5)
need('metric value is overflow-safe', 'maxLines: 2' in phase5 and 'TextOverflow.ellipsis' in phase5)
need('workflow index is bounded', 'currentIndex.clamp(0, steps.length - 1)' in phase5)

need('sales uses commercial hero', 'KajCommercialHero' in sales)
need('purchases uses commercial hero', 'KajCommercialHero' in purchases)
need('sales workflow entry exists', "AppTranslation.translate('أوامر البيع')" in sales_ops)
need('purchase workflow entry exists', "AppTranslation.translate('أوامر الشراء')" in purchase_ops)
need('sale cards use design tokens', 'KajDesignTokens.radiusMd' in sales_card)
need('purchase cards use design tokens', 'KajDesignTokens.radiusMd' in purchase_card)

# UI actions remain permission-aware; backend/RPC enforcement is the
# authoritative security boundary.
need('sales delete permission gate', "'sales.delete'" in sales)
need('purchase delete permission gate', "'purchases.delete'" in purchases)
need('sales printing handles failures', 'userFacingError(' in sales)
need('purchase printing handles failures', 'userFacingError(' in purchases)
need('purchase detail loading handles failures', 'arabicFallback: \'تعذر تحميل تفاصيل فاتورة الشراء.\'' in purchases)
need('purchase delete handles failures', 'arabicFallback: \'تعذر حذف فاتورة الشراء.\'' in purchases)

# Do not reject the package namespace `quality_line_erp`; that is only the
# Dart package name. Reject actual runtime/acceptance dependency on Quality Line.
all_stage_text = '\n'.join([phase5, sales, purchases, sales_ops, purchase_ops])
need('no Quality Line acceptance dependency',
     'qualityline.' not in all_stage_text.lower()
     and 'quality line pass' not in all_stage_text.lower()
     and 'quality line fail' not in all_stage_text.lower())

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(('PASS' if ok else 'FAIL'), name)
if failed:
    print(f'FAILED Stage 5 deep closure — {len(failed)} unresolved contracts')
    sys.exit(1)
print(f'PASS Stage 5 deep commercial closure — {len(checks)} independent contracts')
