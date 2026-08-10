#!/usr/bin/env python3
"""R24 runtime accounting, invoice/payment, performance, UI and locale closure."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MIGRATIONS = [
    "20260808085021_r24_runtime_accounting_payment_performance_closure.sql",
    "20260808085451_r24_journal_currency_invoice_closure.sql",
    "20260808090027_r24_sales_invoice_immutable_logistics_closure.sql",
    "20260808090250_r24_sales_fifo_alias_closure.sql",
    "20260808091343_r24_partner_dual_ledger_canonical_closure.sql",
]
errors: list[str] = []


def need(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8", errors="strict")


def function_body(sql: str, name: str) -> str:
    # R24 uses both $function$ and $$ bodies. Capture the body without relying
    # on physical formatting so Windows dart format cannot affect this gate.
    pat = rf"create\s+or\s+replace\s+function\s+public\.{re.escape(name)}\s*\(.*?\)\s*returns\b.*?\bas\s+(\$[A-Za-z0-9_]*\$)(.*?)\1\s*;"
    m = re.search(pat, sql, re.I | re.S)
    return m.group(2) if m else ""


for relative, digest in {
    "dart_defines.json": "1b0cbea9cf00177e68700f226832d17a083762a04fd271d9ca8b75d36aafb3c7",
    ".firebaserc": "003c25fc2e4659367989cfd4ca9703505abad207657fe6effc49c9317877098e",
    "firebase.json": "ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a",
}.items():
    need((ROOT / relative).exists(), f"missing production configuration: {relative}")
    if (ROOT / relative).exists():
        need(hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() == digest,
             f"production configuration changed: {relative}")

migration_dir = ROOT / "supabase/migrations"
all_migrations = sorted(p.name for p in migration_dir.glob("*.sql"))
for name in MIGRATIONS:
    need((migration_dir / name).exists(), f"missing R24 migration: {name}")
r24_positions = [all_migrations.index(name) for name in MIGRATIONS if name in all_migrations]
need(len(r24_positions) == len(MIGRATIONS)
     and r24_positions == sorted(r24_positions)
     and all(b == a + 1 for a, b in zip(r24_positions, r24_positions[1:])),
     "R24 historical migrations must remain present in their original contiguous order")

# Runtime accounting/cashbox closure.
runtime = read(f"supabase/migrations/{MIGRATIONS[0]}")
transaction_guard = function_body(runtime, "erp_r24_guard_cash_transaction_payload")
account_guard = function_body(runtime, "erp_r24_guard_cash_account_payload")
need(bool(transaction_guard), "R24 cash-transaction field guard missing")
for token in ("when 'type' then 'transactionType'", "when 'voucherNumber' then 'documentNumber'",
              "when 'cashAccountId' then 'cashAccount'", "when 'counterAccountId' then 'counterAccount'"):
    need(token in transaction_guard, f"cash transaction guard does not preserve/map runtime field: {token}")
need(bool(account_guard) and "when 'accountId' then 'ledgerAccount'" in account_guard
     and "when 'account_id' then 'ledgerAccount'" in account_guard,
     "cashbox ledger aliases are not guarded through one logical ledger field")

cash_change = function_body(runtime, "erp_r15_cashbox_definition_changed")
need(bool(cash_change), "R24 cashbox-change trigger function missing")
need("erp_r23_cashbox_ledger_account_id" in cash_change,
     "cashbox save does not use the canonical current ledger resolver")
need("rebind_cashbox" not in cash_change.lower(),
     "normal cashbox save still performs historical rebind work")

deferred = function_body(runtime, "erp_r16_deferred_cash_reconcile")
need("erp_r22_bind_cash_transaction_exact" in deferred,
     "deferred reconciliation is not bounded to the current cash transaction")
need("rebind_cashbox" not in deferred.lower(),
     "cash transaction COMMIT still scans historical cashbox journals")
for fn in ("erp_r22_save_cloud_cash_account", "erp_r22_post_cloud_cash_transaction"):
    body = function_body(runtime, fn)
    need(bool(body), f"R24 wrapper missing: {fn}")
    need("rebind_cashbox" not in body.lower(), f"{fn} still runs historical rebind inline")
transfer = function_body(runtime, "erp_r22_transfer_cloud_cash")
need(bool(transfer), "R24 cash transfer definition missing")
need(transfer.count("erp_r23_cashbox_ledger_account_id") >= 2,
     "cash transfer does not resolve both source/target current ledgers canonically")
need("rebind_cashbox" not in transfer.lower(), "cash transfer still performs historical rebind inline")
need("deferred_exact_transaction" in transfer, "cash transfer does not declare bounded reconciliation mode")
need("r24LedgerBindingRepair" in runtime and "v_count=1" in runtime,
     "deterministic duplicate cashbox-ledger repair is missing or not uniqueness-gated")

# Journal line currency closure.
journal_sql = read(f"supabase/migrations/{MIGRATIONS[1]}")
journal = function_body(journal_sql, "erp_phase2_insert_journal_at")
need(bool(journal), "R24 central journal insert function missing")
need("'entryId',eid,'currency',v_currency" in journal.replace(" ", "").replace("\n", "")
     or "'entryId',eid,'currency',v_currency" in journal,
     "journal lines do not receive currency before validation")
need("journal_line_currency_mismatch" in journal,
     "central journal insert does not reject explicit line-currency mismatch")
need("v_currency not in ('USD','IQD')" in journal,
     "central journal insert does not constrain supported currencies")

# Sales invoice must compare immutable approved logistics, not post-delivery stock.
logistics_sql = read(f"supabase/migrations/{MIGRATIONS[2]}")
validate_alloc = function_body(logistics_sql, "erp_validate_commercial_warehouse_allocations")
assert_logistics = function_body(logistics_sql, "erp_v736_assert_invoice_logistics")
need(bool(validate_alloc) and bool(assert_logistics), "R24 sales logistics functions missing")
need("if p_check_sales_stock then" in validate_alloc,
     "sales vehicle current-state checks are not gated by p_check_sales_stock")
need(assert_logistics.count("p_company_id,p_order_id,p_module") >= 2 and assert_logistics.count(",false") >= 2,
     "invoice logistics does not validate invoice + approved snapshot with live-stock checks disabled")
need("r24ImmutableLogisticsValidation" in assert_logistics,
     "immutable invoice-logistics validation marker missing")

# Sales FIFO alias ambiguity closure.
fifo_sql = read(f"supabase/migrations/{MIGRATIONS[3]}")
fifo = function_body(fifo_sql, "erp_v736_post_sales_invoice_costs")
need(bool(fifo), "R24 sales FIFO posting function missing")
need("join public.erp_inventory_cost_layers layer on layer.id=fc.layer_id" in fifo,
     "sales FIFO posting does not use the unambiguous layer alias")
need("and layer.id=fc.layer_id" in fifo,
     "sales FIFO journal update does not use the unambiguous layer alias")
need(not re.search(r"join\s+public\.erp_inventory_cost_layers\s+l\s+on\s+l\.id\s*=\s*fc\.layer_id", fifo, re.I),
     "ambiguous l.id FIFO alias reintroduced")

# Maintenance/customer/supplier must use canonical dual-currency partner ledgers.
partner_sql = read(f"supabase/migrations/{MIGRATIONS[4]}")
partner = function_body(partner_sql, "erp_v764_assert_partner_dual_ledgers")
need(bool(partner), "R24 canonical partner dual-ledger guard missing")
need(partner.count("erp_workflow_partner_account") >= 2 and "'USD'" in partner and "'IQD'" in partner,
     "partner dual-ledger guard does not resolve both currencies canonically")
for legacy in ("receivableUsdAccountId", "receivableIqdAccountId", "payableUsdAccountId", "payableIqdAccountId"):
    need(legacy not in partner, f"maintenance/partner ledger guard still depends on legacy alias: {legacy}")

# R22 purchase direct-posting policy must remain intact.
r22 = read("supabase/migrations/20260808043000_r22_production_accounting_consolidation.sql")
for token in ("erp_r22_post_purchase_invoice_direct", "'direct_supplier_inventory'", "erp_r22_approve_workflow_invoice"):
    need(token in r22, f"R22 accounting invariant lost: {token}")
for name in MIGRATIONS:
    text = read(f"supabase/migrations/{name}").lower()
    for forbidden in ("1391", "1392", "ledger difference journal", "amount-only fallback"):
        need(forbidden not in text, f"R24 reintroduced forbidden accounting workaround: {forbidden} in {name}")

# Flutter runtime performance/rebuild closure.
cashbox_controller = read("lib/features/accounting/cashbox/controllers/cashbox_controller.dart")
for token in ("Future<void>? _refreshInFlight", "Future<void> _refresh()", "Future<void> _performRefresh()", "identical(_refreshInFlight, request)"):
    need(token in cashbox_controller, f"CashboxController refresh coalescing missing: {token}")
need("if (_isLoading == value) return;" in cashbox_controller,
     "CashboxController emits redundant loading notifications")

cash_page = read("lib/features/accounting/cashbox/pages/add_cash_transaction_page.dart")
build_match = re.search(r"Widget\s+build\s*\(BuildContext\s+context\)\s*\{(.*?)(?=\n\s*}\n\s*})", cash_page, re.S)
build_text = build_match.group(1) if build_match else ""
need("selectedCashAccountId" in cash_page and "selectedCounterAccountId" in cash_page,
     "cash transaction page does not derive valid selections without mutating state")
# Direct mutation of these fields is allowed in callbacks but must not occur while deriving build values.
head = cash_page[cash_page.find("Widget build(BuildContext context)"):cash_page.find("return Scaffold", cash_page.find("Widget build(BuildContext context)"))]
need("_cashAccountId = null" not in head and "_counterAccountId = null" not in head,
     "cash transaction build still mutates selection state")

lazy = read("lib/core/widgets/app_lazy_tab_view.dart")
need("SchedulerBinding.instance.schedulerPhase" in lazy and "addPostFrameCallback" in lazy,
     "lazy module tabs do not defer unsafe mid-frame rebuilds")
lazy_build_start = lazy.find("Widget build(BuildContext context)")
lazy_build = lazy[lazy_build_start:] if lazy_build_start >= 0 else ""
need("_visited.add(selected)" not in lazy_build and "_selectedIndex = selected" not in lazy_build,
     "AppLazyTabView still mutates state from build()")

# Yellow/black RenderFlex closure: every form dropdown must expand to available width.
missing_expanded: list[str] = []
for path in (ROOT / "lib").rglob("*.dart"):
    text = path.read_text(encoding="utf-8")
    for match in re.finditer(r"DropdownButtonFormField\s*<[^>]+>\s*\(", text):
        start = match.start()
        # isExpanded is a top-level constructor option and will be near the constructor opening.
        window = text[start:start + 700]
        if "isExpanded:" not in window:
            line = text.count("\n", 0, start) + 1
            missing_expanded.append(f"{path.relative_to(ROOT)}:{line}")
need(not missing_expanded,
     "DropdownButtonFormField missing isExpanded (yellow/black overflow risk): " + ", ".join(missing_expanded[:12]))
# Guard against malformed automated constructor edits (R24.1 compile closure).
malformed_dropdown_edits: list[str] = []
for path in (ROOT / "lib").rglob("*.dart"):
    text = path.read_text(encoding="utf-8")
    for pattern in (r"child\s*:\s*isExpanded\s*:", r"return\s+isExpanded\s*:", r"=\s*isExpanded\s*:"):
        if re.search(pattern, text):
            malformed_dropdown_edits.append(str(path.relative_to(ROOT)))
            break
need(not malformed_dropdown_edits,
     "malformed DropdownButtonFormField isExpanded injection: " + ", ".join(malformed_dropdown_edits[:12]))
recycle = read("lib/features/settings/recycle_bin/pages/recycle_bin_page.dart")
need(re.search(r"DropdownButtonFormField\s*<String>\s*\(\s*isExpanded\s*:\s*true", recycle) is not None,
     "known recycle-bin 52px RenderFlex overflow is not closed")

# Language/RTL persistence closure.
settings = read("lib/features/settings/pages/settings_page.dart")
need("AppPreferencesController" in settings and ".setLocale(" in settings and "Locale(_language)" in settings,
     "saved system language does not update runtime AppPreferences locale")
need("LayoutBuilder(" in settings and "Wrap(" in settings,
     "language/currency settings remain a fixed-width Row")
need("_language = model.language == 'ar' ? 'ar' : 'en';" in settings,
     "settings language model is not normalized to supported ar/en locales")

scripts = json.loads(read("package.json"))["scripts"]
need(scripts.get("verify:r24") == "python -B tool/verify_r24_runtime_accounting_ui_closure.py",
     "verify:r24 command missing")
need("npm run verify:r24" in scripts.get("verify:workspace", ""), "workspace verification does not include R24")
deploy_command = scripts.get("deploy:production", "")
deploy_match = re.search(r"tool/deploy_r(\d+)_production\.ps1", deploy_command)
deploy_release = int(deploy_match.group(1)) if deploy_match else 0
need(deploy_release >= 24 and (ROOT / f"tool/deploy_r{deploy_release}_production.ps1").is_file(),
     "deploy:production does not point to R24 or an existing verified later orchestration")
need(scripts.get("validate:r24:workspace") == "powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r24_workspace.ps1",
     "R24 installed-workspace validator missing")

deploy = read("tool/deploy_r24_production.ps1")
for name in MIGRATIONS:
    need(name in deploy, f"R24 production deployment does not allow migration: {name}")
need("Unexpected pending migrations. Refusing production push" in deploy,
     "R24 production deployment lost unexpected-migration refusal")
need("npm run validate:r24:workspace" in deploy,
     "R24 deploy does not run analyze/test/fresh-build validation")
need("firebase-tools deploy --only hosting" in deploy.lower(), "R24 deploy no longer publishes Firebase Hosting after validation")

if errors:
    print("FAILED R24 runtime accounting/UI closure")
    for error in errors:
        print("  -", error)
    raise SystemExit(1)

print("PASS R24 runtime accounting/UI closure")
print("  - cashbox saves and cash posting are bounded; historical rebind is removed from normal transactions")
print("  - receipt/payment payload fields survive field-level permission guarding")
print("  - cashbox duplicate ledgers are deterministically repaired without amount-based history guessing")
print("  - journal lines receive their currency before integrity validation")
print("  - purchase and sales invoices keep invoice-owned accounting; sales invoice validates immutable delivery allocation")
print("  - sales FIFO SQL aliases are unambiguous and maintenance uses canonical USD/IQD partner ledgers")
print("  - cashbox refreshes are coalesced and tab/page state is not mutated during build")
print("  - all form dropdowns expand responsively, closing the observed yellow/black RenderFlex class")
print("  - saved company language updates the active app locale and responsive settings layout")
print("  - R22 direct Supplier <-> Inventory purchase accounting remains intact")
print("  - Supabase/Firebase production configuration hashes are unchanged")
