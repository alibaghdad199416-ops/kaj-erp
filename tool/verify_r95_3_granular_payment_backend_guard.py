from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260821053500_r95_3_granular_payment_backend_guard.sql"
V757 = ROOT / "supabase/migrations/20260806214500_v757_multicurrency_payment_chain_hardening.sql"
V762 = ROOT / "supabase/migrations/20260807030000_v762_workflow_posting_payment_integrity.sql"
V2300 = ROOT / "supabase/migrations/20260807180000_v2300_atomic_workflow_enterprise_audit.sql"
SALES = ROOT / "lib/features/sales/workflow/pages/sales_workflow_page.dart"
PURCHASES = ROOT / "lib/features/purchases/pages/purchase_workflow_page.dart"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


def function_block(text: str, name: str) -> str:
    marker = f"create or replace function public.{name}("
    start = text.index(marker)
    next_create = text.find("create or replace function public.", start + len(marker))
    if next_create == -1:
        next_create = text.find("commit;", start)
    return text[start:next_create if next_create != -1 else len(text)]


text = MIGRATION.read_text(encoding="utf-8")
v757 = V757.read_text(encoding="utf-8")
v762 = V762.read_text(encoding="utf-8")
v2300 = V2300.read_text(encoding="utf-8")
sales = SALES.read_text(encoding="utf-8")
purchases = PURCHASES.read_text(encoding="utf-8")

require(text.lstrip().lower().startswith("begin;"), "R95.3 migration is forward-only")
require(text.rstrip().endswith("commit;"), "R95.3 commits atomically")

for token in (
    "sales.actions.restrict",
    "sales.payment",
    "purchases.actions.restrict",
    "purchases.payment",
):
    require(token in text, f"R95.3 contains {token}")

require(
    "'payment' => const <String>['cashbox.receipt']" in sales,
    "Sales UI legacy payment fallback is cashbox.receipt",
)
require(
    "'payment' => const <String>['cashbox.payment']" in purchases,
    "Purchase UI legacy payment fallback is cashbox.payment",
)

old_guard = """perform public.erp_require_any_cloud_permission(
    p_company_id,case when p_module='purchases' then array['cashbox.payment'] else array['cashbox.receipt'] end);"""
require(old_guard in v757, "V757 historical payment guard is present")
require(old_guard in text, "R95.3 targets the exact V757 payment guard")
require(
    "pg_get_functiondef(" in text
    and "'public.erp_execute_secure_linked_payment_v1(uuid,text,uuid,uuid,text,text,jsonb)'::regprocedure" in text,
    "secure payment engine is patched in place",
)
require(
    "r95_3_secure_payment_guard_signature_changed" in text
    and "r95_3_secure_payment_guard_ambiguous" in text,
    "secure payment guard patch fails closed on source drift",
)

v762_new = function_block(text, "erp_v762_apply_workflow_payment")
helper_index = v762_new.index("erp_r95_user_can_perform_action")
engine_index = v762_new.index("erp_apply_cloud_workflow_invoice_payment_batch")
require(helper_index < engine_index, "V762 authorizes before entering payment engine")
for token in (
    "payment_requires_approved_invoice",
    "payment_requires_posted_invoice",
    "erp_v762_assert_posted_journal_balanced",
    "erp_v73_recompute_commercial_order_status",
):
    require(token in v762_new, f"V762 preserves payment integrity contract: {token}")

v2300_new = function_block(text, "erp_v2300_pay_cloud_workflow_invoice_batch")
require(
    "erp_r95_user_can_perform_action" in v2300_new,
    "V2300 payment entry point uses granular action guard",
)
require(
    v2300_new.index("erp_r95_user_can_perform_action")
    < v2300_new.index("erp_v2300_validate_payment_dates"),
    "V2300 authorizes before payment validation/delegation",
)
require(
    "erp_v762_apply_workflow_payment" in v2300_new,
    "V2300 still delegates to V762 integrity surface",
)

require(
    "grant execute on function public.erp_execute_secure_linked_payment_v1(uuid,text,uuid,uuid,text,text,jsonb) to authenticated,service_role;"
    in v757,
    "V757 secure payment engine was historically browser-callable",
)
require(
    "grant execute on function public.erp_apply_cloud_workflow_invoice_payment_batch(uuid,uuid,text,jsonb) to authenticated,service_role;"
    in v757,
    "V757 raw batch engine was historically browser-callable",
)
require(
    "from public,anon,authenticated;" in text
    and "erp_execute_secure_linked_payment_v1" in text
    and "erp_apply_cloud_workflow_invoice_payment_batch" in text,
    "R95.3 removes authenticated access to raw payment engines",
)

require(
    "erp_v762_apply_workflow_payment" in v762
    and "erp_apply_cloud_workflow_invoice_payment_batch" in v762,
    "historical compatibility payment functions converge through V762",
)
require(
    "erp_v2300_validate_payment_dates" in v2300
    and "erp_v762_apply_workflow_payment" in v2300,
    "V2300 operational-date contract is preserved",
)
require("notify pgrst,'reload schema';" in text, "PostgREST schema reload is requested")

print("R95.3 granular payment backend guard PASS")
