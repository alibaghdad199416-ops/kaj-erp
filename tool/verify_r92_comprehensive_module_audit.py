from pathlib import Path
import re
import json

from verification_text import contains_code

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def text(rel: str) -> str:
    path = ROOT / rel
    if not path.exists():
        errors.append(f"missing file: {rel}")
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def need(label: str, condition: bool) -> None:
    if not condition:
        errors.append(label)


migration_rel = "supabase/migrations/20260820133000_r92_comprehensive_module_audit.sql"
migration = text(migration_rel)
low = migration.lower()
need("R92 migration missing", bool(migration))
need("R92 must be forward-only", "begin;" in low and "commit;" in low)
need(
    "R92 migration contains destructive schema/table operation",
    not re.search(r"\b(drop\s+schema|drop\s+table|truncate\s+table)\b", migration, re.I),
)

# 1. Journal balance must be server-computed after the R9 filtered read boundary.
for token in [
    "erp_r92_list_journal_entries",
    "erp_r9_list_cloud_master_records",
    "erp_cloud_user_can_view_field(p_company_id,'accounting','debit'",
    "erp_cloud_user_can_view_field(p_company_id,'accounting','credit'",
    "erp_cloud_user_can_view_field(p_company_id,'accounting','balances'",
    "'balanceDifference'",
    "'isBalanced'",
]:
    need(f"R92 journal-balance contract missing {token}", token in migration)
need(
    "R92 journal balance reconstructs raw hidden values",
    "from public.erp_journal_entries" not in migration[
        migration.find("erp_r92_list_journal_entries") : migration.find("-- ---------------------------------------------------------------------------\n-- 2.")
    ].lower(),
)

journal_model = text("lib/features/accounting/models/journal_entry_model.dart")
accounting_page = text("lib/features/accounting/pages/accounting_page.dart")
accounting_repo = text("lib/features/accounting/repositories/accounting_repository.dart")
need("Journal model missing balanceDifference", "final double? balanceDifference;" in journal_model)
need("Journal model missing server balance state", "final bool? balanceVerified;" in journal_model)
need("Accounting repository does not use R92 journal reader", "erp_r92_list_journal_entries" in accounting_repo)
for token in ["إجمالي المدين", "إجمالي الدائن", "الفرق", "متوازن", "غير متوازن"]:
    need(f"Accounting journal UI missing {token}", token in accounting_page)
need(
    "Journal difference is shown without server-verification gate",
    "if (entry.hasVerifiedBalance)" in accounting_page,
)

# 2. Inventory operational effects may not bypass approved workflow documents.
for signature in [
    "erp_r49_receive_inventory_stock",
    "erp_receive_inventory_stock",
    "erp_sell_inventory_stock",
]:
    need(
        f"Direct inventory mutation endpoint {signature} not revoked from authenticated",
        re.search(
            rf"revoke\s+all\s+on\s+function\s+public\.{re.escape(signature)}\([\s\S]*?\)\s+from\s+public,anon,authenticated",
            migration,
            re.I,
        )
        is not None,
    )

inventory_repo = text("lib/features/inventory/data/inventory_repository.dart")
inventory_controller = text("lib/features/inventory/controllers/inventory_controller.dart")
need("Inventory repository still exposes direct receiveStock", "Future<void> receiveStock(" not in inventory_repo)
need("Inventory repository still exposes direct sellStock", "Future<void> sellStock(" not in inventory_repo)
need("Inventory controller still exposes direct receiveStock", "Future<void> receiveStock(" not in inventory_controller)
need("Inventory controller still exposes direct sellStock", "Future<void> sellStock(" not in inventory_controller)

# Hidden item type must not silently become a stock item. New objects may keep a
# constructor default for explicit local creation, but persisted DB rows must use
# the current defensive reader without a stock fallback when the field is hidden.
inv_model = text("lib/features/inventory/models/inventory_model.dart")
from_map_start = inv_model.find("factory InventoryModel.fromMap")
from_map_end = inv_model.find("factory InventoryModel.fromCloudMap", from_map_start)
from_map = inv_model[from_map_start:from_map_end] if from_map_start >= 0 and from_map_end > from_map_start else ""
need(
    "Persisted InventoryModel does not read itemType through ModelValueReader",
    contains_code(
        from_map,
        """
        itemType: ModelValueReader.string(
          map,
          'itemType',
          aliases: const ['item_type', 'productType', 'product_type'],
        ).toLowerCase()
        """,
    ),
)
item_type_match = re.search(
    r"itemType\s*:\s*ModelValueReader\.string\((.*?)\)\.toLowerCase\(\)",
    from_map,
    re.S,
)
need(
    "Persisted InventoryModel still defaults hidden itemType to stock",
    item_type_match is not None and "fallback" not in item_type_match.group(1),
)
need("Stock semantics are not explicit", "bool get isStockItem => itemType == 'stock';" in inv_model)
need(
    "Inventory persisted item-type behavior test missing",
    (ROOT / "test/features/inventory/inventory_model_item_type_visibility_test.dart").is_file(),
)

# 3. Exact sale/purchase delete permissions.
for token in [
    "erp_r92_delete_cloud_sale",
    "permission_denied:sales.delete",
    "erp_r92_delete_cloud_purchase",
    "permission_denied:purchases.delete",
]:
    need(f"R92 exact commercial delete boundary missing {token}", token in migration)
need("Sales repository does not use R92 delete", "erp_r92_delete_cloud_sale" in text("lib/features/sales/data/sale_repository.dart"))
need("Purchase repository does not use R92 delete", "erp_r92_delete_cloud_purchase" in text("lib/features/purchases/repositories/purchase_repository.dart"))

# 4. Cross-module workflow selectors must use field-aware R92 RPCs and old
# selectors/allocation contexts must be internal-only.
selector_tokens = [
    "erp_r92_list_workflow_cash_accounts",
    "erp_r92_list_workflow_warehouses",
    "erp_r92_list_workflow_settlement_accounts",
    "erp_r92_get_commercial_order_allocation_context",
    "erp_cloud_user_can_view_field(p_company_id,'cashbox','name'",
    "erp_cloud_user_can_view_field(p_company_id,'cashbox','currency'",
    "erp_cloud_user_can_view_field(p_company_id,'warehouses','name'",
    "erp_cloud_user_can_view_field(p_company_id,'accounting','accountCode'",
    "erp_cloud_user_can_view_field(p_company_id,'inventory','quantity'",
    "erp_cloud_user_can_view_field(p_company_id,'cars','warehouseId'",
]
for token in selector_tokens:
    need(f"R92 selector field boundary missing {token}", token in migration)
for legacy in [
    "erp_r49_list_cloud_active_cash_accounts",
    "erp_r49_list_cloud_active_warehouses",
    "erp_list_cloud_settlement_accounts",
    "erp_r49_get_commercial_order_allocation_context",
    "erp_get_commercial_order_allocation_context",
]:
    need(
        f"Legacy unfiltered selector {legacy} remains browser-executable",
        re.search(
            rf"revoke\s+all\s+on\s+function\s+public\.{re.escape(legacy)}\([\s\S]*?from\s+public,anon,authenticated",
            migration,
            re.I,
        )
        is not None,
    )

for rel in [
    "lib/features/sales/workflow/repositories/sales_workflow_repository.dart",
    "lib/features/purchases/repositories/purchase_workflow_repository.dart",
    "lib/features/maintenance/data/maintenance_repository.dart",
]:
    src = text(rel)
    need(f"{rel} still uses legacy active cash-account selector", "erp_r49_list_cloud_active_cash_accounts" not in src)
    need(f"{rel} still uses legacy settlement selector", "erp_list_cloud_settlement_accounts" not in src)

# 5. Professional accounting reads are RPC-bound and direct table reads are
# restrictively permission-guarded.
pro_repo = text("lib/features/accounting/repositories/professional_accounting_repository.dart")
need("Professional accounting repository does not use R92 record reader", "erp_r92_list_professional_accounting_records" in pro_repo)
need("Professional accounting repository does not use guarded branch reader", "erp_r92_list_accounting_branches" in pro_repo)
need(
    "Professional accounting repository still uses direct Supabase table reads",
    re.search(r"(?:_client|client|supabase|Supabase\.instance\.client)\.from\(", pro_repo) is None,
)
for policy in [
    "erp_r92_cost_centers_select_guard",
    "erp_r92_accounting_projects_select_guard",
    "erp_r92_fiscal_years_select_guard",
    "erp_r92_fiscal_periods_select_guard",
]:
    need(f"R92 restrictive RLS policy missing {policy}", f"create policy {policy}" in low and "as restrictive for select to authenticated" in low)

# 6. Internal accounting/payment engines are service-only; current guarded
# wrappers remain the browser APIs.
for internal in [
    "erp_sync_accounting_master_data",
    "erp_ensure_fx_clearing_account",
    "erp_execute_secure_linked_payment_v1",
    "erp_apply_cloud_workflow_invoice_payment",
    "erp_apply_cloud_workflow_invoice_payment_batch",
    "erp_v762_apply_workflow_payment",
    "erp_pay_cloud_sales_workflow_invoice",
    "erp_pay_cloud_purchase_workflow_invoice",
    "erp_v737_record_maintenance_payment",
    "erp_transfer_cloud_cash_v2",
    "erp_transfer_cloud_cash_v3",
    "erp_transfer_cloud_cash_v4",
    "erp_transfer_cloud_cash_v5",
    "erp_v2300_transfer_cloud_cash",
]:
    need(
        f"Internal accounting/payment RPC {internal} not revoked from browser roles",
        re.search(
            rf"revoke\s+all\s+on\s+function\s+public\.{re.escape(internal)}\([\s\S]*?from\s+public,anon,authenticated",
            migration,
            re.I,
        )
        is not None,
    )

# 7. The seven audited feature trees should have no direct Data API .from()
# calls. Map.from() is intentionally excluded by the receiver pattern.
audited_roots = [
    "lib/features/accounting",
    "lib/features/inventory",
    "lib/features/sales",
    "lib/features/purchases",
    "lib/features/maintenance",
    "lib/features/crm",
    "lib/features/customer_service",
]
direct_pattern = re.compile(r"(?:_client|client|supabase|Supabase\.instance\.client)\.from\(")
for rel_root in audited_roots:
    path = ROOT / rel_root
    if not path.exists():
        continue
    for dart in path.rglob("*.dart"):
        src = dart.read_text(encoding="utf-8", errors="replace")
        if direct_pattern.search(src):
            errors.append(f"direct Data API table access remains: {dart.relative_to(ROOT)}")


# Opportunities are implemented under Customer Service in the current source.
opportunity_repo = text("lib/features/customer_service/repositories/opportunity_repository.dart")
need("Opportunity repository does not use tenant/field-scoped R84 reader", "erp_r84_list_opportunities" in opportunity_repo)
r84 = text("supabase/migrations/20260816013000_r84_user_record_scope_atomic_profile_closure.sql")
for token in [
    "create or replace function public.erp_r84_list_opportunities",
    "erp_r9_filter_readable_json",
    "'opportunities'",
    "customer_service.view",
    "erp_r84_record_visible",
]:
    need(f"Opportunity R84 read boundary missing {token}", token in r84)


# R92 ACL tightening must not revoke any RPC still invoked by the audited
# Flutter modules. This guards against security hardening accidentally breaking
# a live workflow at runtime.
rpc_pattern = re.compile(r"\.rpc\(\s*['\"]([^'\"]+)['\"]")
used_rpcs: set[str] = set()
for rel_root in audited_roots:
    path = ROOT / rel_root
    if not path.exists():
        continue
    for dart in path.rglob("*.dart"):
        used_rpcs.update(rpc_pattern.findall(dart.read_text(encoding="utf-8", errors="replace")))
revoked_rpcs: set[str] = set()
for statement in migration.split(";"):
    if re.search(r"\brevoke\b", statement, re.I) and re.search(r"\bauthenticated\b", statement, re.I):
        match = re.search(r"function\s+public\.([A-Za-z0-9_]+)\s*\(", statement, re.I)
        if match:
            revoked_rpcs.add(match.group(1))
array_match = re.search(r"foreach\s+v_name\s+in\s+array\s+array\[(.*?)\]\s+loop", migration, re.S | re.I)
if array_match:
    revoked_rpcs.update(re.findall(r"'([^']+)'", array_match.group(1)))
for conflict in sorted(used_rpcs & revoked_rpcs):
    errors.append(f"R92 revokes RPC still used by Flutter: {conflict}")

# 8. R92 must not rewrite historical migrations.
# Compare by convention: it must be the only R92 migration and later R88-R91
# files remain separate instead of being folded into R92.
r92_files = sorted((ROOT / "supabase/migrations").glob("*r92*.sql"))
need("R92 migration count is not exactly one", len(r92_files) == 1)
for required in [
    "20260819210000_r88_phase11_operational_financial_closure.sql",
    "20260820090000_r89_phase11_completion_closure.sql",
    "20260820113000_r90_phase11_final_acceptance_closure.sql",
    "20260820124500_r91_phase11_material_issue_acceptance_closure.sql",
]:
    need(f"Required prior forward migration missing: {required}", (ROOT / "supabase/migrations" / required).exists())

if errors:
    print("R92 comprehensive module audit FAILED")
    for error in errors:
        print(f" - {error}")
    raise SystemExit(1)

print("R92 comprehensive module audit PASS")
print("  - journal balance is server-computed behind accounting field permissions")
print("  - direct receive/sell inventory bypasses are closed")
print("  - Sales/Purchases deletion uses exact module permissions")
print("  - workflow cashbox/warehouse/account selectors are field-aware")
print("  - Professional Accounting direct-table reads are closed by RPC + restrictive RLS")
print("  - low-level accounting/payment/FX engines are internal-only")
print("  - audited module repositories do not use direct Data API table reads")
