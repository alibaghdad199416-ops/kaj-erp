#!/usr/bin/env python3
"""R86 Phase 2B CRM/Sales authoritative readback source contract."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260816190000_r86_phase2b_crm_sales_authoritative_readback.sql"
REPOSITORY = ROOT / "lib/features/customer_service/repositories/opportunity_repository.dart"
R84 = ROOT / "supabase/migrations/20260816013000_r84_user_record_scope_atomic_profile_closure.sql"


def read(path: Path) -> str:
    if not path.is_file():
        raise SystemExit(f"R86 verifier missing required file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def require(text: str, token: str, label: str) -> None:
    if token not in text:
        raise SystemExit(f"R86 verifier failed: {label} missing {token!r}")


migration = read(MIGRATION)
repository = read(REPOSITORY)
r84 = read(R84)

# Reproduce the regression explicitly: R84 introduced the scoped list but its
# historical implementation projected only compatibility payload data.
require(r84, "create or replace function public.erp_r84_list_opportunities", "R84 regression fixture")
require(r84, "r.payload||jsonb_build_object('updatedAt',r.updated_at", "R84 raw-payload readback fixture")
require(repository, "erp_r84_list_opportunities", "current Opportunity repository")

# R86 must restore canonical linked identities from relational tables, not from
# duplicated/stale Opportunity JSON fields.
for token in (
    "create or replace function public.erp_r84_list_opportunities",
    "r.payload - array[",
    "from public.erp_sales_orders_cloud so",
    "so.opportunity_id=r.record_id",
    "from public.erp_commercial_workflow_documents doc",
    "doc.document_type='delivery'",
    "doc.document_type='invoice'",
    "'salesOrderId'",
    "'salesOrderNumber'",
    "'salesOrderStatus'",
    "'deliveryId'",
    "'deliveryNumber'",
    "'deliveryStatus'",
    "'invoiceId'",
    "'invoiceNumber'",
    "'invoiceStatus'",
    "'invoiceCurrency'",
    "'paidAmount'",
    "'remainingAmount'",
    "'paymentStatus'",
    "'workflowLinked'",
    "'workflowCompleted'",
):
    require(migration, token, "authoritative CRM/Sales projection")

# R84 record ownership and field-level filtering remain mandatory; the fix may
# not re-open company-wide records while restoring linked workflow state.
for token in (
    "public.erp_r84_record_visible(",
    "'customer_service'",
    "coalesce(r.payload->>'createdByUserId',r.payload->>'createdBy','')",
    "public.erp_r9_filter_readable_json(",
    "permission_denied:customer_service.view",
):
    require(migration, token, "R84 scope preservation")

# Physical workflow state must drive freshness as Sales/Delivery/Invoice change,
# otherwise CRM can remain stale until the Opportunity itself is edited.
for token in (
    "coalesce(o.updated_at,r.updated_at)",
    "coalesce(d.updated_at,r.updated_at)",
    "coalesce(i.updated_at,r.updated_at)",
):
    require(migration, token, "linked workflow freshness")

# Keep execution limited to authenticated members/service tooling.
for token in (
    "security definer",
    "set search_path=public",
    "revoke all on function public.erp_r84_list_opportunities(uuid) from public,anon",
    "to authenticated,service_role",
):
    require(migration, token, "RPC security contract")

print("PASS R86 Phase 2B CRM/Sales authoritative readback contracts")
print("  - Opportunity Sales/Delivery/Invoice/Payment links are relational readback")
print("  - R84 records.own/all scope and field filtering remain enforced")
print("  - linked workflow timestamps refresh the CRM projection")
