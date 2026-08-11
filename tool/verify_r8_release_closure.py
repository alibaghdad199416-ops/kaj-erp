from __future__ import annotations
from pathlib import Path
import hashlib
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding='utf-8')

def normalized_config_digest(rel: str) -> str:
    # Git may materialize tracked text files with LF or CRLF depending on the
    # runner/worktree. Preserve configuration content while ignoring only
    # newline encoding so the same release guard works on Windows and Linux.
    payload = (ROOT / rel).read_bytes().replace(b'\r\n', b'\n')
    return hashlib.sha256(payload).hexdigest()

expected_hashes = {
    'dart_defines.json': '1b0cbea9cf00177e68700f226832d17a083762a04fd271d9ca8b75d36aafb3c7',
    '.firebaserc': 'f56fa212a1a202d098575515c3bf7e3210d8c7b9d74865c90e6fa6e5c0f2e4a8',
    'firebase.json': 'ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a',
}
for rel, expected in expected_hashes.items():
    actual = normalized_config_digest(rel)
    assert actual == expected, f'configuration changed: {rel}: {actual}'

# Recycle-bin spreadsheet must expose explicit deletion identity and use typed XLSX cells.
recycle = read('lib/features/settings/recycle_bin/pages/recycle_bin_page.dart')
assert "'حُذف بواسطة'" in recycle and "'Deleted by'" in recycle
excel = read('lib/core/exporting/excel_workbook_presentation.dart')
for marker in ('IntCellValue(', 'DoubleCellValue(', 'BoolCellValue(', 'DateTimeCellValue.fromDateTime'):
    assert marker in excel, marker
assert 'ExportValueType' in excel
export_service = read('lib/core/exporting/excel_export_service.dart')
assert 'ExcelWorkbookPresentation.typedValue' in export_service

# Shared design-system text must flow through application localization/number formatting.
ui_files = [
    'lib/design_system/kaj_completion_components.dart',
    'lib/design_system/kaj_relationship_stage5_components.dart',
    'lib/design_system/kaj_universal_components.dart',
    'lib/design_system/kaj_finance_stage7_components.dart',
    'lib/design_system/kaj_shell_components.dart',
    'lib/design_system/kaj_entry_components.dart',
]
violations: list[str] = []
for rel in ui_files:
    text = read(rel)
    if re.search(r'(?<![A-Za-z0-9_.])Text\(', text):
        violations.append(f'{rel}:Text')
    if re.search(r'(?<![A-Za-z0-9_.])SelectableText\(', text):
        violations.append(f'{rel}:SelectableText')
assert not violations, '\n'.join(violations)

# Current transfer call chain must route through operational-date validation to the hardened V5 posting.
repo = read('lib/features/accounting/cashbox/repositories/cashbox_repository.dart')
r9_finance = read('supabase/migrations/20260807240000_r9_finance_read_write_field_enforcement.sql')
v2300 = read('supabase/migrations/20260807180000_v2300_atomic_workflow_enterprise_audit.sql')
v5 = read('supabase/migrations/20260806193000_v755_fx_transfer_unique_vouchers_auth_preferences.sql')
r22 = read('supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql')
assert "'p_transfer_date': transferDate.toUtc().toIso8601String()" in repo
if "'erp_r22_transfer_cloud_cash'" in repo:
    assert 'create or replace function public.erp_r22_transfer_cloud_cash' in r22
    assert "erp_validate_operational_date(p_company_id,'accounting',p_transfer_date)" in r22
    assert "'cashTransactionId'" in r22 and "'cashAccountId'" in r22
    assert 'erp_v762_assert_posted_journal_balanced' in r22
else:
    assert "'erp_r9_transfer_cloud_cash'" in repo
    assert 'erp_r9_transfer_cloud_cash' in r9_finance and 'erp_v2300_transfer_cloud_cash' in r9_finance
    assert 'erp_validate_operational_date' in v2300 and 'erp_transfer_cloud_cash_v5(' in v2300
    for marker in ('cashboxes_not_linked_for_fx', "'totalDebit',p_source_amount,'totalCredit',p_source_amount", "'totalDebit',p_target_amount,'totalCredit',p_target_amount"):
        assert marker in v5, marker

# Root runtime/accounting closure must remain installed.
assert (ROOT / 'supabase/migrations/20260807213000_v2302_runtime_accounting_root_closure.sql').exists()

# Delivery cleanliness is verified separately by verify:package before dependency installation.

# CI must execute real Flutter compile gates on a compatible SDK outside this constrained environment.
workflow = read('.github/workflows/quality-gates.yml')
for marker in ("flutter-version: '3.44.8'", 'npm run analyze', 'npm run test', 'npm run build:web'):
    assert marker in workflow, marker
assert 'npm run verify:all' in workflow or 'npm run verify:workspace' in workflow, 'workspace verifier missing from CI'

# Field-policy engine exists, but complete UI field wiring is deliberately NOT certified here.
engine = read('lib/core/security/access_policy_engine.dart')
for marker in ('hiddenFields', 'readOnlyFields', 'filterReadableFields', 'filterWritableFields'):
    assert marker in engine, marker

print('PASS R8 release closure verification')
print('- Supabase/Firebase configuration hashes unchanged')
print('- typed XLSX export and explicit recycle-bin deletion identity verified')
print('- shared design-system text uses AppText/AppSelectableText localization layer')
print('- hardened operational-date FX cash transfer chain verified')
print('- delivery cleanliness is delegated to verify:package; CI compile gates are present')
print('NOTICE: exhaustive per-field UI permission wiring is not certified by this verifier.')
