#!/usr/bin/env python3
"""R70 CRM Opportunity runtime/source contract verification.

This verifier intentionally owns implementation-source inspection so Flutter tests
remain behavior-focused and package-safe.
"""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.is_file():
        raise SystemExit(f"R70 verifier missing required file: {relative}")
    return path.read_text(encoding="utf-8")


def require(text: str, token: str, label: str) -> None:
    if token not in text:
        raise SystemExit(f"R70 verifier failed: {label} missing {token!r}")


def forbid(text: str, token: str, label: str) -> None:
    if token in text:
        raise SystemExit(f"R70 verifier failed: {label} still contains {token!r}")


def function_slice(text: str, signature: str) -> str:
    start = text.find(signature)
    if start < 0:
        raise SystemExit(f"R70 verifier failed: function missing {signature!r}")
    next_create = text.find("\ncreate or replace function ", start + len(signature))
    next_revoke = text.find("\nrevoke all on function ", start + len(signature))
    endings = [value for value in (next_create, next_revoke) if value >= 0]
    end = min(endings) if endings else len(text)
    return text[start:end]


base = read("supabase/migrations/20260814170000_r70_crm_opportunity_sales_authority.sql")
readback = read("supabase/migrations/20260814171000_r70_1_sales_opportunity_readback.sql")
reference = read("supabase/migrations/20260814172000_r70_2_opportunity_business_reference.sql")
legacy_acl = read("supabase/migrations/20260814173000_r70_3_legacy_crm_execution_closure.sql")
runtime = read("supabase/migrations/20260814222000_r70_4_opportunity_sales_maintenance_runtime_repair.sql")
maintenance_cancel = read("supabase/migrations/20260814223000_r70_5_maintenance_draft_cancel_contract.sql")
lost_reactivation = read("supabase/migrations/20260814224500_r70_6_lost_sales_reactivation_guard.sql")
identity_guard = read("supabase/migrations/20260814225500_r70_7_sales_opportunity_identity_guard.sql")
r39_maintenance = read("supabase/migrations/20260809161514_r39_canonical_maintenance_compile_closure.sql")
v67_linked_edit = read("supabase/migrations/20260804011000_v67_commercial_maintenance_linked_edit.sql")
repository = read("lib/features/customer_service/repositories/opportunity_repository.dart")
controller = read("lib/features/customer_service/controllers/opportunities_controller.dart")
customer_service = read("lib/features/customer_service/pages/customer_service_page.dart")
add_opportunity = read("lib/features/customer_service/pages/add_opportunity_page.dart")
card = read("lib/features/customer_service/widgets/opportunity_card.dart")
model = read("lib/features/customer_service/models/opportunity_model.dart")
sales_draft = read("lib/features/sales/workflow/pages/sales_order_draft_page.dart")
sales_repository = read("lib/features/sales/workflow/repositories/sales_workflow_repository.dart")
maintenance_repository = read("lib/features/maintenance/data/maintenance_repository.dart")
maintenance_dialog = read("lib/features/maintenance/pages/maintenance_order_details_dialog.dart")

# R70 canonical conversion authority: Opportunity cannot create a fake sale/invoice.
for token in (
    "erp_r70_list_opportunities",
    "erp_r70_opportunity_command",
    "opportunity_won_owned_by_sales_workflow",
    "opportunity_has_sales_history",
    "opportunity_sales_customer_locked",
    "opportunity_sales_currency_locked",
    "opportunity_probability_invalid",
    "opportunity_responsible_user_invalid",
    "for update",
    "erp_v2300_create_sales_order",
    "erp_sync_opportunity_sales_lifecycle",
):
    require(base, token, "R70 canonical Opportunity authority")
forbid(repository, "markWonAndCreateInvoice", "Opportunity repository")
forbid(controller, "markWonAndCreateInvoice", "Opportunity controller")
require(customer_service, "SalesOrderDraftPage(", "Opportunity Sales conversion UI")
require(customer_service, "findOrderByOpportunity", "Opportunity Sales conversion UI")
require(customer_service, "OrderDetailsDialog(", "Opportunity Sales conversion UI")
require(sales_repository, "erp_r49_create_sales_order", "Sales repository")
require(sales_repository, "'opportunityId': opportunityId", "Sales repository")

# Human references and browser authority closure.
for token in ("erp_r70_get_sales_opportunity_context", "'opportunityNumber'", "erp_r62_get_commercial_order_snapshot"):
    require(readback, token, "R70 Sales readback")
for token in ("erp_opportunity_business_reference_seq", "'OPP-'||lpad", "erp_records_opportunity_reference_uq"):
    require(reference, token, "R70 Opportunity business reference")
for token in ("erp_r49_opportunity_command(text,jsonb)", "erp_r9_phase26_cloud_command(text,text,jsonb)", "from public,anon,authenticated"):
    require(legacy_acl, token, "R70 legacy CRM execution closure")

# Fix 1: cancelling an already-linked Sales order after CRM becomes Lost must be
# allowed, while NEW/re-linked/reactivated Sales from Lost remains blocked.
for token in (
    "v_same_historical_link",
    "v_cancel_restore",
    "v_creates_or_relinks",
    "raise exception 'opportunity_is_lost'",
):
    require(runtime, token, "R70.4 Lost/Sales cancellation repair")
for token in (
    "v_cancel_restore",
    "v_reactivates_cancelled",
    "v_creates_or_relinks",
    "update of company_id,customer_id,opportunity_id,is_deleted,status",
    "raise exception 'opportunity_is_lost'",
):
    require(lost_reactivation, token, "R70.6 Lost Sales reactivation guard")
require(card, "opportunity.saleId != null && canViewSale", "Lost Opportunity historical Sales open path")

# R70.7 closes the remaining identity gap on Sales updates. Customer and currency
# are checked at the table trigger boundary while an unchanged legacy mismatch
# can still reach governed cancellation/reversal rather than becoming undeletable.
for token in (
    "v_customer_changed",
    "v_currency_changed",
    "v_opportunity_customer",
    "v_opportunity_currency",
    "opportunity_customer_mismatch",
    "opportunity_currency_mismatch",
    "company_id,customer_id,opportunity_id,is_deleted,status,currency",
):
    require(identity_guard, token, "R70.7 Sales Opportunity identity guard")
require(identity_guard, "v_cancel_restore", "R70.7 historical cancellation compatibility")
require(identity_guard, "v_reactivates_cancelled", "R70.7 reactivation guard")

# Fix 2: Maintenance Cancel is a real independent operation from the Opportunity
# modal, including Draft cancellation, and Delete remains separately governed.
for token in (
    "draftCancellation",
    "workflow_stage='cancelled'",
    "maintenance.cancel",
    "erp_r67_cancel_maintenance_order_pre_r70_5",
):
    require(maintenance_cancel, token, "R70.5 Maintenance cancellation contract")
require(card, "'maintenance.cancel'", "Opportunity Maintenance cancel permission")
require(card, "'maintenance.delete'", "Opportunity Maintenance delete permission")
require(card, "onCancel: !linkedOrder.isCancelled", "Opportunity Maintenance modal cancel callback")
require(maintenance_repository, "erp_r67_cancel_maintenance_order", "Maintenance repository cancel RPC")
require(maintenance_dialog, "await widget.onCancel?.call();", "Maintenance dialog cancel callback")
require(maintenance_dialog, "await _loadDetails();", "Maintenance dialog authoritative reload")

# Fix 3: Opportunity <-> Maintenance is persisted/read from canonical DB state,
# visible on the Opportunity card, and reopenable after save/update/cancel.
for token in (
    "erp_r56_find_maintenance_by_opportunity",
    "maintenanceOrderId",
    "maintenanceOrderNumber",
    "maintenanceOrderStatus",
    "erp_maintenance_orders",
    "idx_r70_maintenance_opportunity_history",
):
    require(runtime, token, "R70.4 Opportunity/Maintenance readback")
for token in ("maintenanceOrderId", "maintenanceOrderNumber", "maintenanceOrderStatus", "hasMaintenanceOrder"):
    require(model, token, "Opportunity model Maintenance projection")
for token in ("findByOpportunity(opportunity.id)", "AddMaintenanceOrderPage(", "MaintenanceOrderDetailsDialog(", "opportunity.hasMaintenanceOrder"):
    require(card, token, "Opportunity Maintenance UI")
require(maintenance_repository, "erp_r56_find_maintenance_by_opportunity", "Maintenance repository readback RPC")

# Updating/rebuilding an existing Maintenance order must keep the canonical
# Opportunity relation. Both routines update the same order row and intentionally
# leave opportunity_id/opportunity_number untouched.
r39_update = function_slice(
    r39_maintenance,
    "create or replace function public.erp_r39_update_cloud_maintenance_draft(",
)
v67_prepare = function_slice(
    v67_linked_edit,
    "create or replace function public.erp_v67_prepare_maintenance_linked_edit(",
)
require(r39_update, "update public.erp_maintenance_orders set", "R39 Maintenance edit")
require(v67_prepare, "update public.erp_maintenance_orders", "V67 Maintenance linked-edit preparation")
for token in ("opportunity_id=", "opportunity_number="):
    forbid(r39_update.lower().replace(" ", ""), token, "R39 Maintenance edit relation preservation")
    forbid(v67_prepare.lower().replace(" ", ""), token, "V67 Maintenance linked-edit relation preservation")

# Opportunity-created Sales drafts must carry the Opportunity currency into the
# UI instead of silently defaulting an IQD Opportunity to USD. Backend identity
# validation remains the final authority.
for token in (
    "this.initialCurrency",
    "final String? initialCurrency",
    "widget.initialCurrency?.trim().toUpperCase()",
    "this.initialOpportunityNumber",
    "final String? initialOpportunityNumber",
):
    require(sales_draft, token, "Opportunity Sales seed")
require(customer_service, "initialCurrency: opportunity.currency", "Opportunity center Sales currency seed")
require(
    customer_service,
    "initialOpportunityNumber: opportunity.opportunityNumber",
    "Opportunity center Sales business-reference seed",
)
forbid(sales_draft, "${widget.opportunityId}", "Sales draft user-visible Opportunity identity")
require(add_opportunity, "initialCurrency: item.currency", "Opportunity editor Sales currency seed")

# Daily CRM search/export must use human business references, not internal UUIDs.
for token in (
    "item.salesOrderNumber ?? ''",
    "item.maintenanceOrderNumber ?? ''",
    "o.salesOrderNumber ?? ''",
    "o.maintenanceOrderNumber ?? ''",
):
    require(customer_service, token, "Opportunity business-reference search/export")
forbid(customer_service, "o.saleId ?? ''", "Opportunity export")

# A cancelled Maintenance order is historical evidence. Explicitly creating a
# new Maintenance draft from the Opportunity must not try to edit that cancelled
# document.
require(
    add_opportunity,
    "order: existing?.isCancelled == true ? null : existing",
    "Opportunity cancelled-Maintenance history handling",
)

# Conversion must not collapse physical/accounting stages.
create_start = base.find("create or replace function public.erp_r49_create_sales_order")
if create_start < 0:
    raise SystemExit("R70 verifier failed: Sales creation wrapper missing")
create_body = base[create_start:]
for forbidden in (
    "approve_sales",
    "create_sales_delivery",
    "create_cloud_sales_workflow_invoice",
    "pay_cloud_sales",
    "inventory_movement",
):
    forbid(create_body, forbidden, "R70 Sales draft conversion")

print("PASS R70 CRM Opportunity runtime/source contracts")
print("  - linked Sales cancellation remains possible after CRM Lost projection")
print("  - new/re-linked/reactivated Sales from Lost remain blocked")
print("  - linked Sales customer/currency identity cannot diverge from Opportunity")
print("  - Maintenance Cancel and Delete remain distinct governed operations")
print("  - Opportunity <-> Maintenance readback is canonical and reopenable")
print("  - Maintenance linked edits preserve the exact Opportunity relation")
print("  - IQD/USD Opportunity currency seeds the linked Sales draft")
print("  - Sales draft shows the human Opportunity business reference")
print("  - CRM search/export uses human Sales and Maintenance references")
