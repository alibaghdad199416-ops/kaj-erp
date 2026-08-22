from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
checks = {
    'commercial order table': ('lib/core/widgets/commercial_workflow_order_table.dart', ['Order number', 'Workflow stage', 'Details & Items']),
    'order lifecycle details': ('lib/features/sales/workflow/pages/order_details_dialog.dart', ['Ordered qty', 'Invoiced qty', 'Remaining qty', 'Item lifecycle: Ordered → Warehouse movement → Invoiced']),
    'maintenance scheduling/history UI': ('lib/features/inventory/cars/pages/vehicle_service_card_page.dart', ['schedule.assign_other', 'history_detail.edit', 'Linked order']),
    'cashbox workspace': ('lib/features/accounting/cashbox/pages/cashbox_page.dart', ['Current Balance', 'Related document', 'Counter account']),
    'notification deep links': ('lib/features/notifications/pages/notification_center_page.dart', ["notification['deepLink']", 'report']),
    'report event persistence': ('lib/features/settings/reports/data/reports_repository.dart', ['erp_r88_record_report_event']),
    'granular client actions': (
        'lib/features/settings/access/controllers/access_controller.dart',
        ['PermissionContract.hasRestrictedActions', 'PermissionContract.canPerformAction'],
    ),
    'canonical granular action contract': (
        'lib/core/security/permission_contract.dart',
        [
            'actionRestriction(resource)',
            'hasRestrictedActions(permissionCodes, resource)',
            'permissionCodes.contains(action(resource, actionName))',
            'permissionCodes.contains(legacyPermission)',
        ],
    ),
    'phase11 migration': ('supabase/migrations/20260819210000_r88_phase11_operational_financial_closure.sql', [
        'erp_manage_commercial_order_component_v3', "'receipt','logistics'", 'erp_r88_filter_trial_balance_row',
        "x->>'cashIn'", 'erp_vehicle_maintenance_schedules', 'erp_maintenance_history_details',
        'erp_r88_record_report_event', "'maintenance','material_issue.approve'", "'maintenance','payment'",
        'erp_r88_list_maintenance_payments', 'erp_r88_materialize_maintenance_schedule_reminders'
    ]),
}
errors=[]
for label,(rel,needles) in checks.items():
    path=ROOT/rel
    if not path.exists():
        errors.append(f'{label}: missing {rel}')
        continue
    text=path.read_text(encoding='utf-8', errors='replace')
    for needle in needles:
        if needle not in text:
            errors.append(f'{label}: missing marker {needle!r} in {rel}')
if errors:
    print('FAIL R88 Phase 11 focused verification')
    for e in errors: print(' -',e)
    raise SystemExit(1)
print('PASS R88 Phase 11 focused verification')
print('  - operational document tables and lifecycle quantities present')
print('  - receipt/delivery component contract repair present')
print('  - trial balance and cash-flow boundaries present')
print('  - maintenance schedule/history persistence present')
print('  - granular maintenance/payment guards present in client + PostgreSQL')
print('  - persistent operational/report notifications and deep links present')
