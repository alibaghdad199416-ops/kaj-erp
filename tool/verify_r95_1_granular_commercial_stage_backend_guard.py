from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260821044900_r95_1_granular_commercial_stage_backend_guard.sql"
R95 = ROOT / "supabase/migrations/20260821044500_r95_granular_action_backend_guard.sql"
V736 = ROOT / "supabase/migrations/20260805223000_v736_invoice_owned_accounting_workflow_ui.sql"
V758 = ROOT / "supabase/migrations/20260806230000_v758_invoice_draft_csp_runtime.sql"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


text = MIGRATION.read_text(encoding="utf-8")
r95 = R95.read_text(encoding="utf-8")
v736 = V736.read_text(encoding="utf-8")
v758 = V758.read_text(encoding="utf-8")

require(text.lstrip().lower().startswith("begin;"), "R95.1 is a forward-only migration")
require(
    "create or replace function public.erp_r95_user_can_perform_action(" in r95,
    "R95.1 reuses the canonical R95 action helper",
)

expected = {
    "erp_approve_cloud_purchase_receipt": (
        "purchases.actions.restrict",
        "purchases.receipt.approve",
        "array['purchases.approve','purchases.update','purchases.create']",
    ),
    "erp_approve_cloud_sales_delivery": (
        "sales.actions.restrict",
        "sales.delivery.approve",
        "array['sales.approve','sales.update','sales.create']",
    ),
    "erp_create_cloud_sales_workflow_invoice": (
        "sales.actions.restrict",
        "sales.invoice.create",
        "array['sales.create','sales.update','sales.approve']",
    ),
    "erp_create_cloud_purchase_workflow_invoice": (
        "purchases.actions.restrict",
        "purchases.invoice.create",
        "array['purchases.create','purchases.update','purchases.approve']",
    ),
}

for function_name, tokens in expected.items():
    marker = f"create or replace function public.{function_name}("
    require(marker in text, f"{function_name} is replaced in R95.1")
    start = text.index(marker)
    next_create = text.find("create or replace function public.", start + len(marker))
    body = text[start : next_create if next_create != -1 else len(text)]
    require(
        "erp_r95_user_can_perform_action" in body,
        f"{function_name} delegates authorization to R95",
    )
    require(
        "erp_require_any_cloud_permission" not in body,
        f"{function_name} no longer re-imposes broad permission arrays",
    )
    for token in tokens:
        require(token in body, f"{function_name} preserves {token}")

require(
    "erp_validate_commercial_warehouse_allocations" in text
    and "erp_inventory_insert_movement" in text
    and "inventoryPostedAt" in text,
    "logistics approval preserves canonical quantity/location posting",
)
require(
    "valuationPendingInvoice" in text and "accountingOwner','invoice" in text,
    "logistics approval keeps valuation/accounting owned by invoice",
)
require(
    text.count("pg_advisory_xact_lock") == 2,
    "both invoice draft creators preserve duplicate-prevention advisory locks",
)
require(
    text.count("erp_v758_active_logistics") == 2,
    "both invoice draft creators preserve V758 approved-logistics resolution",
)
require(
    text.count("erp_v749_prepare_order_invoice_accounts") == 2,
    "both invoice draft creators preserve resilient account preflight",
)
require(
    "accountPreflightWarning" in text,
    "invoice draft creation preserves non-blocking account preflight warning",
)
require(
    "erp_r22_approve_workflow_invoice" not in text,
    "R95.1 intentionally does not partially rewrite the invoice-posting engine",
)
require(
    "perform public.erp_require_any_cloud_permission(p_company_id,array['purchases.approve','purchases.update','purchases.create']);" in v736
    and "perform public.erp_require_any_cloud_permission(p_company_id,array['sales.approve','sales.update','sales.create']);" in v736,
    "R95.1 closes the proven V736 broad logistics authorization boundary",
)
require(
    "array['sales.create','sales.update','sales.approve']" in v758
    and "array['purchases.create','purchases.update','purchases.approve']" in v758,
    "R95.1 closes the proven V758 broad invoice-create authorization boundary",
)
require("notify pgrst,'reload schema';" in text, "PostgREST schema reload is requested")
require(text.rstrip().endswith("commit;"), "R95.1 commits atomically")
print("R95.1 granular commercial stage backend guard PASS")
