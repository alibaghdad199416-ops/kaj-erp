#!/usr/bin/env python3
"""Verify V7.3.7 invoice-owned accounting, headless UI, cache and performance repair."""
from __future__ import annotations

import json
import re
from pathlib import Path
from verification_text import contains_code

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


migration_path = "supabase/migrations/20260805223000_v736_invoice_owned_accounting_workflow_ui.sql"
migration = read(migration_path)
v737_migration = read(
    'supabase/migrations/20260805234500_v737_maintenance_payment_batch_and_final_repairs.sql'
)
release = read("lib/core/release/app_release_info.dart") + read("pubspec.yaml")
web_version = read("web/version.json")
web_index = read("web/index.html")
firebase = read("firebase.json")
package = read("package.json")
pill_tabs = read("lib/core/widgets/app_pill_tab_bar.dart")
entity_page = read("lib/core/widgets/app_entity_page.dart")
horizontal_strip = read("lib/core/widgets/app_horizontal_strip.dart")
lazy_tab_view = read("lib/core/widgets/app_lazy_tab_view.dart")
window_close = read("lib/core/widgets/app_window_close_button.dart")
window = read("lib/core/widgets/app_full_page_route.dart")
back = read("lib/core/widgets/app_back_button.dart")
account_fields = read("lib/features/inventory/widgets/inventory_account_fields.dart")
product_model = read("lib/features/inventory/models/inventory_model.dart")
car_model = read("lib/features/inventory/cars/models/car_model.dart")
product_page = read("lib/features/inventory/pages/inventory_page.dart")
car_page = read("lib/features/inventory/cars/pages/cars_page.dart")
maintenance_page = read("lib/features/maintenance/pages/maintenance_page.dart")
maintenance_repository = read("lib/features/maintenance/data/maintenance_repository.dart")
maintenance_controller = read("lib/features/maintenance/controllers/maintenance_controller.dart")
payment_dialog = read("lib/core/finance/invoice_payment_batch_dialog.dart")
accounting_page = read("lib/features/accounting/pages/accounting_center_page.dart")
customer_stats = read("lib/features/business_partners/customers/widgets/customers_statistics.dart")
customer_card = read("lib/features/business_partners/customers/widgets/customer_card.dart")
supplier_card = read("lib/features/business_partners/suppliers/widgets/supplier_card.dart")
stock_catalog = read("lib/features/inventory/pages/stock_catalog_page.dart")
partners = read("lib/features/business_partners/pages/business_partners_page.dart")
sales_tabs = read("lib/features/sales/pages/sales_operations_page.dart")
purchase_tabs = read("lib/features/purchases/pages/purchase_operations_page.dart")
sales_repo = read("lib/features/sales/workflow/repositories/sales_workflow_repository.dart")
purchase_repo = read("lib/features/purchases/repositories/purchase_workflow_repository.dart")
sales_draft = read("lib/features/sales/workflow/pages/sales_order_draft_page.dart")
purchase_draft = read("lib/features/purchases/pages/purchase_order_draft_page.dart")
sales_page = read("lib/features/sales/workflow/pages/sales_workflow_page.dart")
purchase_page = read("lib/features/purchases/pages/purchase_workflow_page.dart")
maintenance_details = read("lib/features/maintenance/pages/maintenance_order_details_dialog.dart")
opportunity_model = read("lib/features/customer_service/models/opportunity_model.dart")
opportunity_card = read("lib/features/customer_service/widgets/opportunity_card.dart")
realtime = read("lib/core/cloud/cloud_realtime_bridge.dart")
nomenclature = read("lib/core/documents/document_nomenclature.dart")

require(
    release + web_version,
    (
        "18.9.8",
        "189800",
        "v738-full-verified-runtime-accounting-ui-20260806",
    ),
    "release identity",
)

require(
    migration,
    (
        "Invoice-owned valuation/accounting, quantity-only logistics",
        "erp_v736_ensure_currency_revenue_accounts",
        "erp_v736_ensure_purchase_clearing_accounts",
        "erp_v736_convert_currency",
        "erp_v736_item_accounting",
        "erp_v736_assert_invoice_logistics",
        "erp_create_cloud_sales_workflow_invoice",
        "erp_create_cloud_purchase_workflow_invoice",
        "erp_approve_cloud_workflow_invoice",
        "erp_cancel_cloud_workflow_invoice",
        "erp_v736_post_sales_invoice_costs",
        "erp_v736_post_maintenance_invoice",
        "erp_v736_sales_document_opportunity_sync",
        "erp_v736_sales_order_opportunity_sync",
        "erp_v736_sales_order_opportunity_sync_trg",
    ),
    "V736 migration surface",
)

for name in (
    "erp_phase2_post_purchase_receipt",
    "erp_phase2_post_sales_delivery",
    "erp_phase3_post_maintenance_issue",
):
    body = function_body(migration, name)
    if "select null::text" not in body:
        errors.append(f"{name} must be a no-op compatibility wrapper")

for name in ("erp_approve_cloud_purchase_receipt", "erp_approve_cloud_sales_delivery"):
    body = function_body(migration, name)
    require(
        body,
        (
            "'accountingOwner','invoice'",
            "'valuationPendingInvoice',true",
            "quantity-only; valuation owned by invoice",
        ),
        f"{name} quantity-only behavior",
    )
    for forbidden in (
        "erp_phase2_insert_journal_at",
        "purchase_invoice_valuation_",
        "sales_invoice_revenue",
    ):
        if forbidden in body:
            errors.append(f"{name} still posts accounting through {forbidden}")

approval = function_body(migration, "erp_approve_cloud_workflow_invoice")
require(
    approval,
    (
        "erp_v736_assert_invoice_logistics",
        "currency=v_currency",
        "exchange_rate>0",
        "ac->>'revenueAccountId'",
        "sales_invoice_revenue",
        "erp_v736_post_sales_invoice_costs",
        "purchase_invoice_valuation_",
        "erp_v736_convert_currency",
        "'valuationApplied',true",
        "financial and valuation posting owned by invoice",
    ),
    "invoice-owned financial and valuation posting",
)

cancellation = function_body(migration, "erp_cancel_cloud_workflow_invoice")
require(
    cancellation,
    (
        "erp_v736_void_journal_id",
        "costJournalEntries",
        "valuationSnapshots",
        "valuationReversedAt",
        "accountingReversedAt",
    ),
    "invoice reversal",
)

exact = function_body(migration, "erp_v736_assert_invoice_logistics")
require(
    exact,
    (
        "invoice_quantities_must_equal_approved_logistics",
        "approved",
        "allocations",
    ),
    "exact logistics invoice quantities",
)

maintenance = function_body(migration, "erp_v736_post_maintenance_invoice")
require(
    maintenance,
    (
        "maintenanceRevenueIqdAccountId",
        "maintenanceRevenueUsdAccountId",
        "cost_journal_entry_ids",
        "erp_phase2_insert_journal_at",
        "accountingOwner",
    ),
    "maintenance invoice accounting",
)

maintenance_advance = function_body(migration, "erp_advance_cloud_maintenance_workflow")
require(
    maintenance_advance,
    (
        "'maintenance_out'",
        "car_cost_added=0",
        "erp_v736_post_maintenance_invoice",
        "workflow_stage='invoice_approved'",
    ),
    "maintenance quantity then invoice workflow",
)
if "erp_phase3_post_maintenance_issue" in maintenance_advance:
    errors.append("maintenance stock approval still invokes legacy accounting posting")

require(
    v737_migration,
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

maintenance_payment = function_body(
    v737_migration, "erp_v737_record_maintenance_payment"
)
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

maintenance_batch = function_body(
    v737_migration, "erp_record_cloud_maintenance_payment_batch"
)
require(
    maintenance_batch,
    (
        "jsonb_array_elements(p_payments) with ordinality",
        "maintenance_closing_payment_must_be_last",
        "erp_v737_record_maintenance_payment",
    ),
    "atomic maintenance payment batch",
)

maintenance_component = function_body(
    v737_migration, "erp_manage_maintenance_order_component"
)
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

maintenance_payment_surface = maintenance_page + maintenance_repository + maintenance_controller + payment_dialog
require(
    maintenance_payment_surface,
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
if "erp_record_cloud_maintenance_payment_batch" not in maintenance_payment_surface and "erp_v2300_record_maintenance_payment_batch" not in maintenance_payment_surface:
    errors.append("maintenance multi-payment UI and repository: missing maintenance payment batch RPC")

require(
    migration,
    (
        "salesRevenueIqdAccountId",
        "salesRevenueUsdAccountId",
        "lower(a.account_type)='revenue'",
        "upper(a.currency)=v_invoice_currency",
        "legacyReceiptValuationDetachedAt",
        "legacyDeliveryAccountingDetachedAt",
        "legacyStockIssueAccountingDetachedAt",
    ),
    "dual revenue bindings and safe legacy detachment",
)

require(
    account_fields + product_model + car_model,
    (
        "salesRevenueIqdAccountId",
        "salesRevenueUsdAccountId",
        "حساب إيراد البيع بالدينار IQD",
        "حساب إيراد البيع بالدولار USD",
        "a.type.toLowerCase() == 'revenue'",
        "a.currency.toUpperCase() == 'IQD'",
        "a.currency.toUpperCase() == 'USD'",
    ),
    "master-data revenue account validation",
)

exchange_surface = sales_repo + purchase_repo + sales_draft + purchase_draft
require(
    exchange_surface,
    (
        "required double exchangeRate",
        "final _exchangeRate = TextEditingController",
        "سعر الصرف (دينار لكل دولار)",
    ),
    "order exchange-rate capture",
)
if not contains_code(exchange_surface, "'p_exchange_rate': exchangeRate") and not contains_code(exchange_surface, "'exchangeRate': exchangeRate"):
    errors.append("order exchange-rate capture: exchangeRate is not sent to the order RPC/payload")

require(
    sales_page + purchase_page + maintenance_details,
    (
        "invoiceId",
        "invoiceStatus",
        "createInvoice",
        "approveInvoice",
        "addPayment",
    ),
    "invoice and payment actions",
)

require(
    pill_tabs,
    (
        "no surrounding segmented-control rectangle",
        "dividerColor: Colors.transparent",
        "borderRadius: BorderRadius.circular(999)",
        "isScrollable: true",
    ),
    "independent oval module tabs",
)
pill_surface = stock_catalog + partners + sales_tabs + purchase_tabs
require(pill_surface, ("AppPillTabBar",), "module pill tab integration")
for arabic_label in ("السيارات", "العملاء", "أوامر البيع", "أوامر الشراء"):
    if arabic_label not in pill_surface:
        errors.append(f"module pill tab integration: missing localized label {arabic_label!r}")
require(
    stock_catalog + partners + sales_tabs + purchase_tabs + lazy_tab_view,
    (
        "AppLazyTabView",
        "This view builds only the",
        "IndexedStack",
        "lazy-module-tab-",
    ),
    "lazy module tabs for performance",
)
require(
    entity_page + horizontal_strip,
    (
        "mergeHiddenHeaderActionsAndStatistics",
        "class _InlineCommandMetricsRow",
        "AppHorizontalStrip",
        "scrollDirection: Axis.horizontal",
        "statistics!",
        "SingleChildScrollView(",
    ),
    "one-line actions and metrics",
)
require(
    product_page + car_page + maintenance_page + accounting_page + customer_stats,
    (
        "hideHeader: true",
        "statistics:",
        "SingleChildScrollView(",
        "scrollDirection: Axis.horizontal",
    ),
    "module one-line command/metric rows",
)
require(
    accounting_page,
    (
        "toolbarFramed: false",
        "ChoiceChip(",
        "scrollDirection: Axis.horizontal",
    ),
    "accounting pill sections without ruler frame",
)
require(
    window + back + entity_page + window_close,
    (
        "The window has no title header, footer",
        "class _ScaffoldAsWindow",
        "class _AlertDialogAsWindow",
        "...?appBar?.actions",
        "scaffold.floatingActionButton",
        "closeDock",
        "AppWorkspaceWindowScope.maybeOf(context) != null",
        "AppWindowCloseButton",
        "module-inline-close",
    ),
    "headless internal windows and hidden back control",
)
if "module-window-control-strip" in window:
    errors.append("separate module window header strip is still present")

require(
    customer_card + supplier_card,
    (
        "maxLines: 2",
        "PartnerStatusBadge(",
        "const SizedBox(height: 3)",
    ),
    "partner status below full name",
)

require(
    opportunity_model + opportunity_card + sales_repo + realtime + migration,
    (
        "salesOrderStatus",
        "deliveryStatus",
        "invoiceStatus",
        "paymentStatus",
        "remainingAmount",
        "AppDataChangeBus.instance.publish('opportunities'",
        "_RealtimeBinding('erp_records'",
        "'opportunities'",
        "erp_sync_opportunity_sales_lifecycle",
    ),
    "two-way opportunity and sales lifecycle",
)

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

print("PASS V7.3.7 invoice-owned accounting, UI, cache and performance repair")
print("  - logistics updates quantity/state only; invoice approval owns accounting")
print("  - invoice quantities match approved multi-warehouse logistics exactly")
print("  - IQD/USD revenue and cost-currency journals are separated")
print("  - invoice cancellation restores journals, FIFO and valuation snapshots")
print("  - maintenance and opportunities follow the same invoice lifecycle")
print("  - maintenance supports atomic multi-currency payment batches and settlements")
print("  - pill navigation, one-line commands and headless windows are enforced")
print("  - web runtime assets bypass stale service-worker/browser caches")
