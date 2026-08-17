#!/usr/bin/env python3
"""R22: production accounting consolidation closure.

R22 replaces the failure-prone invoice/cash browser surface with one current
contract, posts new purchases directly Supplier <-> Inventory, rebuilds legacy
purchase accounting from source without replaying valuation, and makes cash
transfer identity explicit at creation and during reconciliation.
"""
from __future__ import annotations

from verification_text import normalized_text_sha256
import json
import re
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATION_NAME = "20260808043000_r22_production_accounting_consolidation.sql"
errors: list[str] = []


def need(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8", errors="strict")


def function_body(sql: str, name: str) -> str:
    match = re.search(
        rf"create\s+or\s+replace\s+function\s+public\.{re.escape(name)}\s*\(.*?\)\s*"
        rf"returns\b.*?\bas\s*\$\$(.*?)\$\$\s*;",
        sql,
        re.I | re.S,
    )
    return match.group(1) if match else ""


for relative, digest in {
    "dart_defines.json": "4c7d0bbe2c68df5bd459d1b06081921b80f531c9887fe464dd70532718764c2f",
    ".firebaserc": "f56fa212a1a202d098575515c3bf7e3210d8c7b9d74865c90e6fa6e5c0f2e4a8",
    "firebase.json": "ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a",
}.items():
    need(
        normalized_text_sha256(ROOT / relative) == digest,
        f"local runtime/hosting baseline changed: {relative}",
    )

migration_path = ROOT / "supabase/migrations" / MIGRATION_NAME
need(migration_path.exists(), f"R22 migration missing: {MIGRATION_NAME}")
migration_names = sorted(p.name for p in (ROOT / "supabase/migrations").glob("*.sql"))
need(MIGRATION_NAME in migration_names, "R22 consolidation migration is missing from the migration chain")
sql = migration_path.read_text(encoding="utf-8") if migration_path.exists() else ""

purchase = function_body(sql, "erp_r22_post_purchase_invoice_direct")
need(bool(purchase), "R22 direct purchase posting function missing")
for token in (
    "erp_workflow_partner_account",
    "'assetAccountId'",
    "'direct_supplier_inventory'",
    "erp_phase2_insert_journal_at",
    "erp_v762_assert_posted_journal_balanced",
    "'accountingOwner','invoice'",
):
    need(token in purchase, f"R22 direct purchase path missing: {token}")
for forbidden in (
    "erp_v760_ensure_purchase_fx_settlement_accounts",
    "erp_v736_ensure_purchase_clearing_accounts",
    "erp_v760_normalize_purchase_invoice_posting",
    "1391",
    "1392",
):
    need(forbidden not in purchase, f"R22 direct purchase path still depends on legacy clearing/capitalization: {forbidden}")
need("purchase_item_currency_mismatch" in purchase, "purchase single-currency definition guard is missing")
need("costJournalEntries','[]'" in purchase, "direct purchase must not retain a secondary cost/capitalization journal chain")

historical = function_body(sql, "erp_r22_normalize_legacy_purchase_invoice")
need(bool(historical), "R22 historical purchase rebuild function missing")
for token in (
    "erp_r15_legacy_capitalized_purchase_invoices",
    "erp_v736_void_journal_id",
    "erp_phase2_insert_journal_at",
    "'r22HistoricalCanonicalRepost'",
    "'direct_supplier_inventory'",
    "legacy_purchase_currency_ambiguous",
):
    need(token in historical, f"R22 historical purchase rebuild missing: {token}")
for forbidden in (
    "erp_v760_normalize_purchase_invoice_posting",
    "erp_v760_ensure_purchase_fx_settlement_accounts",
    "1391",
    "1392",
):
    need(forbidden not in historical, f"historical R22 rebuild still routes through legacy settlement path: {forbidden}")
r15_normalizer = function_body(sql, "erp_r15_normalize_legacy_purchase_invoice")
need("erp_r22_normalize_legacy_purchase_invoice" in r15_normalizer, "R15/R16 historical reconciliation does not converge to R22")

approve = function_body(sql, "erp_r22_approve_workflow_invoice")
need(bool(approve), "R22 canonical invoice approval function missing")
need("erp_approve_cloud_workflow_invoice(p_company_id,p_invoice_id,'sales')" in approve.replace("\n", " ").replace("  ", " "),
     "R22 sales approval does not call the proven invoice-owned sales core directly")
need("erp_r22_post_purchase_invoice_direct" in approve, "R22 purchase approval does not use direct Supplier/Inventory posting")
for forbidden in (
    "erp_v762_approve_workflow_invoice",
    "erp_v760_approve_workflow_invoice",
    "erp_v750_approve_workflow_invoice_resilient",
):
    need(forbidden not in approve, f"R22 approval still traverses legacy wrapper chain: {forbidden}")
for wrapper in (
    "erp_r14_approve_sales_invoice",
    "erp_r14_approve_purchase_invoice",
    "erp_v762_approve_workflow_invoice",
    "erp_approve_cloud_sales_workflow_invoice",
    "erp_approve_cloud_purchase_workflow_invoice",
):
    body = function_body(sql, wrapper)
    need("erp_r22_" in body, f"compatibility approval wrapper does not converge to R22: {wrapper}")

cash_transfer = function_body(sql, "erp_r22_transfer_cloud_cash")
need(bool(cash_transfer), "R22 cash transfer function missing")
for token in (
    "'cashTransactionId'",
    "'cashAccountId'",
    "'referenceType','cash_transfer'",
    "erp_v762_assert_posted_journal_balanced",
    "erp_r15_rebind_cashbox_journals_internal",
):
    need(token in cash_transfer, f"R22 cash transfer identity/posting missing: {token}")
need("ledger difference" not in cash_transfer.lower(), "R22 cash transfer must not create a Ledger Difference workaround")

binder = function_body(sql, "erp_r22_bind_cash_transaction_exact")
for token in (
    "r22_cash_identity_unresolved",
    "r22_cash_identity_ambiguous",
    "candidateCount",
    "erp_r16_record_reconciliation_issue",
):
    need(token in binder, f"R22 identity-safe cash reconciliation missing: {token}")
need("v_count<>1" in re.sub(r"\s+", "", binder), "R22 cash binding must refuse non-unique matches")
repair = function_body(sql, "erp_r22_repair_cash_transfer")
need("referenceId" in repair and "transfer_out" in repair and "transfer_in" in repair,
     "historical cash-transfer repair does not use transfer identity + direction")

# Browser surface: finance reads/writes, invoice approvals and cashbox operations no
# longer depend on R9/R14 PostgREST endpoint names.
files_without_old_browser_rpc = [
    "lib/features/accounting/repositories/accounting_repository.dart",
    "lib/features/accounting/repositories/professional_accounting_repository.dart",
    "lib/features/accounting/expenses/data/expense_repository.dart",
    "lib/features/accounting/fixed_assets/fixed_assets_page.dart",
    "lib/features/accounting/cashbox/repositories/cashbox_repository.dart",
]
for relative in files_without_old_browser_rpc:
    text = read(relative)
    need("erp_r9_" not in text, f"accounting browser still depends on an R9 RPC endpoint: {relative}")

need("erp_r22_approve_purchase_invoice" in read("lib/features/purchases/repositories/purchase_workflow_repository.dart"),
     "purchase browser does not use R22 approval")
need("erp_r22_approve_sales_invoice" in read("lib/features/sales/workflow/repositories/sales_workflow_repository.dart"),
     "sales browser does not use R22 approval")
cloud_command = read("lib/core/cloud/cloud_feature_command.dart")
# The generic browser command advanced to R37, whose server chain delegates
# R37 -> R35 -> R27 -> R14 -> R9. R22 reconciliation/probe remain direct.
r37 = read("supabase/migrations/20260809124736_r37_full_functional_presentation_closure.sql")
r35 = read("supabase/migrations/20260809153000_r35_runtime_ui_opportunity_maintenance_closure.sql")
r27 = read("supabase/migrations/20260808162000_r27_complete_functional_closure.sql")
r37_phase26_successor = (
    "erp_r37_cloud_command" in cloud_command
    and "erp_r35_cloud_command($1,$2" in r37
    and "erp_r27_cloud_command($1,$2" in r35
    and "erp_r14_phase26_cloud_command($1,$2" in r27
)
need("erp_r22_phase26_cloud_command" in cloud_command or r37_phase26_successor,
     "cloud command surface missing a verified successor of the R22 Phase-26 contract")
for token in ("erp_r22_reconcile_company_state", "erp_r22_runtime_contract_probe"):
    need(token in cloud_command, f"cloud command surface missing R22 contract: {token}")
readiness = read("lib/core/release/production_readiness_service.dart")
for flag in (
    "r22Phase26",
    "r22SalesApprove",
    "r22PurchaseApprove",
    "r22DirectPurchase",
    "r22HistoricalPurchaseRebuild",
    "r22CashTransfer",
    "r22CashReconciliation",
    "r22StateReconcile",
):
    need(flag in readiness, f"Production Readiness does not require R22 flag: {flag}")

# One coherent PostgREST schema exposure after the migration.
need("notify pgrst,'reload schema';" in sql.lower(), "R22 migration does not reload PostgREST schema")
for rpc in (
    "erp_r22_approve_sales_invoice(uuid,uuid)",
    "erp_r22_approve_purchase_invoice(uuid,uuid)",
    "erp_r22_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text)",
    "erp_r22_reconcile_company_state(uuid)",
    "erp_r22_runtime_contract_probe(uuid)",
):
    need(f"grant execute on function public.{rpc} to authenticated,service_role;" in sql.lower(),
         f"R22 authenticated grant missing: {rpc}")
for rpc in (
    "erp_r22_invoice_preflight(uuid,uuid,text)",
    "erp_r22_post_purchase_invoice_direct(uuid,uuid)",
    "erp_r22_normalize_legacy_purchase_invoice(uuid,uuid)",
):
    need(f"revoke all on function public.{rpc} from public,anon,authenticated;" in sql.lower(),
         f"R22 internal accounting helper is browser executable: {rpc}")
    need(f"grant execute on function public.{rpc} to service_role;" in sql.lower(),
         f"R22 internal accounting helper service grant missing: {rpc}")

scripts = json.loads(read("package.json"))["scripts"]
need(scripts.get("verify:r22") == "python -B tool/verify_r22_production_accounting_consolidation.py", "verify:r22 command missing")
need("npm run verify:r22" in scripts.get("verify:workspace", ""), "workspace verification missing R22")
deploy_command = scripts.get("deploy:production", "")
deploy_match = re.search(r"tool/deploy_r(\d+)_production\.ps1", deploy_command)
deploy_release = int(deploy_match.group(1)) if deploy_match else 0
need(deploy_release >= 22 and (ROOT / f"tool/deploy_r{deploy_release}_production.ps1").is_file(),
     "deploy:production must point at R22 or an existing verified later orchestrator")
production = read("tool/deploy_r22_production.ps1") if (ROOT / "tool/deploy_r22_production.ps1").exists() else ""
need(MIGRATION_NAME in production, "R22 production deploy does not allow the consolidation migration")
need("Unexpected pending migrations. Refusing production push" in production, "R22 deploy lost unexpected migration refusal")
need("Invoke-NativeCaptured" in production, "R22 deploy lost native exit-code handling")
need("npm run validate:r22:workspace" in production, "R22 deploy does not validate/build R22 first")

if errors:
    print("FAILED R22 production accounting consolidation")
    for error in errors:
        print("  -", error)
    raise SystemExit(1)

print("PASS R22 production accounting consolidation")
print("  - new purchase invoices post directly Supplier <-> Inventory without legacy clearing/capitalization")
print("  - historical capitalized purchase journals rebuild from source without replaying inventory valuation")
print("  - sales/purchase approvals converge on one diagnosable R22 contract")
print("  - cash transfers carry immutable transaction/cashbox identity and ambiguous history is never rewritten blindly")
print("  - accounting/cash browser RPC exposure is consolidated under the R22 namespace")
print("  - Production Readiness requires R22 runtime, reconciliation and historical-rebuild contracts")
print("  - Local Supabase/Firebase baseline hashes are unchanged")
