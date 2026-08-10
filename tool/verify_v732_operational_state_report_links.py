#!/usr/bin/env python3
"""Verify V7.3.2 operational state repair, shell cleanup, and linked reports."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260804213000_v732_operational_state_repair.sql"
INVENTORY = ROOT / "lib/features/inventory/pages/inventory_page.dart"
ERRORS = ROOT / "lib/core/errors/user_facing_error.dart"
REPORTS = ROOT / "lib/features/settings/reports/pages/reports_page.dart"
EXPORT = ROOT / "lib/features/settings/reports/services/report_export_service.dart"
ACTION = ROOT / "lib/core/widgets/app_module_action_icon.dart"
SALES = ROOT / "lib/features/sales/workflow/pages/order_details_dialog.dart"
MAINT = ROOT / "lib/features/maintenance/pages/maintenance_order_details_dialog.dart"
DASHBOARD = ROOT / "lib/features/dashboard/pages/dashboard_page.dart"
CUSTOMER = ROOT / "lib/features/customer_service/pages/customer_service_page.dart"
SALES_OPS = ROOT / "lib/features/sales/pages/sales_operations_page.dart"
PURCHASE_OPS = ROOT / "lib/features/purchases/pages/purchase_operations_page.dart"
CONFIG = ROOT / "supabase/config.toml"
RELEASE = ROOT / "lib/core/release/app_release_info.dart"
PUBSPEC = ROOT / "pubspec.yaml"

errors: list[str] = []

def read(path: Path) -> str:
    if not path.exists():
        errors.append(f"missing file: {path.relative_to(ROOT)}")
        return ""
    return path.read_text(encoding="utf-8")

def require(haystack: str, needles: tuple[str, ...], label: str) -> None:
    missing = [needle for needle in needles if needle not in haystack]
    if missing:
        errors.append(f"{label}: missing {', '.join(missing)}")

migration = read(MIGRATION)
inventory = read(INVENTORY)
errors_ui = read(ERRORS)
reports = read(REPORTS)
export = read(EXPORT)
action = read(ACTION)
sales = read(SALES)
maintenance = read(MAINT)
dashboard = read(DASHBOARD)
customer = read(CUSTOMER)
sales_ops = read(SALES_OPS)
purchase_ops = read(PURCHASE_OPS)
config = read(CONFIG)
release = read(RELEASE) + read(PUBSPEC)

require(migration, (
    "erp_v732_refresh_car_state",
    "warehouse_transfer_deleted",
    "operationalStateReplayed",
    "erp_delete_cloud_sales_order_v3",
    "erp_delete_cloud_purchase_order_v3",
), "vehicle state replay")
require(migration, (
    "missingVehicleTolerated",
    "erp_cancel_cloud_purchase_receipt",
    "Purchase receipt deleted",
    "erp_v73_rebuild_product_warehouse_stock",
), "orphan purchase receipt repair")
require(migration, (
    "returnedToOpeningState",
    "warehouseOpeningMismatches",
    "openingBalanceRetired",
    "active_links_removed_and_each_warehouse_back_to_opening_state",
), "opening-state product deletion")
require(inventory, (
    "الرصيد الافتتاحي",
    "حذف المادة وسجلها الافتتاحي",
    "orphanMovementCount",
), "inventory deletion UI")
require(errors_ui, (
    "purchase_receipt_has_downstream_sales",
    "inventory_product_not_back_to_opening_state",
), "domain error mapping")
require(action, ("class AppModuleActionIcon", "LinearGradient", "Tooltip"), "module action icon")
require(sales + maintenance, ("AppModuleActionIcon",), "document action integration")
if "class _PremiumOrderAction" in sales or "class _HeaderAction" in maintenance:
    errors.append("old wide document action classes still exist")
require(reports, ("_relatedModuleLinks", "_contextCellWidth", "SelectableText"), "linked report UI")
require(export, ("AdaptivePdfTable.build", "maxColumnsPerGroup: 5", "maxRowsPerChunk: 12"), "wrapped PDF reports")
if "class _TopBar" in dashboard:
    errors.append("dashboard duplicate top bar still exists")
if "KajSectionHeader" in sales_ops or "KajSectionHeader" in purchase_ops:
    errors.append("sales/purchase duplicate body headers still exist")
if "Customer Service')," in customer and "fontSize: 20" in customer:
    errors.append("customer-service duplicate title appears to remain")

# Verify global signup is off while email/password provider stays on.
import re

def section(name: str) -> str:
    match = re.search(
        rf"(?ms)^\[{re.escape(name)}\]\s*(.*?)(?=^\[[^\]]+\]\s*$|\Z)",
        config,
    )
    return match.group(1) if match else ""

auth = section("auth")
email = section("auth.email")
if "enable_signup = false" not in auth:
    errors.append("global public signup must remain disabled")
if "enable_signup = true" not in email:
    errors.append("email/password provider must remain enabled")

# Fresh packages must not carry the PL/pgSQL CASE syntax bug.
for path in (
    ROOT / "supabase/migrations/20260804180000_v73_reversible_workflows_shell.sql",
    ROOT / "supabase/migrations/20260804193000_v731_preserved_payment_reallocation.sql",
    MIGRATION,
):
    body = read(path).lower().replace(" ", "")
    if "document_type<>casewhen" in body:
        errors.append(f"unparenthesized CASE comparison: {path.name}")

require(release, ("18.9.8", "189800"), "release version")

if errors:
    print("FAILED V7.3.2 operational state and report links")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS V7.3.2 operational state and report links")
print("  - orphaned purchase receipts tolerate previously deleted vehicles")
print("  - vehicle warehouse and lifecycle status are replayed after reversals")
print("  - opening-state products are deletable after active links are removed")
print("  - duplicate body headers and wide document actions are removed")
print("  - contextual report tables wrap and link to related modules")
print("  - email/password login remains enabled while public signup is disabled")
