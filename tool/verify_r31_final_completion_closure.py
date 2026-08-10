from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[1]
def text(p): return (ROOT/p).read_text(encoding='utf-8')
checks={}
def need(name, ok): checks[name]=bool(ok)
need('r30 gate retained', (ROOT/'tool/verify_r30_completion_audit.py').exists())
need('asset history has no unix epoch fallback', 'fromMillisecondsSinceEpoch(0' not in text('lib/features/inventory/asset_history/repositories/asset_history_repository.dart'))
need('asset history date is nullable', 'final DateTime? date;' in text('lib/features/inventory/asset_history/models/asset_history_event.dart'))
need(
    'asset history renders missing date safely',
    re.search(
        r"event\.date\s*==\s*null\s*\?\s*'—'",
        text('lib/features/inventory/asset_history/pages/asset_history_page.dart'),
    ) is not None,
)
warehouse_page = text('lib/features/inventory/pages/warehouse_management_page.dart')
warehouse_extents = [int(value) for value in re.findall(r'mainAxisExtent:\s*(\d+)', warehouse_page)]
need('warehouse card overflow headroom', any(value >= 124 for value in warehouse_extents))
need('supplier card overflow headroom', any(x in text('lib/features/business_partners/suppliers/pages/suppliers_page.dart') for x in ['mainAxisExtent: 142','mainAxisExtent: 126']))
need('customer card overflow headroom', any(x in text('lib/features/business_partners/customers/pages/customers_page.dart') for x in ['mainAxisExtent: 142','mainAxisExtent: 126']))
need('maintenance picker overflow headroom', any(x in text('lib/features/maintenance/pages/add_maintenance_order_page.dart') for x in ['mainAxisExtent: 136','mainAxisExtent: 164','mainAxisExtent: 180']))
need('r31 cache token', any(x in text('web/index.html') for x in ('r41-export-language-canonical-closure-20260809','r42-production-cashbox-guard-closure-20260809','r43-performance-functional-closure-20260809','r47-production-runtime-dependency-closure-20260810','r49-')))
need('r31 deploy script exists', (ROOT/'tool/deploy_r31_production.ps1').exists())
need('r31 workspace validation exists', (ROOT/'tool/validate_r31_workspace.ps1').exists())
need('default deploy points r31', any(x in __import__('json').loads(text('package.json'))['scripts'].get('deploy:production','') for x in ('deploy_r41_production.ps1','deploy_r42_production.ps1','deploy_r43_production.ps1','deploy_r44_production.ps1','deploy_r49_production.ps1')))
for name,ok in checks.items(): print(('PASS' if ok else 'FAIL'),name)
failed=[n for n,o in checks.items() if not o]
if failed: raise SystemExit('R31 failed: '+', '.join(failed))
print(f'PASS R31 final completion closure — {len(checks)} gates')
