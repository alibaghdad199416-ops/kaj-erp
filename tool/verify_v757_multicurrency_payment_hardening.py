from pathlib import Path
import re
root=Path(__file__).resolve().parents[1]
m=(root/'supabase/migrations/20260806214500_v757_multicurrency_payment_chain_hardening.sql').read_text(encoding='utf-8')
checks=[
"cashboxes_must_be_bidirectionally_linked_for_fx",
"paymentKey",
"idempotent",
"settlement_mode_requires_dedicated_adjustment_workflow",
"paymentChainVersion','v757",
]
for c in checks:
    assert c in m, c
ui=(root/'lib/core/finance/invoice_payment_batch_dialog.dart').read_text(encoding='utf-8')
assert "'paymentKey': paymentKey" in ui
assert "const Uuid().v4()" in ui
od=(root/'lib/features/sales/workflow/pages/order_details_dialog.dart').read_text(encoding='utf-8')
assert re.search(r"\.where\(\s*\(row\)\s*=>\s*\(row\['currency'\]", od) is None
assert "listSettlementAccounts" in od
for f in [
'lib/features/sales/workflow/pages/sales_workflow_page.dart',
'lib/features/purchases/pages/purchase_workflow_page.dart',
'lib/features/maintenance/pages/maintenance_page.dart']:
    t=(root/f).read_text(encoding='utf-8')
    assert 'settlementAccounts = results[1]' in t, f
print('PASS V7.5.7 hardened multi-currency payment chain')
