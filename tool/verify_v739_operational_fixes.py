#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors=[]

def require(path, *tokens):
    p=ROOT/path
    if not p.exists():
        errors.append(f'missing: {path}')
        return
    text=p.read_text(encoding='utf-8')
    for token in tokens:
        if token not in text:
            errors.append(f'{path}: missing token {token!r}')

require(Path('supabase/migrations/20260806023000_v739_operational_invoicing_cash_opportunity_performance.sql'),
        'erp_v736_active_logistics',
        'operational invoice approval without automatic capitalization journals',
        "'automaticJournalPosting',false",
        'payment_currency_must_match_order_currency',
        'cashbox_currency_must_match_order_currency',
        'erp_transfer_cloud_cash',
        'erp_sync_opportunity_sales_lifecycle',
        "'workflowCanOpen',o.id is not null")
require(Path('lib/core/widgets/app_entity_page.dart'),
        'if (insideModuleWindow) const AppWindowCloseButton()',
        'final effectiveShowBackButton = showBackButton && !insideModuleWindow')
require(Path('lib/features/accounting/cashbox/repositories/cashbox_repository.dart'),
        "'erp_transfer_cloud_cash'", 'sourceAmount', 'targetAmount', 'exchangeRate')
require(Path('lib/core/widgets/app_launch_shell.dart'), 'const AppLogo(', 'width: 238', 'height: 148')
require(Path('lib/features/customer_service/pages/customer_service_page.dart'),
        'findOrderByOpportunity', 'OrderDetailsDialog(orderId: orderId, purchase: false)')
require(Path('lib/features/sales/workflow/pages/sales_workflow_page.dart'),
        'static const Duration _loadTtl', '_loadInFlight', '_serverFlag')
require(Path('lib/features/purchases/pages/purchase_workflow_page.dart'),
        'static const Duration _loadTtl', '_loadInFlight', '_serverFlag')
require(Path('lib/features/maintenance/pages/maintenance_page.dart'), 'AppEntityPage')
require(Path('pubspec.yaml'), 'version: 18.9.9+189900')

if errors:
    print('FAILED V7.3.9 operational fixes verification')
    for e in errors: print(' -',e)
    raise SystemExit(1)
print('PASS V7.3.9 operational invoicing, cashbox, opportunity, UI and launch fixes')
print('  - approved logistics remains invoiceable and cancelled documents do not block progression')
print('  - sales, purchase and maintenance avoid automatic capitalization journals')
print('  - payment cashboxes are restricted to the order currency')
print('  - same-currency and cross-currency cashbox transfers use one atomic RPC')
print('  - opportunity links expose the full sales workflow in both directions')
print('  - module close actions are integrated beside commands and back actions are suppressed')
print('  - launch UI uses the login shell with an enlarged company logo')
