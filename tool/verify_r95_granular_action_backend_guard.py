from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260821044500_r95_granular_action_backend_guard.sql"
R49 = ROOT / "supabase/migrations/20260810090000_r49_focused_final_permission_runtime_closure.sql"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")
    print(f"PASS: {message}")


text = MIGRATION.read_text(encoding="utf-8")
r49 = R49.read_text(encoding="utf-8")

require(text.lstrip().lower().startswith("begin;"), "R95 migration is forward-only")
require(
    "create or replace function public.erp_r95_user_can_perform_action(" in text,
    "central backend action guard is defined",
)
require(
    "perform public.erp_active_company_context(p_company_id);" in text,
    "action guard validates active company context",
)
require(
    "if public.is_company_admin(p_company_id) then" in text,
    "company admin bypass remains explicit",
)

helper_start = text.index(
    "create or replace function public.erp_r95_user_can_perform_action("
)
helper_end = text.index(
    "revoke all on function public.erp_r95_user_can_perform_action", helper_start
)
helper = text[helper_start:helper_end]
restricted_index = helper.index(
    "if public.erp_cloud_user_has_permission(p_company_id,v_restriction) then"
)
granular_index = helper.index(
    "return public.erp_cloud_user_has_permission(p_company_id,v_granular);"
)
legacy_index = helper.index("foreach v_legacy in array")
require(
    restricted_index < granular_index < legacy_index,
    "restricted mode evaluates granular permission before legacy fallback",
)

expected = {
    "erp_r49_approve_sales_order": (
        "sales.actions.restrict",
        "sales.order.approve",
        "sales.approve",
        "erp_approve_cloud_sales_order",
    ),
    "erp_r49_approve_purchase_order": (
        "purchases.actions.restrict",
        "purchases.order.approve",
        "purchases.approve",
        "erp_approve_cloud_purchase_order",
    ),
    "erp_r49_create_sales_delivery": (
        "sales.actions.restrict",
        "sales.delivery.create",
        "sales.update",
        "erp_create_cloud_sales_delivery",
    ),
    "erp_r49_create_sales_delivery_multi": (
        "sales.actions.restrict",
        "sales.delivery.create",
        "sales.update",
        "erp_create_cloud_sales_delivery_multi",
    ),
    "erp_r49_create_purchase_receipt": (
        "purchases.actions.restrict",
        "purchases.receipt.create",
        "purchases.update",
        "erp_create_cloud_purchase_receipt",
    ),
    "erp_r49_create_purchase_receipt_multi": (
        "purchases.actions.restrict",
        "purchases.receipt.create",
        "purchases.update",
        "erp_create_cloud_purchase_receipt_multi",
    ),
}

for function_name, tokens in expected.items():
    marker = f"create or replace function public.{function_name}("
    require(marker in text, f"{function_name} is replaced forward-only in R95")
    start = text.index(marker)
    next_create = text.find("create or replace function public.", start + len(marker))
    body = text[start : next_create if next_create != -1 else len(text)]
    for token in tokens:
        require(token in body, f"{function_name} preserves {token}")

require(
    "erp_r49_require_active_warehouse" in text
    and "erp_r49_require_allocation_warehouses" in text,
    "R49 active-warehouse validation remains in logistics wrappers",
)
require(
    "erp_r49_approve_sales_order" in r49
    and "erp_r49_approve_purchase_order" in r49,
    "historical R49 migration remains present and untouched",
)
require(
    "security definer" in helper.lower() and "set search_path=public" in helper.lower(),
    "central action guard keeps fixed SECURITY DEFINER search_path",
)
require("notify pgrst,'reload schema';" in text, "PostgREST schema reload is requested")
print("R95 granular action backend guard PASS")
