#!/usr/bin/env python3
"""Verify V7.3.8 performance, cache, UI and invoice-owned workflow repairs."""
from __future__ import annotations

from pathlib import Path
from verification_text import contains_code

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        errors.append(f"missing {relative}")
        return ""
    return path.read_text(encoding="utf-8-sig")


def require(text: str, needles: tuple[str, ...], label: str) -> None:
    missing = [needle for needle in needles if needle not in text]
    if missing:
        errors.append(f"{label}: missing {', '.join(missing)}")


release = read("pubspec.yaml") + read("lib/core/release/app_release_info.dart") + read("web/version.json")
migration = read("supabase/migrations/20260806003000_v738_active_workflow_projection_and_verified_links.sql")
v736 = read("supabase/migrations/20260805223000_v736_invoice_owned_accounting_workflow_ui.sql")
v737 = read("supabase/migrations/20260805234500_v737_maintenance_payment_batch_and_final_repairs.sql")
entity = read("lib/core/widgets/app_entity_page.dart")
horizontal = read("lib/core/widgets/app_horizontal_strip.dart")
lazy = read("lib/core/widgets/app_lazy_tab_view.dart")
window = read("lib/core/widgets/app_full_page_route.dart")
window_close = read("lib/core/widgets/app_window_close_button.dart")
pills = read("lib/core/widgets/app_pill_tab_bar.dart")
stock_tabs = read("lib/features/inventory/pages/stock_catalog_page.dart")
partner_tabs = read("lib/features/business_partners/pages/business_partners_page.dart")
sales_tabs = read("lib/features/sales/pages/sales_operations_page.dart")
purchase_tabs = read("lib/features/purchases/pages/purchase_operations_page.dart")
product_page = read("lib/features/inventory/pages/inventory_page.dart")
maintenance_page = read("lib/features/maintenance/pages/maintenance_page.dart")
accounting = read("lib/features/accounting/pages/accounting_center_page.dart")
car_stats = read("lib/features/inventory/cars/widgets/cars_statistics.dart")
customer_stats = read("lib/features/business_partners/customers/widgets/customers_statistics.dart")
supplier_page = read("lib/features/business_partners/suppliers/pages/suppliers_page.dart")
customer_card = read("lib/features/business_partners/customers/widgets/customer_card.dart")
supplier_card = read("lib/features/business_partners/suppliers/widgets/supplier_card.dart")
sales_page = read("lib/features/sales/workflow/pages/sales_workflow_page.dart")
purchase_page = read("lib/features/purchases/pages/purchase_workflow_page.dart")
workflow_card = read("lib/core/widgets/commercial_workflow_order_card.dart")
filter_bar = read("lib/core/widgets/commercial_workflow_filter_bar.dart")
refresh = read("lib/app/bootstrap/app_dependencies.dart")
controllers = "\n".join(
    read(path)
    for path in (
        "lib/features/inventory/cars/controllers/cars_controller.dart",
        "lib/features/inventory/controllers/inventory_controller.dart",
        "lib/features/business_partners/customers/controllers/customers_controller.dart",
        "lib/features/business_partners/suppliers/controllers/suppliers_controller.dart",
        "lib/features/sales/controllers/sales_controller.dart",
        "lib/features/purchases/controllers/purchases_controller.dart",
        "lib/features/maintenance/controllers/maintenance_controller.dart",
    )
)
web = read("web/index.html") + read("firebase.json") + read("web/_headers") + read("web/.htaccess")
prepare_web = read("tool/prepare_local_canvaskit.py")
nomenclature = read("lib/core/documents/document_nomenclature.dart")
product_forms = "\n".join(
    read(path)
    for path in (
        "lib/features/inventory/pages/add_inventory_page.dart",
        "lib/features/inventory/cars/pages/add_car_page.dart",
        "lib/features/inventory/cars/pages/edit_car_page.dart",
    )
)

require(
    release,
    ("18.9.8", "189800", "v738-full-verified-runtime-accounting-ui-20260806"),
    "release identity",
)
require(
    lazy + stock_tabs + partner_tabs + sales_tabs + purchase_tabs,
    (
        "class AppLazyTabView",
        "IndexedStack",
        "AppLazyTabView",
        "CarsPage()",
        "CustomersPage()",
        "SalesWorkflowPage()",
        "PurchaseWorkflowPage()",
    ),
    "lazy module loading",
)
require(
    entity + horizontal + window + window_close,
    (
        "AppHorizontalStrip",
        "effectiveShowBackButton",
        "AppWorkspaceWindowScope.maybeOf(context)",
        "AppWindowCloseButton",
        "module-inline-close",
        "child is AppEntityPage",
        "Desktop workspaces intentionally remain bounded",
        "class _WorkspaceHeader",
        "class _WorkspacePresentation",
        "_scaffoldAsHeaderlessWorkspace",
        "module-workspace-window",
        "Clip.antiAlias",
    ),
    "one-line commands and bounded module workspaces",
)
require(
    pills + filter_bar + accounting,
    (
        "borderRadius: BorderRadius.circular(999)",
        "dividerColor: Colors.transparent",
        "shape: const StadiumBorder()",
        "AppHorizontalStrip",
        "إدخال محاسبي جديد",
    ),
    "pill-only navigation",
)
require(
    product_page,
    (
        "المجموعات المخزنية",
        "إدارة المخازن",
        "سجل الحركة",
        "الحركات المتوقعة",
        "نقل مخزني",
        "إنشاء منتج",
        "statistics: Row(",
    ),
    "product command and metric row",
)
require(
    maintenance_page + v737,
    (
        "أمر صيانة جديد",
        "statistics: Row(",
        "showInvoicePaymentBatchDialog",
        "recordPaymentsBatch",
        "erp_record_cloud_maintenance_payment_batch",
        "maintenance_closing_payment_must_be_last",
    ),
    "maintenance one-line commands and multi-currency payments",
)
for text, label in (
    (car_stats, "car metrics"),
    (customer_stats, "customer metrics"),
    (supplier_page[supplier_page.rfind("class _SupplierStatistics"):], "supplier metrics"),
):
    if "SingleChildScrollView" in text:
        errors.append(f"{label}: nested horizontal scroller remains")
    if not contains_code(text, "mainAxisSize: MainAxisSize.min"):
        errors.append(f"{label}: metrics are not a compact row")
require(
    customer_card + supplier_card,
    ("عميل تجاري", "مورد نشط", "Column(", "maxLines: 2"),
    "partner badge placement",
)
require(
    controllers + refresh,
    (
        "bool get hasLoaded",
        "Duration(seconds: 20)",
        "cars.hasLoaded",
        "inventory.hasLoaded",
        "maintenance.hasLoaded",
        "loadInventory(force: true)",
        "loadOrders(force: true)",
    ),
    "performance refresh gating",
)
require(
    migration,
    (
        "status,'')) not in ('cancelled','canceled','voided')",
        "canCreateReceipt",
        "canCreateDelivery",
        "canCreateInvoice",
        "canApproveInvoice",
        "canRecordPayment",
        "canCancelInvoice",
        "receiptAccountingOwner",
        "deliveryAccountingOwner",
        "'accountingOwner','invoice'",
        "erp_sync_opportunity_sales_lifecycle",
        "workflowAccountingOwner",
    ),
    "active workflow projection and two-way opportunity link",
)
require(
    sales_page + purchase_page,
    (
        "_serverFlag",
        "canCreateInvoice",
        "canApproveInvoice",
        "canRecordPayment",
        "الدفعات متعددة العملات",
    ),
    "server-authoritative invoice buttons",
)
require(
    workflow_card,
    (
        "Delivery",
        "Receipt",
        "Not posted",
        "القيد المحاسبي",
        "Accounting entry",
        "accountingOwner",
        "invoiceRemaining",
        "paymentStatus",
    ),
    "visible accounting and payment indicators",
)
require(
    v736,
    (
        "quantity-only; valuation owned by invoice",
        "erp_v736_assert_invoice_logistics",
        "invoice_quantities_must_equal_approved_logistics",
        "salesRevenueIqdAccountId",
        "salesRevenueUsdAccountId",
        "sales_invoice_revenue",
        "purchase_invoice_valuation_",
        "erp_v736_post_sales_invoice_costs",
        "erp_cancel_cloud_workflow_invoice",
        "valuationSnapshots",
    ),
    "invoice-owned accounting and reversal",
)
require(
    product_forms,
    (
        "salesRevenueIqdAccountId",
        "salesRevenueUsdAccountId",
        "type.toLowerCase() != 'revenue'",
        "currency.toUpperCase() != 'IQD'",
        "currency.toUpperCase() != 'USD'",
    ),
    "dual revenue account validation",
)
require(
    web + prepare_web,
    (
        "Cache-Control",
        "no-store, no-cache, must-revalidate, max-age=0",
        "getRegistrations()",
        "caches.keys()",
        "copy_host_metadata",
        '"_headers", ".htaccess"',
        "flutter_bootstrap.js?v=",
        "version.json?t=",
    ),
    "cross-device web cache recovery",
)
require(
    nomenclature,
    (
        "إشعار استلام مخزني للشراء",
        "إذن تجهيز مخزني للبيع",
        "سند قبض دفعة عميل",
        "سند صرف دفعة مورد",
        "محضر إتلاف مخزني",
        "سند إدخال أو تسوية مخزنية",
        "قيد يومية محاسبي",
    ),
    "document nomenclature",
)

if errors:
    print("FAIL V7.3.8 full requirements verification")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS V7.3.8 full requirements verification")
print("  - heavy module tabs are lazy and hidden controllers are not refreshed")
print("  - command/metric rows stay horizontal and internal workspaces stay bounded")
print("  - active workflow documents drive invoice/payment controls")
print("  - warehouse approval is quantity-only; invoices own accounting/valuation")
print("  - opportunity, payment, naming and cross-device cache links are verified")
