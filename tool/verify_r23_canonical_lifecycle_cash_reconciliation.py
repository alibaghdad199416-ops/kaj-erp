#!/usr/bin/env python3
"""R23 canonical vehicle lifecycle, Phase26 RPC, and cashbox reconciliation closure."""
from __future__ import annotations

from verification_text import normalized_text_sha256
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = [
    "20260808052709_r23_canonical_vehicle_lifecycle_and_phase26_contract.sql",
    "20260808062444_r23_cashbox_ledger_alias_contract.sql",
    "20260808062519_r23_deterministic_cashbox_rebinding.sql",
    "20260808063806_r23_cashbox_rebind_lock_safety.sql",
]
errors: list[str] = []

def need(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)

def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8", errors="strict")

def function_body(sql: str, name: str) -> str:
    m = re.search(
        rf"create\s+or\s+replace\s+function\s+public\.{re.escape(name)}\s*\(.*?\)\s*"
        rf"returns\b.*?\bas\s*\$\$(.*?)\$\$\s*;",
        sql,
        re.I | re.S,
    )
    if not m and name == "erp_r22_phase26_cloud_command":
        m = re.search(
            rf"create\s+function\s+public\.{re.escape(name)}\s*\(.*?\)\s*"
            rf"returns\b.*?\bas\s*\$\$(.*?)\$\$\s*;",
            sql,
            re.I | re.S,
        )
    return m.group(1) if m else ""

for relative, digest in {
    "dart_defines.json": "4c7d0bbe2c68df5bd459d1b06081921b80f531c9887fe464dd70532718764c2f",
    ".firebaserc": "f56fa212a1a202d098575515c3bf7e3210d8c7b9d74865c90e6fa6e5c0f2e4a8",
    "firebase.json": "ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a",
}.items():
    need(normalized_text_sha256(ROOT / relative) == digest,
         f"local runtime/hosting baseline changed: {relative}")

migration_dir = ROOT / "supabase/migrations"
for name in MIGRATIONS:
    need((migration_dir / name).exists(), f"missing R23 migration: {name}")
all_migrations = sorted(p.name for p in migration_dir.glob("*.sql"))
r23_positions = [all_migrations.index(name) for name in MIGRATIONS if name in all_migrations]
need(len(r23_positions) == len(MIGRATIONS) and r23_positions == list(range(r23_positions[0], r23_positions[0] + len(MIGRATIONS))),
     "R23 migrations are not a contiguous ordered migration chain")

lifecycle_sql = read(f"supabase/migrations/{MIGRATIONS[0]}")
state = function_body(lifecycle_sql, "erp_r23_vehicle_operational_state")
need(bool(state), "canonical vehicle state function missing")
for token in (
    "erp_r15_pending_delete_exists",
    "erp_purchase_order_items_cloud",
    "erp_sales_order_items_cloud",
    "erp_commercial_workflow_documents",
    "eligibleForPurchase",
    "eligibleForSale",
    "legacyStatusIgnored",
    "canonicalVehicleStateVersion",
):
    need(token in state, f"vehicle lifecycle missing canonical source: {token}")
need("data->>'status'" not in state, "vehicle operational state still reads legacy status text")
need("data->>'statusValue'" not in state and "data->>'status_value'" not in state,
     "vehicle operational state still trusts persisted status aliases")

subtotal = function_body(lifecycle_sql, "erp_cloud_commercial_items_subtotal")
need("erp_r23_vehicle_operational_state" in subtotal, "purchase/sales validation does not use R23 vehicle state")
need("data->>'status'" not in subtotal, "commercial item validation still uses legacy vehicle status")
catalog = function_body(lifecycle_sql, "erp_cloud_purchase_order_catalog")
need("erp_r23_vehicle_operational_state" in catalog and "eligibleForPurchase" in catalog,
     "purchase catalog is not generated from canonical vehicle eligibility")
need("erp_r15_pending_delete_exists" in catalog, "purchase catalog can surface tombstoned data")

phase26 = function_body(lifecycle_sql, "erp_r22_phase26_cloud_command")
need(bool(phase26), "exact R22 Phase26 RPC definition missing")
need("erp_r14_phase26_cloud_command" in phase26, "Phase26 compatibility route is broken")
need("p_payload jsonb default" not in lifecycle_sql.lower(), "Phase26 endpoint still exposes a default/ambiguous signature")
need("revoke all on function public.erp_r22_phase26_cloud_command(text,text,jsonb) from public,anon;" in lifecycle_sql.lower(),
     "Phase26 anonymous execution is not revoked")
need("grant execute on function public.erp_r22_phase26_cloud_command(text,text,jsonb) to authenticated,service_role;" in lifecycle_sql.lower(),
     "Phase26 authenticated execute grant missing")
need("notify pgrst,'reload schema';" in lifecycle_sql.lower(), "Phase26 migration does not reload PostgREST schema")

alias_sql = read(f"supabase/migrations/{MIGRATIONS[1]}")
helper = function_body(alias_sql, "erp_r23_cashbox_ledger_account_id")
need("account_id" in helper and "accountId" in helper, "cashbox current-ledger resolver missing both persisted aliases")
need(helper.find("account_id") < helper.find("accountId"), "normalized account_id must win over stale accountId")
need("trg_r23_sync_cashbox_ledger_aliases" in alias_sql, "future cashbox alias drift is not prevented")
need("erp_r23_cashbox_ledger_account_id(ca.data)" in alias_sql,
     "cash/GL reconciliation does not use canonical current ledger identity")

bind_sql = read(f"supabase/migrations/{MIGRATIONS[2]}")
binder = function_body(bind_sql, "erp_r22_bind_cash_transaction_exact")
for token in (
    "cashTransactionId",
    "v_ref_type='cash_transfer'",
    "transfer_id_cashbox_current_account",
    "currentLedgerAccountId",
    "r23DeterministicCashBinding",
    "r23CashIdentityMethod",
):
    need(token in binder, f"deterministic cash binding missing identity token: {token}")
need("Amount is NOT used to select the line" in bind_sql,
     "R23 cash migration must document the no-amount-only identity rule")
match_pos = binder.find("erp_r16_cash_line_matches")
transfer_pos = binder.find("transfer_id_cashbox_current_account")
need(match_pos > transfer_pos > 0,
     "amount/direction helper is being used before deterministic identity selection")
need("r23_cash_identity_unresolved" in binder and "r23_cash_identity_ambiguous" in binder,
     "unprovable cash history is not surfaced explicitly")

lock_sql = read(f"supabase/migrations/{MIGRATIONS[3]}")
rebind = function_body(lock_sql, "erp_r23_rebind_cashbox_journals_internal")
need("for update skip locked" in rebind.lower(), "cash reconciliation can block live Production transactions")
need("skippedLockedTransactions" in rebind, "lock-safe reconciliation does not report deferred transactions")
compat = function_body(lock_sql, "erp_r15_rebind_cashbox_journals_internal")
need("erp_r23_rebind_cashbox_journals_internal" in compat,
     "legacy R15 reconciliation callers do not converge to R23")

# Accounting invariants remain owned by R22; R23 must not re-introduce clearing/capitalization.
r22 = read("supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql")
for token in ("erp_r22_post_purchase_invoice_direct", "'direct_supplier_inventory'", "erp_r22_approve_workflow_invoice"):
    need(token in r22, f"R22 accounting invariant lost: {token}")
for r23_name in MIGRATIONS:
    text = read(f"supabase/migrations/{r23_name}").lower()
    for forbidden in ("1391", "1392", "ledger difference journal", "amount-only fallback"):
        need(forbidden not in text, f"R23 reintroduced forbidden accounting workaround: {forbidden} in {r23_name}")

scripts = json.loads(read("package.json"))["scripts"]
need(scripts.get("verify:r23") == "python -B tool/verify_r23_canonical_lifecycle_cash_reconciliation.py",
     "verify:r23 command missing")
need("npm run verify:r23" in scripts.get("verify:workspace", ""), "workspace verification does not include R23")
deploy_command = scripts.get("deploy:production", "")
deploy_match = re.search(r"tool/deploy_r(\d+)_production\.ps1", deploy_command)
deploy_release = int(deploy_match.group(1)) if deploy_match else 0
need(deploy_release >= 23 and (ROOT / f"tool/deploy_r{deploy_release}_production.ps1").is_file(),
     "deploy:production does not point to R23 or an existing verified later orchestration")
need(scripts.get("validate:r23:workspace") == "powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r23_workspace.ps1",
     "R23 installed-workspace validator missing")
production = read("tool/deploy_r23_production.ps1") if (ROOT / "tool/deploy_r23_production.ps1").exists() else ""
for name in MIGRATIONS:
    need(name in production, f"R23 production deployment does not allow migration: {name}")
need("Unexpected pending migrations. Refusing production push" in production,
     "R23 production deployment lost unexpected-migration refusal")
need("npm run validate:r23:workspace" in production, "R23 deploy does not run compile/test/build validation")

if errors:
    print("FAILED R23 canonical lifecycle/cash reconciliation")
    for error in errors:
        print("  -", error)
    raise SystemExit(1)

print("PASS R23 canonical lifecycle/cash reconciliation")
print("  - vehicle purchase/sale eligibility derives from current normalized workflow state, not legacy labels")
print("  - deleted/tombstoned vehicles/products are not resurrected into catalogs")
print("  - Phase26 exposes one authenticated PostgREST signature with schema reload")
print("  - cashbox ledger aliases converge on the current account and reconciliation uses that account")
print("  - historical rebinding uses transaction/transfer identity; amount is validation only")
print("  - live reconciliation uses SKIP LOCKED and reports deferred rows instead of blocking Production")
print("  - R22 direct purchase/sales accounting ownership remains intact")
print("  - Local Supabase/Firebase baseline hashes are unchanged")
