from __future__ import annotations

from pathlib import Path
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BASELINE_COMMIT = "967845801cb6d63881f95b38744fdd6e4c27ff6c"
errors: list[str] = []


def need(label: str, condition: bool) -> None:
    if not condition:
        errors.append(label)


def text(rel: str) -> str:
    path = ROOT / rel
    if not path.exists():
        errors.append(f"missing file: {rel}")
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        errors.append(
            f"git {' '.join(args)} failed: {result.stderr.strip() or result.stdout.strip()}"
        )
        return ""
    return result.stdout


# 1. Historical migrations are immutable relative to the accepted R92 baseline.
# New forward-only migrations are allowed; any migration that already existed in
# the accepted baseline must remain byte-identical.
need(
    "accepted R92 baseline commit is not available in git history",
    subprocess.run(
        ["git", "cat-file", "-e", f"{BASELINE_COMMIT}^{{commit}}"],
        cwd=ROOT,
        check=False,
        capture_output=True,
    ).returncode
    == 0,
)
baseline_migrations = {
    line.strip()
    for line in git(
        "ls-tree", "-r", "--name-only", BASELINE_COMMIT, "--", "supabase/migrations"
    ).splitlines()
    if line.strip()
}
changed_migrations = {
    line.strip()
    for line in git(
        "diff", "--name-only", f"{BASELINE_COMMIT}..HEAD", "--", "supabase/migrations"
    ).splitlines()
    if line.strip()
}
for rel in sorted(baseline_migrations & changed_migrations):
    errors.append(f"historical migration changed after accepted R92 baseline: {rel}")

# 2. The latest Phase 11 static and PostgreSQL runtime gates must exist.
for rel in [
    "tool/verify_r88_phase11.py",
    "tool/verify_r89_phase11_completion.py",
    "tool/verify_r90_phase11_final_acceptance.py",
    "tool/verify_r91_phase11_material_issue_acceptance.py",
    "tool/verify_r92_comprehensive_module_audit.py",
    "supabase/migrations/20260820184500_r93_purchase_receipt_single_action_closure.sql",
    "supabase/tests/verify_r89_phase11_runtime.sql",
    "supabase/tests/verify_r90_phase11_runtime.sql",
    "supabase/tests/verify_r91_phase11_runtime.sql",
    "supabase/tests/verify_r92_comprehensive_module_audit_runtime.sql",
    "supabase/tests/verify_r93_purchase_receipt_single_action_runtime.sql",
    "supabase/tests/verify_r93_restricted_user_runtime.sql",
    "tool/run_r89_r92_local_runtime_tests.py",
    "test/thousands_input_formatter_localized_test.dart",
]:
    need(f"required final gate missing: {rel}", (ROOT / rel).exists())

# 3. npm's authoritative aliases must include the current closure instead of
# silently stopping at the historical R58 workspace chain.
package_text = text("package.json")
try:
    package = json.loads(package_text)
except json.JSONDecodeError as exc:
    errors.append(f"package.json is invalid JSON: {exc}")
    package = {}
scripts = package.get("scripts", {}) if isinstance(package, dict) else {}
verify_all = str(scripts.get("verify:all", ""))
for script_name in [
    "verify:r88",
    "verify:r89",
    "verify:r90",
    "verify:r91",
    "verify:r92",
    "verify:r93",
]:
    need(f"verify:all omits {script_name}", f"npm run {script_name}" in verify_all)
need("verify:all no longer includes verify:workspace", "npm run verify:workspace" in verify_all)
need(
    "verify:r93 script is not wired to the final verifier",
    scripts.get("verify:r93") == "python -B tool/verify_r93_final_closure.py",
)
need(
    "check does not enter through verify:all",
    str(scripts.get("check", "")).startswith("npm run verify:all &&"),
)

# 4. R92 ACL tightening must not revoke an RPC still called anywhere in Flutter,
# including shared core/widgets code outside the seven audited feature trees.
r92 = text("supabase/migrations/20260820133000_r92_comprehensive_module_audit.sql")
rpc_pattern = re.compile(r"\.rpc\(\s*['\"]([^'\"]+)['\"]")
used_rpcs: dict[str, list[str]] = {}
for dart in (ROOT / "lib").rglob("*.dart"):
    src = dart.read_text(encoding="utf-8", errors="replace")
    for rpc in rpc_pattern.findall(src):
        used_rpcs.setdefault(rpc, []).append(str(dart.relative_to(ROOT)))

revoked_rpcs: set[str] = set()
for statement in r92.split(";"):
    if re.search(r"\brevoke\b", statement, re.I) and re.search(
        r"\bauthenticated\b", statement, re.I
    ):
        match = re.search(r"function\s+public\.([A-Za-z0-9_]+)\s*\(", statement, re.I)
        if match:
            revoked_rpcs.add(match.group(1))
for array_match in re.finditer(
    r"foreach\s+v_name\s+in\s+array\s+array\[(.*?)\]\s+loop", r92, re.S | re.I
):
    revoked_rpcs.update(re.findall(r"'([^']+)'", array_match.group(1)))

for conflict in sorted(set(used_rpcs) & revoked_rpcs):
    errors.append(
        "R92 revokes RPC still used by Flutter: "
        + conflict
        + " in "
        + ", ".join(sorted(set(used_rpcs[conflict])))
    )

# 5. Purchase receiving is one atomic action. The established client RPC keeps
# its signature, but R93 owns create+approval in one PostgreSQL transaction.
r93_purchase = text(
    "supabase/migrations/20260820184500_r93_purchase_receipt_single_action_closure.sql"
)
for marker in [
    "create or replace function public.erp_r49_create_purchase_receipt_multi",
    "'purchases','receipt.create'",
    "'purchases','receipt.approve'",
    "erp_r49_create_purchase_receipt_multi_pre_r88",
    "erp_phase2_approve_purchase_receipt_pre_r88",
    "purchase_receipt_allocations_required",
]:
    need(f"R93 atomic purchase receiving missing {marker}", marker in r93_purchase)
need(
    "R93 atomic purchase receiving mutates stock directly instead of approval-owned flow",
    "erp_warehouse_stock" not in r93_purchase
    and "erp_inventory_movements" not in r93_purchase,
)

# 6. The official GitHub gate must validate the committed tree before any
# formatter mutation, run the authoritative all-gate, and exercise local PostgreSQL.
workflow = text(".github/workflows/quality-gates.yml")
for marker in [
    "fetch-depth: 0",
    "npm run format:check",
    "npm run verify:all",
    "npx supabase start",
    "python -B tool/run_r89_r92_local_runtime_tests.py",
    "npm run analyze",
    "npm run test",
    "npm run build:web",
]:
    need(f"quality-gates workflow missing final closure marker: {marker}", marker in workflow)
workflow_lines = {line.strip() for line in workflow.splitlines()}
need(
    "quality-gates workflow still mutates Dart formatting before validation",
    "run: npm run format" not in workflow_lines,
)
for forbidden in [
    "supabase db reset",
    "supabase db push",
    "supabase link",
    "dart_defines.production.json",
]:
    need(f"quality-gates workflow contains forbidden operation: {forbidden}", forbidden not in workflow)

# 7. The local runtime runner must be explicitly local-only and cover every
# available R89-R93 PostgreSQL acceptance script without reset/push/link.
runner = text("tool/run_r89_r92_local_runtime_tests.py")
for marker in [
    "supabase_db_quality_line_erp_local_dev",
    "verify_r89_phase11_runtime.sql",
    "verify_r90_phase11_runtime.sql",
    "verify_r91_phase11_runtime.sql",
    "verify_r92_comprehensive_module_audit_runtime.sql",
    "verify_r93_purchase_receipt_single_action_runtime.sql",
    "verify_r93_restricted_user_runtime.sql",
    "ON_ERROR_STOP=1",
]:
    need(f"local runtime runner missing marker: {marker}", marker in runner)
for forbidden in ["db reset", "db push", "supabase link"]:
    need(f"local runtime runner contains forbidden operation: {forbidden}", forbidden not in runner)

# 8. High-severity Phase 11 UI regressions must remain closed. These guards are
# deliberately structural in addition to Flutter tests so a future refactor
# cannot silently reintroduce the reported production-facing failures.
numeric_formatter = text("lib/core/utils/thousands_input_formatter.dart")
localized_numeric_test = text("test/thousands_input_formatter_localized_test.dart")
maintenance_form = text("lib/features/maintenance/pages/add_maintenance_order_page.dart")
order_details = text("lib/features/sales/workflow/pages/order_details_dialog.dart")

for marker in [
    "_arabicIndicDigits",
    "_persianDigits",
    "_normalizeLocalizedNumber",
    "case '٫'",
    "case '٬'",
    "TextSelection.collapsed(offset: raw.length)",
]:
    need(f"localized numeric formatter missing marker: {marker}", marker in numeric_formatter)
for marker in ["١٢٣٬٤٥٦٫٧٥", "۹۸۷٬۶۵۴٫۵", "123,456.75", "discarded nonnumeric input"]:
    need(f"localized numeric regression test missing marker: {marker}", marker in localized_numeric_test)

for marker in [
    "getOrderLines(editingOrder.id)",
    "if (selectedVehicle == null && editingOrder != null)",
    "_loadError",
    "_bootstrap(force: true)",
    "CircularProgressIndicator",
]:
    need(f"maintenance draft reopen safety missing marker: {marker}", marker in maintenance_form)

need(
    "purchase receipt approval is still exposed as a separate workflow action",
    "Approve warehouse receipt" not in order_details
    and "تصديق الاستلام المخزني" not in order_details,
)
need(
    "purchase receipt inline approval is still enabled",
    "!(widget.purchase && componentType == 'receipt')" in order_details,
)
need(
    "purchase receipt UI still calls separate approveReceipt",
    "PurchaseWorkflowRepository().approveReceipt(documentId)" not in order_details,
)
need(
    "sales delivery lost its intentional separate approval branch",
    "SalesWorkflowRepository().approveDelivery(documentId)" in order_details
    and "!widget.purchase &&" in order_details,
)

# 9. Vehicle maintenance scheduling must stay reachable from every vehicle card,
# support the full schedule lifecycle, and materialize due reminders into the
# assigned user's notification inbox rather than storing reminder timestamps only.
cars_page = text("lib/features/inventory/cars/pages/cars_page.dart")
car_card = text("lib/features/inventory/cars/widgets/car_card.dart")
vehicle_service = text("lib/features/inventory/cars/pages/vehicle_service_card_page.dart")
notification_center = text(
    "lib/features/notifications/repositories/notification_center_repository.dart"
)

for marker in [
    "onSchedule: () => _showCarHistory(car)",
    "VehicleServiceCardPage(car: car)",
]:
    need(f"vehicle service card access missing marker: {marker}", marker in cars_page)
for marker in [
    "if (onSchedule != null)",
    "onPressed: onSchedule",
    "جدولة الصيانة",
]:
    need(f"car card service access missing marker: {marker}", marker in car_card)
for marker in [
    "_editSchedule",
    "_deleteSchedule",
    "_convertSchedule",
    "assignedUserId",
    "reminderMinutes",
    "linkedMaintenanceOrderId",
    "customDetails",
]:
    need(f"vehicle schedule UI missing marker: {marker}", marker in vehicle_service)
for marker in [
    "Future<List<Map<String, Object?>>> loadPersistentNotifications(",
    "erp_r88_materialize_maintenance_schedule_reminders",
    "authoritative inbox is read",
]:
    need(
        f"maintenance notification materialization missing marker: {marker}",
        marker in notification_center,
    )

# 10. CRM opportunity-to-sales linkage remains canonical and single-link. Lost
# is explicit, a Sales Order is opened/created from the opportunity, and the DB
# trigger projects Proposal -> Negotiation -> Won -> Closed from real workflow
# documents while cancellation projects Lost.
customer_service = text("lib/features/customer_service/pages/customer_service_page.dart")
sales_workflow = text("lib/features/sales/workflow/repositories/sales_workflow_repository.dart")
single_link = text("supabase/migrations/20260728004400_opportunity_sales_order_single_link.sql")
r37_crm = text("supabase/migrations/20260809124736_r37_full_functional_presentation_closure.sql")
r49_crm = text("supabase/migrations/20260810030000_r49_end_to_end_opportunity_lifecycle_readback.sql")

for marker in [
    "markLost(opportunity)",
    "findOrderByOpportunity(opportunity.id)",
    "SalesOrderDraftPage(",
    "opportunityId: opportunity.id",
    "OrderDetailsDialog(orderId: orderId, purchase: false)",
]:
    need(f"CRM opportunity sales UI missing marker: {marker}", marker in customer_service)
for marker in [
    "'opportunityId': opportunityId",
    "erp_r9_find_sales_order_by_opportunity",
    "await _reconcileOpportunityLinks();",
]:
    need(f"Sales workflow opportunity linkage missing marker: {marker}", marker in sales_workflow)
need(
    "CRM active Sales Order link is no longer unique per opportunity",
    "erp_sales_orders_one_active_per_opportunity_uq" in single_link
    and "where opportunity_id is not null" in single_link,
)
for marker in [
    "create trigger trg_r37_sales_order_opportunity",
    "erp_sync_opportunity_sales_lifecycle",
]:
    need(f"CRM lifecycle trigger missing marker: {marker}", marker in r37_crm)
for marker in [
    "v_stage:='proposal'",
    "v_stage:='negotiation'",
    "v_status:='won'",
    "v_stage:='closed'",
    "v_status:='lost'",
    "v_remaining<=0.001",
]:
    need(f"CRM canonical lifecycle missing marker: {marker}", marker in r49_crm)

if errors:
    print("R93 final closure verification FAILED")
    for error in errors:
        print(f" - {error}")
    raise SystemExit(1)

print("R93 final closure verification PASS")
print("  - accepted R92 historical migrations remain immutable")
print("  - verify:all/check include the complete R88-R93 static closure")
print("  - R92 revoked RPCs are unused across the complete Flutter lib tree")
print("  - purchase receipt create+approve is one approval-owned PostgreSQL action")
print("  - committed formatting is checked before any formatter mutation")
print("  - R89-R93 PostgreSQL runtime tests are wired to local Supabase only")
print("  - restricted-user runtime proves field masking and delete denial")
print("  - localized Arabic/Persian numeric entry cannot be silently discarded")
print("  - maintenance draft reopen keeps loading/error/vehicle fallback guards")
print("  - purchase receiving UI has no second approval action; sales delivery remains staged")
print("  - every vehicle keeps service schedules/history access and due reminders materialize")
print("  - opportunity Sales Order linkage remains unique and lifecycle-synchronized")
print("  - analyze, Flutter tests and web build remain mandatory")
