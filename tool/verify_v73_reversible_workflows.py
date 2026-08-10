#!/usr/bin/env python3
"""Verify V7.3 reversible workflows, independent order components, and shell cleanup."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing required file: {relative}")
        return ""
    return path.read_text(encoding="utf-8")


def require(source: str, tokens: tuple[str, ...], label: str) -> None:
    missing = [token for token in tokens if token not in source]
    if missing:
        errors.append(f"{label}: missing {', '.join(repr(item) for item in missing)}")


migration = read("supabase/migrations/20260804180000_v73_reversible_workflows_shell.sql")
sales_repo = read("lib/features/sales/workflow/repositories/sales_workflow_repository.dart")
purchase_repo = read("lib/features/purchases/repositories/purchase_workflow_repository.dart")
maintenance_repo = read("lib/features/maintenance/data/maintenance_repository.dart")
sales_details = read("lib/features/sales/workflow/pages/order_details_dialog.dart")
maintenance_details = read("lib/features/maintenance/pages/maintenance_order_details_dialog.dart")
maintenance_page = read("lib/features/maintenance/pages/maintenance_page.dart")
top_bar = read("lib/core/widgets/app_workspace_top_bar.dart")
side_bar = read("lib/core/widgets/app_top_navigation.dart")
module_shell = read("lib/core/widgets/app_module_shell.dart")
errors_ui = read("lib/core/errors/user_facing_error.dart")
recycle_model = read("lib/features/settings/recycle_bin/models/recycle_bin_item.dart")
recycle_page = read("lib/features/settings/recycle_bin/pages/recycle_bin_page.dart")
release = read("lib/core/release/app_release_info.dart")
pubspec = read("pubspec.yaml")

require(
    migration,
    (
        "erp_delete_car_warehouse_transfer",
        "v_car_exists",
        "linksRebuilt",
        "Purchase order linked cleanup",
    ),
    "vehicle transfer/orphan purchase recovery",
)
require(
    migration,
    (
        "erp_delete_inventory_warehouse_transfer",
        "erp_v73_rebuild_product_warehouse_stock",
        "sourceAndDestinationInOneDocument",
        "warehouse_history_would_be_negative",
    ),
    "unified reversible product transfer",
)
require(
    migration,
    (
        "erp_delete_inventory_product",
        "delete_active_inventory_links_first",
        "inventory_history_not_back_to_original",
        "openingBalanceRetired",
    ),
    "product deletion after returning to opening state",
)
require(
    migration,
    (
        "erp_delete_cloud_sales_order_v3",
        "erp_delete_cloud_purchase_order_v3",
        "erp_delete_cloud_maintenance_order_v3",
        "delete_payment_from_cashbox_first",
    ),
    "full reversible order deletion",
)
require(
    migration,
    (
        "erp_manage_commercial_order_component",
        "erp_manage_maintenance_order_component",
        "'logistics'",
        "'invoice'",
        "'payment'",
        "'approve'",
        "'delete'",
    ),
    "independent order component operations",
)
require(
    migration,
    (
        "erp_record_cloud_maintenance_payment",
        "maintenance_payment",
        "erp_cash_transactions",
        "journalEntryId",
        "erp_v73_sync_deleted_maintenance_cash_payment",
    ),
    "maintenance payment cashbox ownership",
)
require(
    migration,
    (
        "erp_delete_cloud_accounting_entry",
        "Delete orphaned accounting entry",
        "erp_delete_cloud_cash_transaction",
    ),
    "complete accounting entry deletion routing",
)
require(
    migration,
    (
        "deleted_by text",
        "left join public.profiles",
        "erp_recycle_bin_purge_by_archive",
        "integrityTombstonesRetained",
        "Backfill legacy soft-deleted records",
    ),
    "complete recycle bin purge and deleting-user metadata",
)

if not (("erp_delete_cloud_sales_order_v4" in sales_repo) or ("erp_delete_cloud_sales_order_v3" in sales_repo)):
    errors.append("sales repository: missing latest reversible sales deletion wrapper")
require(sales_repo, ("erp_manage_commercial_order_component",), "sales repository")
require(purchase_repo, ("erp_delete_cloud_purchase_order_v3", "erp_manage_commercial_order_component"), "purchase repository")
require(maintenance_repo, ("erp_delete_cloud_maintenance_order_v3", "erp_manage_maintenance_order_component"), "maintenance repository")

require(
    sales_details,
    (
        "AppModuleActionIcon",
        "_componentActions",
        "_paymentCashboxAction",
        "Delete from cashbox",
        "picture_as_pdf_outlined",
    ),
    "sales and purchase premium/component UI",
)
require(
    maintenance_details + maintenance_page,
    (
        "MaintenanceOrderDetailsDialog",
        "Manage order stages",
        "order_approval",
        "componentType: 'stock'",
        "componentType: 'invoice'",
        "AppModuleActionIcon",
        "picture_as_pdf_outlined",
    ),
    "maintenance premium/component UI",
)
require(
    top_bar,
    (
        "_ModuleIdentity(title: title, icon: _routeIcon(currentRoute))",
        "_ConnectionIndicator",
        "_RefreshWorkspaceButton",
        "Icons.logout_rounded",
        "Icons.currency_exchange_rounded",
    ),
    "top workspace bar",
)
if "_SideUserCard" in side_bar or "_queryController" in side_bar:
    errors.append("sidebar cleanup: legacy user card or sidebar search remains")
if "_RuntimeReadinessBanner" in module_shell:
    errors.append("module shell cleanup: duplicate readiness banner remains")
require(errors_ui, ("delete_payment_from_cashbox_first", "inventory_history_not_back_to_original"), "domain error messages")
require(recycle_model + recycle_page, ("deletedBy", "Deleted by", "حُذف بواسطة"), "recycle deleting-user UI")
require(release + pubspec, ("18.9.8", "189800"), "release version")

if errors:
    print("FAILED V7.3 reversible workflow verification")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS V7.3 reversible workflows and shell cleanup")
print("  - vehicle and product transfers are reversible and rebuild links")
print("  - orphaned purchased-car transfer chains can be removed")
print("  - products return to a deletable opening state after linked reversals")
print("  - sales, purchase, and maintenance components are independently managed")
print("  - maintenance payments are cashbox-owned")
print("  - accounting entries route deletion through their source")
print("  - recycle rows include deleting user and exact archive purge")
print("  - sidebar duplication is removed and top bar owns runtime actions")
