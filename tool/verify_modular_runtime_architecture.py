from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        errors.append(f'missing required file: {relative}')
        return ''
    return path.read_text(encoding='utf-8')


def require(source: str, token: str, label: str) -> None:
    if token not in source:
        errors.append(f'{label}: missing {token!r}')


main = read('lib/main.dart')
deps = read('lib/app/bootstrap/app_dependencies.dart')
coordinator = read('lib/core/events/app_data_refresh_coordinator.dart')
runtime = read('lib/core/cloud/erp_runtime_capabilities_controller.dart')
loader = read('lib/core/startup/authenticated_data_loader.dart')
shell = read('lib/core/widgets/app_module_shell.dart')
top_bar = read('lib/core/widgets/app_workspace_top_bar.dart')
reader = read('lib/core/models/model_value_reader.dart')
maintenance = read('lib/features/maintenance/controllers/maintenance_controller.dart')
cashbox_controller = read('lib/features/accounting/cashbox/controllers/cashbox_controller.dart')
accounting_controller = read('lib/features/accounting/controllers/accounting_controller.dart')
access_controller = read('lib/features/settings/access/controllers/access_controller.dart')
settings_controller = read('lib/features/settings/controllers/settings_controller.dart')
realtime = read('lib/core/cloud/cloud_realtime_bridge.dart')
localization = read('lib/core/localization/app_localizations.dart')
preferences = read('lib/core/preferences/app_preferences_controller.dart')
ui_preferences = read('lib/core/preferences/user_interface_preferences.dart')
migration = read('supabase/migrations/20260804143000_auth_user_delete_and_readiness_fix.sql')
manage_user_function = read('supabase/functions/admin-manage-user/index.ts')
user_admin_service = read('lib/core/cloud/supabase_user_administration_service.dart')

require(main, 'AppDependencies.create()', 'composition root')
require(main, 'dependencies.providers', 'composition root')
if '/controllers/' in main:
    errors.append('main.dart must not import or instantiate feature controllers')
if 'AppDataChangeBus.instance.events.listen' in main:
    errors.append('main.dart still owns a hard-coded data refresh listener')

provider_types = [
    'ErpRuntimeCapabilitiesController',
    'AppPreferencesController',
    'CarsController',
    'CarImagesController',
    'OpportunitiesController',
    'CustomersController',
    'SuppliersController',
    'SalesController',
    'ExpensesController',
    'InventoryController',
    'MaintenanceController',
    'DashboardController',
    'ReportsController',
    'InstallmentsController',
    'PurchasesController',
    'CashboxController',
    'AccountingController',
    'AccessController',
    'SettingsController',
]
for controller in provider_types:
    require(deps, f'ChangeNotifierProvider<{controller}>.value', 'provider registry')

# New feature controllers must be either application-scoped providers or an
# explicit page-local controller. This catches the common failure where a new
# module compiles but its Provider is forgotten.
registered_provider_types = set(
    re.findall(r'ChangeNotifierProvider<([A-Za-z0-9_]+)>\.value', deps)
)
feature_controller_types: set[str] = set()
for path in (ROOT / 'lib/features').rglob('*_controller.dart'):
    source = path.read_text(encoding='utf-8', errors='replace')
    feature_controller_types.update(
        re.findall(
            r'class\s+([A-Za-z0-9_]+Controller)\s+extends\s+ChangeNotifier',
            source,
        )
    )
page_local_controller_types = {'SystemMonitorController'}
missing_controller_registration = (
    feature_controller_types
    - registered_provider_types
    - page_local_controller_types
)
if missing_controller_registration:
    errors.append(
        'feature controllers missing from AppDependencies or the page-local '
        'allowlist: ' + ', '.join(sorted(missing_controller_registration))
    )
stale_page_local = page_local_controller_types - feature_controller_types
if stale_page_local:
    errors.append(
        'stale page-local controller allowlist: ' + ', '.join(sorted(stale_page_local))
    )

for rule_id in (
    'cars', 'car-images-cache', 'opportunities', 'customers', 'suppliers',
    'sales', 'purchases', 'inventory', 'maintenance', 'installments',
    'expenses', 'cashbox', 'accounting', 'access', 'settings', 'dashboard',
    'reports',
):
    require(deps, f"id: '{rule_id}'", 'refresh rules')
require(deps, 'loadInventory(force: true)', 'inventory refresh')
require(deps, 'loadDashboard(force: true)', 'dashboard refresh')
require(deps, 'reports.loadReports(', 'reports refresh')

for token in ('state.running', 'state.runAgain', 'pendingEvents', 'Timer(', 'try {', 'catch (error, stackTrace)'):
    require(coordinator, token, 'refresh coordinator')

require(loader, "name: 'runtime-readiness'", 'authenticated startup')
require(loader, 'runtimeCapabilities.check', 'authenticated startup')
require(top_bar, '_ConnectionIndicator', 'top-bar runtime diagnostics UI')
require(top_bar, 'unavailableCapabilitiesForRoute(currentRoute)', 'top-bar runtime diagnostics UI')
require(top_bar, '_RefreshWorkspaceButton', 'top-bar refresh action')
for route in (
    '/inventory', '/maintenance', '/business-partners', '/customer-service',
    '/sales', '/purchases', '/accounting', '/settings',
):
    require(runtime, f"'{route}'", 'runtime capability routes')

for table in (
    'erp_maintenance_orders', 'erp_maintenance_parts',
    'erp_maintenance_payments', 'erp_fixed_assets', 'erp_fiscal_periods',
):
    require(realtime, table, 'Supabase Realtime bindings')

# Every literal mutation or Realtime source must have a refresh consumer.
# Notification Center owns its own page-local listener; all other sources are
# consumed by AppDataRefreshCoordinator rules.
refresh_sources: set[str] = set()
for match in re.finditer(r'sources:\s*(?:const\s*)?\{([^}]*)\}', deps, re.S):
    refresh_sources.update(re.findall(r"['\"]([^'\"]+)['\"]", match.group(1)))
aggregate_match = re.search(
    r'_aggregateSources\s*=\s*<String>\{([^}]*)\}',
    deps,
    re.S,
)
if aggregate_match:
    refresh_sources.update(
        re.findall(r"['\"]([^'\"]+)['\"]", aggregate_match.group(1))
    )

emitted_sources: set[str] = set()
for path in (ROOT / 'lib').rglob('*.dart'):
    source = path.read_text(encoding='utf-8', errors='replace')
    emitted_sources.update(
        re.findall(
            r"AppDataChangeBus\.instance\.publish\(\s*['\"]([^'\"]+)['\"]",
            source,
        )
    )
    emitted_sources.update(
        re.findall(
            r"AppDataChangeBus\.instance\.publish\(\s*source\s*:\s*['\"]([^'\"]+)['\"]",
            source,
        )
    )

realtime_sources: set[str] = set()
for match in re.finditer(
    r"_RealtimeBinding\(\s*['\"][^'\"]+['\"]\s*,\s*\{([^}]*)\}",
    realtime,
    re.S,
):
    realtime_sources.update(
        re.findall(r"['\"]([^'\"]+)['\"]", match.group(1))
    )

direct_listener_sources = {'notifications'}
require(
    read('lib/features/notifications/pages/notification_center_page.dart'),
    "'notifications'",
    'notification direct refresh listener',
)
unconsumed_sources = (
    emitted_sources | realtime_sources
) - refresh_sources - direct_listener_sources - {'all'}
if unconsumed_sources:
    errors.append(
        'data-change sources without a refresh consumer: '
        + ', '.join(sorted(unconsumed_sources))
    )

require(maintenance, "AppDataChangeBus.instance.publish(", 'maintenance mutations')
require(maintenance, "'maintenance',", 'maintenance mutations')

require(coordinator, "event.source != 'all'", 'full refresh invalidation')
for token in ('account_delete', "operation: 'update'", "operation: 'delete'"):
    require(cashbox_controller, token, 'cashbox mutation invalidation')
for token in ('partner-payment-update', 'partner-payment-delete'):
    require(accounting_controller, token, 'partner payment invalidation')
for token in ('user-permission-clear', 'user-permission-save', 'role-permission-save'):
    require(access_controller, token, 'permission invalidation')
for token in ("_publishSettingsChange('company-save')", "_publishSettingsChange('branch-save'", "_publishSettingsChange('currency-save'", "'all'", "operation: 'backup-restore'"):
    require(settings_controller, token, 'settings invalidation')

for token in ('_toSnakeCase', '_toCamelCase', 'dateTimeOr', 'boolean(', 'objectMap('):
    require(reader, token, 'defensive model reader')

critical_models = [
    'lib/features/settings/access/models/user_model.dart',
    'lib/features/settings/access/models/audit_log_model.dart',
    'lib/features/settings/models/branch_model.dart',
    'lib/features/settings/models/backup_model.dart',
    'lib/features/sales/models/sale_model.dart',
    'lib/features/purchases/models/purchase_model.dart',
    'lib/features/purchases/models/purchase_item_model.dart',
    'lib/features/accounting/cashbox/models/cash_transaction_model.dart',
    'lib/features/accounting/expenses/models/expense_model.dart',
    'lib/features/accounting/installments/models/installment_model.dart',
    'lib/features/accounting/models/account_statement_line_model.dart',
    'lib/features/inventory/cars/models/car_image_model.dart',
]
for model in critical_models:
    source = read(model)
    require(source, 'ModelValueReader.', model)
    for fragile in ("as String", "as int", "as double", "DateTime.parse(map["):
        if fragile in source:
            errors.append(f'{model}: retains fragile cloud parsing token {fragile!r}')

# UI files must not call Supabase directly. All cloud access belongs in a
# repository/service so pages remain replaceable and testable. Include legacy
# feature layouts where a page lives directly under the feature directory
# (for example `fixed_assets/fixed_assets_page.dart`) instead of `/pages/`.
for path in (ROOT / 'lib/features').rglob('*.dart'):
    relative_parts = path.relative_to(ROOT / 'lib/features').parts
    is_ui_file = (
        path.name.endswith('_page.dart')
        or path.name.endswith('_widget.dart')
        or 'pages' in relative_parts
        or 'widgets' in relative_parts
    )
    if not is_ui_file:
        continue
    source = path.read_text(encoding='utf-8', errors='replace')
    if 'Supabase.instance' in source or 'package:supabase_flutter' in source:
        errors.append(
            'direct Supabase access in UI file: ' + str(path.relative_to(ROOT))
        )

require(localization, "<Locale>[Locale('en'), Locale('ar')]", 'locale order')
require(localization, "values['en'] ?? values['ar']", 'translation fallback')
require(localization, "static String localeCode = 'en';", 'translation default')
require(preferences, "Locale('en')", 'preference default')
require(ui_preferences, "localeCode: 'en'", 'per-user preference default')
require(ui_preferences, "map['locale_code'] == 'ar'", 'per-user preference fallback')


require(migration, 'v_auth_user_id uuid := auth.uid()', 'runtime readiness identity')
require(migration, 'membership.user_id = v_auth_user_id', 'runtime readiness membership')
if 'erp_current_firebase_uid' in migration or 'membership.user_uid' in migration:
    errors.append('runtime readiness hotfix must not use the retired Firebase identity columns')
for token in (
    "'user_delete_blocked'",
    'admin.auth.admin.deleteUser(targetUserId, false)',
    'ERP user deletion rollback failed',
):
    require(manage_user_function, token, 'cloud user deletion')
for token in ('on FunctionException catch', "'user_delete_blocked' =>"):
    require(user_admin_service, token, 'cloud user error handling')

for capability in (
    'dashboard', 'search', 'notifications', 'cars', 'customers', 'suppliers',
    'customer_service', 'sales', 'purchases', 'installments', 'inventory',
    'maintenance', 'accounting', 'cashbox', 'expenses', 'reports', 'settings',
    'access', 'documents',
):
    require(migration, f"'{capability}'", 'runtime readiness migration')

package_path = ROOT / 'package.json'
if package_path.is_file():
    package = json.loads(package_path.read_text(encoding='utf-8'))
    script = package.get('scripts', {}).get('verify:modular-runtime', '')
    normalized_script = script.replace('python -B tool/', 'python tool/')
    if normalized_script != 'python tool/verify_modular_runtime_architecture.py':
        errors.append('package.json does not expose verify:modular-runtime')

if errors:
    print('FAILED modular runtime architecture verification')
    for error in errors:
        print('  -', error)
    raise SystemExit(1)

print('PASS modular runtime architecture verification')
print('  - main.dart is reduced to bootstrap and composition')
print('  - all long-lived controllers are registered centrally or explicitly page-local')
print('  - all mutation and Realtime sources have an explicit refresh consumer')
print('  - data refresh is declarative, debounced, and re-entrant safe')
print('  - Supabase readiness is visible per module')
print('  - UI pages and widgets do not access Supabase directly')
print('  - critical cloud models use defensive key/type conversion')
print('  - English is the primary default and Arabic remains supported')
