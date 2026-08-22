from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def text(rel: str) -> str:
    path = ROOT / rel
    if not path.exists():
        errors.append(f'missing file: {rel}')
        return ''
    return path.read_text(encoding='utf-8', errors='replace')


def need(label: str, condition: bool) -> None:
    if not condition:
        errors.append(label)


def has_all(label: str, rel: str, needles: list[str]) -> None:
    data = text(rel)
    missing = [needle for needle in needles if needle not in data]
    if missing:
        errors.append(f"{label}: missing {missing!r} in {rel}")


def has_all_compact(label: str, rel: str, needles: list[str]) -> None:
    """Match source-code guards independent of dart-format whitespace/wrapping."""
    data = re.sub(r'\s+', '', text(rel))
    missing = [
        needle
        for needle in needles
        if re.sub(r'\s+', '', needle) not in data
    ]
    if missing:
        errors.append(f"{label}: missing {missing!r} in {rel}")


r90_rel = 'supabase/migrations/20260820113000_r90_phase11_final_acceptance_closure.sql'
r90 = text(r90_rel)
need('R90 migration missing', bool(r90))
need('R90 must be forward-only', 'begin;' in r90.lower() and 'commit;' in r90.lower())
need('R90 must not alter historical migrations', '20260820113000_r90_phase11_final_acceptance_closure.sql' in r90_rel)
need('R90 must not contain destructive reset/drop schema operations', not re.search(r'\b(drop\s+schema|truncate\s+table|drop\s+table)\b', r90, re.I))

# 1) Commercial and Maintenance legacy detail reads cannot bypass filtered R89/R90 boundaries.
legacy_revokes = [
    'erp_r28_get_commercial_order_complete_details(uuid,uuid,boolean)',
    'erp_r57_commercial_reconciliation(uuid,uuid,text)',
    'erp_r62_get_commercial_order_snapshot(uuid,uuid,boolean)',
    'erp_r57_maintenance_cost_reconciliation(uuid,uuid)',
    'erp_r57_maintenance_material_issue_state(uuid,uuid)',
    'erp_r64_get_maintenance_order_snapshot(uuid,uuid)',
    'erp_r88_list_maintenance_payments(uuid,uuid)',
    'erp_r88_vehicle_service_card(uuid,text)',
]
for signature in legacy_revokes:
    need(
        f'authenticated legacy detail bypass not revoked: {signature}',
        re.search(rf'revoke\s+execute\s+on\s+function\s+public\.{re.escape(signature)}\s+from\s+authenticated', r90, re.I) is not None,
    )

# 2) Cross-resource field filtering must include cashbox metadata on payments.
has_all('commercial cross-cashbox payment filtering', r90_rel, [
    "v_kind='payment'", "v_item.key in ('cashAccountName')", "'cashbox','name'",
    "v_item.key in ('cashAccountId')", "'cashbox','cashAccount'",
    "v_item.key in ('cashTransactionId')", "'cashbox','reference'",
    "v_item.key in ('cashAccountCurrency')", "'cashbox','currency'",
])
has_all('maintenance payment cross-cashbox filtering', r90_rel, [
    'erp_r90_filter_maintenance_payment', "v_item.key='cashboxName'", "'cashbox','name'",
    "v_item.key='cashboxId'", "'cashbox','cashAccount'", "v_item.key='cashTransactionId'",
    "'cashbox','reference'", "v_item.key='journalEntryId'", "'cashbox','journalEntryId'",
])

# 3) Vehicle history/service card must honor Cars + Maintenance field visibility.
has_all('R90 vehicle service-card data boundary', r90_rel, [
    'erp_r90_vehicle_service_card', "'cars','maintenanceHistory'", "'maintenance','stockIssue'",
    "'maintenance','invoice'", "'maintenance','payments'", "'maintenance','maintenanceHistoryDetails'",
    "'maintenance','maintenanceSchedule'", "v_row:=v_row-'materialIssues'",
    "v_row:=v_row-'invoiceReferences'", "v_row:=v_row-'paymentReferences'-'payments'",
    "v_row:=v_row-'customDetails'", "'maintenanceHistory',case when v_can_history",
])

# 4) Cashbox definition reads/writes must use R90 filtered/action-guarded boundaries.
cashbox_legacy_revokes = [
    'erp_r42_list_cash_accounts(uuid)',
    'erp_r22_cloud_cash_account_balances(uuid)',
    'erp_r22_cloud_cash_ledger_reconciliation(uuid)',
    'erp_r42_save_cash_account(uuid,jsonb)',
    'erp_delete_cloud_cash_account(uuid,text)',
    'erp_r22_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text)',
    'erp_r22_post_cloud_cash_transaction(uuid,jsonb,boolean)',
    'erp_delete_cloud_cash_transaction(uuid,text)',
    'erp_delete_cloud_cash_transfer(uuid,text)',
]
for signature in cashbox_legacy_revokes:
    need(
        f'authenticated legacy cashbox endpoint not revoked: {signature}',
        re.search(rf'revoke\s+execute\s+on\s+function\s+public\.{re.escape(signature)}\s+from\s+authenticated', r90, re.I) is not None,
    )
for signature in [
    'erp_r90_list_cash_accounts(uuid)',
    'erp_r90_cash_account_balances(uuid)',
    'erp_r90_cash_ledger_reconciliation(uuid)',
    'erp_r90_save_cash_account(uuid,jsonb)',
    'erp_r90_delete_cash_account(uuid,text)',
    'erp_r90_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text)',
    'erp_r90_post_cash_transaction(uuid,jsonb,boolean)',
    'erp_r90_delete_cash_transaction(uuid,text)',
    'erp_r90_delete_cash_transfer(uuid,text)',
]:
    need(
        f'R90 cashbox endpoint not exposed to authenticated: {signature}',
        re.search(rf'grant\s+execute\s+on\s+function\s+public\.{re.escape(signature)}\s+to\s+authenticated\s*,\s*service_role', r90, re.I) is not None,
    )
has_all('cashbox account field filter', r90_rel, [
    'erp_r90_filter_cashbox_account', "when 'name' then 'name'", "when 'currency' then 'currency'",
    "when 'openingBalance' then 'openingBalance'", "when 'isActive' then 'isActive'",
    "when 'accountId' then 'ledgerAccount'", "when 'linkedCashAccountId' then 'linkedCashAccount'",
    "when 'createdAt' then 'auditMetadata'",
])
has_all('cashbox action enforcement', r90_rel, [
    "'cashbox',case when v_exists then 'account.edit' else 'account.create' end",
    "'cashbox','account.delete'", "'cashbox','transfer'", 'erp_r88_action_allowed',
])
has_all('cashbox transaction mutation enforcement', r90_rel, [
    'erp_r90_post_cash_transaction', "'cashbox','transaction.edit'",
    'erp_r90_delete_cash_transaction', "'cashbox','transaction.delete'",
    'erp_r90_delete_cash_transfer', "'cashbox','transfer.delete'",
    'erp_r22_post_cloud_cash_transaction', 'erp_delete_cloud_cash_transaction',
    'erp_delete_cloud_cash_transfer',
])
has_all('cashbox direct-table hardening', r90_rel, [
    'revoke all on table public.erp_cash_transfers from public,anon,authenticated',
    'revoke all on table public.erp_cash_account_links from public,anon,authenticated',
    "('erp_cash_accounts','cashbox','accounting.view')",
    "('erp_cash_transactions','cashbox','accounting.view')",
    "('erp_maintenance_orders','maintenance','maintenance.view')",
    "('erp_maintenance_parts','maintenance','maintenance.view')",
    "('erp_maintenance_payments','maintenance','maintenance.view')",
    "('erp_sales_orders_cloud','sales','sales.view')",
    "('erp_purchase_orders_cloud','purchases','purchases.view')",
    'as restrictive for select to authenticated',
    'erp_commercial_workflow_documents_r90_field_scope',
])

# 5) Repositories must call filtered R89/R90 endpoints, never revoked browser reads.
has_all('cashbox repository R90 boundary', 'lib/features/accounting/cashbox/repositories/cashbox_repository.dart', [
    'erp_r90_list_cash_accounts', 'erp_r90_save_cash_account', 'erp_r90_delete_cash_account',
    'erp_r90_cash_account_balances', 'erp_r90_cash_ledger_reconciliation', 'erp_r90_transfer_cloud_cash',
    'erp_r90_post_cash_transaction', 'erp_r90_delete_cash_transaction', 'erp_r90_delete_cash_transfer',
])
maint_repo = text('lib/features/maintenance/data/maintenance_repository.dart')
for token in [
    'erp_r90_get_maintenance_order_snapshot', 'erp_r89_maintenance_cost_reconciliation',
    'erp_r90_maintenance_material_issue_state', 'erp_r90_list_maintenance_payments',
    'erp_r90_vehicle_service_card',
]:
    need(f'maintenance repository missing secure endpoint {token}', token in maint_repo)
commercial_repo = text('lib/features/sales/workflow/repositories/commercial_order_details_repository.dart')
need('commercial repository does not use R89 secure snapshot', 'erp_r89_get_commercial_order_snapshot' in commercial_repo)
accounting_repo = text('lib/features/accounting/repositories/accounting_repository.dart')
need('accounting repository still bypasses R90 cash transaction delete guard',
     'erp_r90_delete_cash_transaction' in accounting_repo and 'erp_delete_cloud_cash_transaction' not in accounting_repo)
for forbidden in [
    'erp_r28_get_commercial_order_complete_details', 'erp_r57_commercial_reconciliation',
    'erp_r62_get_commercial_order_snapshot', 'erp_r64_get_maintenance_order_snapshot',
    'erp_r57_maintenance_cost_reconciliation', 'erp_r57_maintenance_material_issue_state',
    'erp_r88_list_maintenance_payments', 'erp_r88_vehicle_service_card',
    'erp_r42_list_cash_accounts', 'erp_r42_save_cash_account', 'erp_delete_cloud_cash_account',
    'erp_r22_cloud_cash_account_balances', 'erp_r22_cloud_cash_ledger_reconciliation',
    'erp_r22_transfer_cloud_cash', 'erp_r22_post_cloud_cash_transaction',
    'erp_delete_cloud_cash_transaction', 'erp_delete_cloud_cash_transfer',
]:
    occurrences = []
    for rel in [
        'lib/features/sales/workflow/repositories/commercial_order_details_repository.dart',
        'lib/features/maintenance/data/maintenance_repository.dart',
        'lib/features/accounting/cashbox/repositories/cashbox_repository.dart',
        'lib/features/accounting/repositories/accounting_repository.dart',
    ]:
        if forbidden in text(rel):
            occurrences.append(rel)
    need(f'browser repository still calls revoked legacy RPC {forbidden}: {occurrences}', not occurrences)

# 6) Granular permission catalog and UI visibility/action guards.
perm = text('lib/features/settings/access/models/permission_catalog.dart')
for code in [
    'cashbox.actions.restrict', 'cashbox.account.create', 'cashbox.account.edit',
    'cashbox.account.delete', 'cashbox.transfer', 'cashbox.transfer.delete',
    'cashbox.transaction.view', 'cashbox.transaction.edit', 'cashbox.transaction.delete',
    'cashbox.transaction.print',
    'maintenance.schedule.create', 'maintenance.schedule.update', 'maintenance.schedule.delete',
    'maintenance.schedule.assign_other', 'maintenance.schedule.convert',
    'maintenance.history_detail.edit',
]:
    need(f'missing Phase 11 granular permission {code}', code in perm)

has_all_compact('cashbox UI data/action visibility', 'lib/features/accounting/cashbox/pages/cashbox_page.dart', [
    "'account.create'", "'account.edit'", "_requireCashboxAction(", "'transfer'",
    "_securedCashboxField('documentNumber'", "_securedCashboxField('operationalDate'",
    "_securedCashboxField('transactionType'", "_securedCashboxField('amount'",
    "_securedCashboxField('currency'", "_securedCashboxField('counterAccount'",
    "_securedCashboxField('reference'", "_securedCashboxField('performedBy'",
    "_securedCashboxField('notes'", "_securedCashboxField('transactionStatus'",
    "'transaction.print'", "legacyPermission: 'accounting.view'",
    "final legacyPermission = type == 'receipt'",
])
cashbox_ui = text('lib/features/accounting/cashbox/pages/cashbox_page.dart')
need('cashbox compile regression: dead _actions remains', 'Widget _actions(' not in cashbox_ui)
need('cashbox compile regression: undefined account.id in no-arg _actions', not re.search(r'Widget\s+_actions\s*\(\s*\)[\s\S]{0,900}?account\.id', cashbox_ui))
# A duplicate literal borderRadius in a short BoxDecoration block was an R89 regression.
for match in re.finditer(r'BoxDecoration\s*\((.*?)\)\s*[,;]', cashbox_ui, re.S):
    body = match.group(1)
    if body.count('borderRadius:') > 1:
        errors.append('cashbox compile regression: duplicate borderRadius in BoxDecoration')
        break

has_all('vehicle scheduling/history UI action gates', 'lib/features/inventory/cars/pages/vehicle_service_card_page.dart', [
    'canCreateSchedule', 'canEditSchedule', 'canDeleteSchedule', 'canConvertSchedule',
    'canEditHistoryDetails', "'schedule.create'", "'schedule.update'",
    "'schedule.delete'", "'schedule.convert'", "'history_detail.edit'",
])

# 7) Existing R88/R89 functional requirements remain represented.
for required in [
    'tool/verify_r88_phase11.py', 'tool/verify_r89_phase11_completion.py',
    'supabase/migrations/20260819210000_r88_phase11_operational_financial_closure.sql',
    'supabase/migrations/20260820090000_r89_phase11_completion_closure.sql',
]:
    need(f'Phase 11 predecessor contract missing: {required}', (ROOT / required).exists())

# 8) Runtime gate + launch path must use the canonical R89-R94 runner.
need('R90 LOCAL runtime SQL missing', (ROOT / 'supabase/tests/verify_r90_phase11_runtime.sql').exists())
has_all('canonical R89-R94 LOCAL runtime runner', 'tool/run_r89_r92_local_runtime_tests.py', [
    'ensure_local_supabase_schema',
    'verify_r89_phase11_runtime.sql',
    'verify_r90_phase11_runtime.sql',
    'verify_r91_phase11_runtime.sql',
    'verify_r92_comprehensive_module_audit_runtime.sql',
    'verify_r93_purchase_receipt_single_action_runtime.sql',
    'verify_r93_restricted_user_runtime.sql',
    'verify_r94_legacy_endpoint_acl_runtime.sql',
    'R89-R94 LOCAL PostgreSQL runtime verification PASS',
])
run_web = text('tool/run_current_web.ps1')
need(
    'run_current_web does not gate R90 source verifier',
    'verify_r90_phase11_final_acceptance.py' in run_web,
)
need(
    'run_current_web does not use canonical R89-R94 LOCAL runtime runner',
    'run_r89_r92_local_runtime_tests.py' in run_web,
)
for legacy_runner in [
    'run_r89_local_runtime_test.ps1',
    'run_r90_local_runtime_test.ps1',
    'run_r91_local_runtime_test.ps1',
    'run_r92_local_runtime_test.ps1',
]:
    need(
        f'run_current_web still depends on legacy runtime runner {legacy_runner}',
        legacy_runner not in run_web,
    )

# 9) Project verifier should include current Phase 11 gates.
verify_project = text('tool/verify_project.py')
for verifier in ['verify_r88_phase11.py', 'verify_r89_phase11_completion.py', 'verify_r90_phase11_final_acceptance.py']:
    need(f'verify_project missing {verifier}', verifier in verify_project)

if errors:
    print(f'FAIL R90 Phase 11 final acceptance: {len(errors)} issue(s)')
    for error in errors:
        print(f'- {error}')
    raise SystemExit(1)

print('PASS R90 Phase 11 final acceptance')
print('  legacy Commercial/Maintenance detail bypasses are revoked for authenticated')
print('  payment-linked cashbox fields are cross-resource filtered')
print('  vehicle history/schedule payloads obey field visibility before reaching the browser')
print('  cashbox definitions/balances/reconciliation use R90 server-side field boundaries')
print('  cashbox create/edit/delete/transfer/transaction mutations use granular action guards')
print('  raw cash transfer/link tables and restricted direct JSON reads are fail-closed')
print('  Cashbox print/edit/delete and Vehicle Service UI action/data visibility gates are present')
print('  Phase 11 R88/R89 contracts remain in place and R90 is wired into verification/runtime startup')
