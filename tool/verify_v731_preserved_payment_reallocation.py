#!/usr/bin/env python3
"""Verify V7.3.1 preserved-payment accounting semantics."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260804193000_v731_preserved_payment_reallocation.sql"
ERRORS_UI = ROOT / "lib/core/errors/user_facing_error.dart"
SALES_DETAILS = ROOT / "lib/features/sales/workflow/pages/order_details_dialog.dart"
MAINT_DETAILS = ROOT / "lib/features/maintenance/pages/maintenance_order_details_dialog.dart"
MAINT_PAGE = ROOT / "lib/features/maintenance/pages/maintenance_page.dart"
RELEASE = ROOT / "lib/core/release/app_release_info.dart"
PUBSPEC = ROOT / "pubspec.yaml"

errors: list[str] = []

def text(path: Path) -> str:
    if not path.exists():
        errors.append(f"missing file: {path.relative_to(ROOT)}")
        return ""
    return path.read_text(encoding="utf-8")

def require(haystack: str, needles: tuple[str, ...], label: str) -> None:
    missing = [needle for needle in needles if needle not in haystack]
    if missing:
        errors.append(f"{label}: missing {', '.join(missing)}")

migration = text(MIGRATION)
errors_ui = text(ERRORS_UI)
sales = text(SALES_DETAILS)
maintenance = text(MAINT_DETAILS) + text(MAINT_PAGE)
release = text(RELEASE) + text(PUBSPEC)

require(
    migration,
    (
        "erp_partner_advance_allocations",
        "erp_v731_advance_allocated_amount",
        "erp_v731_refresh_advance_cache",
        "erp_v731_release_advance_allocations",
    ),
    "normalized advance allocation ledger",
)
require(
    migration,
    (
        "erp_v731_apply_advance_to_commercial_invoice",
        "same_partner_same_currency",
        "preserved_partner_balance",
        "partnerAdvanceApplied",
    ),
    "commercial automatic allocation",
)
require(
    migration,
    (
        "erp_v731_detach_maintenance_payments",
        "erp_v731_apply_advance_to_maintenance_order",
        "is_advance_application",
        "advance_allocation_id",
    ),
    "maintenance preserved payment allocation",
)
require(
    migration,
    (
        "paymentsRequiredDeleted',false",
        "paymentPolicy','partner_balance_preserved",
        "payment_is_cashbox_owned",
    ),
    "payment independence from operational deletion",
)
require(
    migration,
    (
        "erp_v731_sync_deleted_advance_cash",
        "Source cash payment deleted",
        "erp_delete_cloud_accounting_entry",
    ),
    "cashbox deletion reverses allocations",
)
require(
    migration,
    (
        "create or replace function public.erp_list_partner_unapplied_payments",
        "original_amount",
        "allocated_amount",
        "advance_has_active_allocations",
    ),
    "accounting balance visibility and edit protection",
)
require(
    sales,
    (
        "تبقى الدفعات المالية في حساب العميل أو المورد كرصيد غير مخصص",
        "automatically considered for a later approved invoice",
    ),
    "sales and purchase user messaging",
)
require(
    maintenance,
    (
        "تبقى الدفعات كرصيد غير مخصص للعميل",
        "تُستخدم تلقائيًا في أمر لاحق",
    ),
    "maintenance user messaging",
)
require(
    errors_ui,
    (
        "payment_is_cashbox_owned",
        "advance_has_active_allocations",
        "حذف الأمر أو الفاتورة يُبقيها رصيدًا للطرف",
    ),
    "domain error messages",
)
require(release, ("18.9.8", "189800"), "release version")

# The V7.3.1 override must not block order/invoice deletion on active payments.
for function_name in (
    "erp_delete_cloud_sales_order_v3",
    "erp_delete_cloud_purchase_order_v3",
    "erp_delete_cloud_maintenance_order_v3",
):
    start = migration.find(f"create or replace function public.{function_name}")
    if start < 0:
        continue
    end = migration.find("\n$$;", start)
    block = migration[start:end]
    if "delete_payment_from_cashbox_first" in block:
        errors.append(f"{function_name}: still blocks deletion on payments")

if errors:
    print("FAILED V7.3.1 preserved payment reallocation verification")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS V7.3.1 preserved payment reallocation")
print("  - operational reversal preserves cash payments as partner balances")
print("  - later approved invoices consume available balances by party/currency")
print("  - allocation deletion restores available balance")
print("  - deleting the cash transaction reverses every active allocation")
print("  - maintenance and commercial workflows share the accounting rule")
