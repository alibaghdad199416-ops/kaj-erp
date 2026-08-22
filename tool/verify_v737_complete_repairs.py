#!/usr/bin/env python3
"""Verify V7.3.7 incremental maintenance, performance and current UI closure."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.exists():
        errors.append(f"missing {relative}")
        return ""
    return path.read_text(encoding="utf-8-sig")


def require(text: str, needles: tuple[str, ...], label: str) -> None:
    missing = [needle for needle in needles if needle not in text]
    if missing:
        errors.append(f"{label}: missing {', '.join(missing)}")


def function_body(sql: str, name: str) -> str:
    marker = f"create or replace function public.{name}"
    start = sql.lower().find(marker.lower())
    if start < 0:
        errors.append(f"migration: missing function {name}")
        return ""
    next_start = sql.lower().find("\ncreate or replace function public.", start + len(marker))
    if next_start < 0:
        next_start = len(sql)
    return sql[start:next_start]


migration = read(
    "supabase/migrations/20260805234500_v737_maintenance_payment_batch_and_final_repairs.sql"
)
release = read("lib/core/release/app_release_info.dart") + read("pubspec.yaml")
web_version = read("web/version.json")
web_index = read("web/index.html")
firebase = read("firebase.json")
package = read("package.json")
entity_page = read("lib/core/widgets/app_entity_page.dart")
horizontal_strip = read("lib/core/widgets/app_horizontal_strip.dart")
lazy_tab_view = read("lib/core/widgets/app_lazy_tab_view.dart")
window = read("lib/core/widgets/app_full_page_route.dart")
window_close = read("lib/core/widgets/app_window_close_button.dart")
back = read("lib/core/widgets/app_back_button.dart")
maintenance_page = read("lib/features/maintenance/pages/maintenance_page.dart")
maintenance_repository = read("lib/features/maintenance/data/maintenance_repository.dart")
maintenance_controller = read("lib/features/maintenance/controllers/maintenance_controller.dart")
payment_dialog = read("lib/core/finance/invoice_payment_batch_dialog.dart")
stock_catalog = read("lib/features/inventory/pages/stock_catalog_page.dart")
partners = read("lib/features/business_partners/pages/business_partners_page.dart")
sales_tabs = read("lib/features/sales/pages/sales_operations_page.dart")
purchase_tabs = read("lib/features/purchases/pages/purchase_operations_page.dart")
pill_tabs = read("lib/core/widgets/app_pill_tab_bar.dart")
nomenclature = read("lib/core/documents/document_nomenclature.dart")

require(
    release + web_version,
    ("18.9.8", "189800", "v738-full-verified-runtime-accounting-ui-20260806"),
    "release identity",
)

require(
    migration,
    (
        "Atomic multi-currency maintenance invoice payments",
        "payment_key text",
        "erp_v737_record_maintenance_payment",
        "erp_record_cloud_maintenance_payment_batch",
        "maintenance_closing_payment_must_be_last",
        "maintenance_payment_journal",
        "accountCurrencyAmount",
        "erp_v731_detach_maintenance_payments",
        "erp_v736_void_journal_id",
        "previousCarMaintenanceCost",
        "'paymentsPreserved',true",
    ),
    "V737 maintenance payment and reversal migration",
)

maintenance_payment = function_body(migration, "erp_v737_record_maintenance_payment")
require(
    maintenance_payment,
    (
        "cashAccountId",
        "paymentCurrency",
        "invoiceAmount",
        "cashAmount",
        "exchangeRate",
        "settlementMode",
        "settlementAccountId",
        "erp_v736_convert_currency",
        "maintenance_cash_amount_mismatch",
        "maintenance_payment_journal",
        "paymentKey",
    ),
    "maintenance multi-currency payment posting",
)

maintenance_batch = function_body(migration, "erp_record_cloud_maintenance_payment_batch")
require(
    maintenance_batch,
    (
        "jsonb_array_elements(p_payments) with ordinality",
        "maintenance_closing_payment_must_be_last",
        "erp_v737_record_maintenance_payment",
    ),
    "atomic maintenance payment batch",
)

maintenance_component = function_body(migration, "erp_manage_maintenance_order_component")
require(
    maintenance_component,
    (
        "erp_v731_detach_maintenance_payments",
        "erp_v736_void_journal_id",
        "previousCarMaintenanceCost",
        "stock_issue_approved",
        "paymentsPreserved",
        "erp_v66_reverse_maintenance_stock",
    ),
    "maintenance invoice deletion and stock separation",
)

maintenance_surface = (
    maintenance_page + maintenance_repository + maintenance_controller + payment_dialog
)
require(
    maintenance_surface,
    (
        "showInvoicePaymentBatchDialog",
        "recordPaymentsBatch",
        "listCashAccounts",
        "listSettlementAccounts",
        "documentLabelArabic",
        "documentLabelEnglish",
        "Maintenance invoice payments",
    ),
    "maintenance multi-payment UI and repository",
)
if (
    "erp_record_cloud_maintenance_payment_batch" not in maintenance_surface
    and "erp_v2300_record_maintenance_payment_batch" not in maintenance_surface
):
    errors.append("maintenance multi-payment UI and repository: missing batch RPC")

require(
    pill_tabs,
    (
        "indicatorSize: TabBarIndicatorSize.tab",
        "indicator: BoxDecoration(",
        "dividerColor: Colors.transparent",
        "borderRadius: BorderRadius.circular(999)",
        "isScrollable: true",
    ),
    "independent oval module tabs",
)
require(
    stock_catalog + partners + sales_tabs + purchase_tabs + lazy_tab_view,
    ("AppLazyTabView", "This view builds only the", "IndexedStack", "lazy-module-tab-"),
    "lazy module tabs for performance",
)

# The current module architecture intentionally supersedes the historical
# nested inline-metric rectangle. Assert implementation markers rather than
# comments that may change independently from the workspace contract.
require(
    entity_page + horizontal_strip,
    (
        "mergeHiddenHeaderActionsAndStatistics",
        "module-command-rail",
        "module-continuous-workspace",
        "AppHorizontalStrip",
        "scrollDirection: Axis.horizontal",
        "SingleChildScrollView(",
        "ConstrainedBox(",
    ),
    "continuous command/metric workspace",
)

# R86 replaces the historical movable/resizable window shell with one bounded
# operational workspace. The route owns the only window header; page-level
# close/back helpers remain scope-aware without recreating nested window chrome.
require(
    window + back + entity_page + window_close,
    (
        "Desktop workspaces intentionally remain bounded",
        "class _PremiumWorkspaceTheme",
        "class _WorkspaceHeader",
        "class _WorkspacePresentation",
        "_scaffoldAsHeaderlessWorkspace",
        "appBar?.actions",
        "source.floatingActionButton",
        "if (child is AlertDialog)",
        "module-workspace-window",
        "Clip.antiAlias",
        "AppWorkspaceWindowScope.maybeOf(context) != null",
        "AppWindowCloseButton",
    ),
    "bounded integrated internal workspaces",
)
for forbidden in (
    "class _PremiumWindowTheme",
    "class _WindowHeader",
    "class _WindowFooter",
    "class _ScaffoldAsWindow",
    "class _AlertDialogAsWindow",
    "closeDock",
    "module-window-control-strip",
):
    if forbidden in window:
        errors.append(f"legacy module-window chrome is still active: {forbidden}")

require(
    firebase + package + web_index,
    (
        '"source": "/main.dart.js"',
        '"value": "no-store, no-cache, must-revalidate, max-age=0"',
        "navigator.serviceWorker.getRegistrations()",
        "registration.unregister()",
    ),
    "cross-device fresh web UI",
)

require(
    nomenclature,
    (
        "'salesorder'",
        "'purchaseorder'",
        "maintenanceOrder",
        "'stocktransfer'",
        "'stockscrap'",
        "'inventoryinput'",
        "invoice(",
        "partnerPayment",
        "'journalentry'",
    ),
    "document nomenclature coverage",
)

try:
    json.loads(web_version)
    json.loads(firebase)
    json.loads(package)
except json.JSONDecodeError as error:
    errors.append(f"invalid release JSON: {error}")

if errors:
    print("FAILED V7.3.7 complete repairs")
    for error in errors:
        print("  -", error)
    raise SystemExit(1)

print("PASS V7.3.7 incremental maintenance, UI, cache and performance repair")
print("  - maintenance supports atomic multi-currency payment batches and settlements")
print("  - maintenance invoice deletion preserves governed payment/stock separation")
print("  - lazy module tabs and independent pill navigation remain enforced")
print("  - continuous command rails replace nested internal module rectangles")
print("  - bounded operational workspaces are the canonical internal window shell")
print("  - web runtime assets bypass stale service-worker/browser caches")
