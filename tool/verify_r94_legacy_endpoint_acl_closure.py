from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260820233000_r94_legacy_endpoint_acl_closure.sql"
RUNTIME = ROOT / "supabase/tests/verify_r94_legacy_endpoint_acl_runtime.sql"
errors: list[str] = []

LEGACY_SIGNATURES = (
    "erp_r28_get_commercial_order_complete_details(uuid,uuid,boolean)",
    "erp_r57_commercial_reconciliation(uuid,uuid,text)",
    "erp_r62_get_commercial_order_snapshot(uuid,uuid,boolean)",
    "erp_r57_maintenance_cost_reconciliation(uuid,uuid)",
    "erp_r57_maintenance_material_issue_state(uuid,uuid)",
    "erp_r64_get_maintenance_order_snapshot(uuid,uuid)",
    "erp_r88_list_maintenance_payments(uuid,uuid)",
    "erp_r88_vehicle_service_card(uuid,text)",
    "erp_r42_list_cash_accounts(uuid)",
    "erp_r22_cloud_cash_account_balances(uuid)",
    "erp_r22_cloud_cash_ledger_reconciliation(uuid)",
    "erp_r42_save_cash_account(uuid,jsonb)",
    "erp_delete_cloud_cash_account(uuid,text)",
    "erp_r22_transfer_cloud_cash(uuid,text,text,numeric,numeric,numeric,timestamptz,text)",
    "erp_r22_post_cloud_cash_transaction(uuid,jsonb,boolean)",
    "erp_delete_cloud_cash_transaction(uuid,text)",
    "erp_delete_cloud_cash_transfer(uuid,text)",
)

SECURE_RPC_NAMES = (
    "erp_r89_get_commercial_order_snapshot",
    "erp_r90_get_maintenance_order_snapshot",
    "erp_r89_maintenance_cost_reconciliation",
    "erp_r90_maintenance_material_issue_state",
    "erp_r90_list_maintenance_payments",
    "erp_r90_vehicle_service_card",
    "erp_r90_list_cash_accounts",
    "erp_r90_cash_account_balances",
    "erp_r90_cash_ledger_reconciliation",
    "erp_r90_save_cash_account",
    "erp_r90_delete_cash_account",
    "erp_r90_transfer_cloud_cash",
    "erp_r90_post_cash_transaction",
    "erp_r90_delete_cash_transaction",
    "erp_r90_delete_cash_transfer",
)


def need(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def read(path: Path) -> str:
    if not path.is_file():
        errors.append(f"missing required file: {path.relative_to(ROOT)}")
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


migration = read(MIGRATION)
runtime = read(RUNTIME)
need(
    "begin;" in migration.lower() and "commit;" in migration.lower(),
    "R94 migration is not forward transactional",
)
need(
    not re.search(
        r"\b(drop\s+schema|drop\s+table|truncate\s+table|db\s+reset)\b",
        migration,
        re.I,
    ),
    "R94 migration contains destructive schema/data operations",
)

for signature in LEGACY_SIGNATURES:
    escaped = re.escape(signature)
    need(
        re.search(
            rf"revoke\s+all\s+on\s+function\s+public\.{escaped}\s+from\s+public\s*,\s*anon\s*,\s*authenticated\s*;",
            migration,
            re.I,
        )
        is not None,
        f"R94 does not revoke PUBLIC/anon/authenticated from legacy endpoint: {signature}",
    )
    need(
        re.search(
            rf"grant\s+execute\s+on\s+function\s+public\.{escaped}\s+to\s+service_role\s*;",
            migration,
            re.I,
        )
        is not None,
        f"R94 does not preserve service_role execution for legacy endpoint: {signature}",
    )
    need(signature in runtime, f"R94 runtime omits legacy endpoint: {signature}")

for marker in (
    "has_function_privilege('authenticated', v_sig, 'execute')",
    "has_function_privilege('anon', v_sig, 'execute')",
    "has_function_privilege('service_role', v_sig, 'execute')",
    "r94_secure_endpoint_not_executable_by_authenticated",
):
    need(marker in runtime, f"R94 runtime missing ACL assertion: {marker}")

# The browser must use only the governed R89/R90 API. Scan literal .rpc calls
# across the complete Flutter lib tree rather than a hand-picked repository list.
legacy_names = {signature.split("(", 1)[0] for signature in LEGACY_SIGNATURES}
rpc_pattern = re.compile(r"\.rpc\(\s*['\"]([^'\"]+)['\"]")
legacy_calls: list[str] = []
secure_calls: set[str] = set()
for dart in (ROOT / "lib").rglob("*.dart"):
    source = dart.read_text(encoding="utf-8", errors="replace")
    for rpc in rpc_pattern.findall(source):
        if rpc in legacy_names:
            legacy_calls.append(f"{rpc} @ {dart.relative_to(ROOT)}")
        if rpc in SECURE_RPC_NAMES:
            secure_calls.add(rpc)
need(
    not legacy_calls,
    "Flutter still calls R94-revoked legacy RPCs: " + ", ".join(legacy_calls),
)
for rpc in SECURE_RPC_NAMES:
    need(rpc in secure_calls, f"governed browser RPC is not used by Flutter: {rpc}")

# R90 runtime is intentionally rerun after R94 migration. Its inherited-role
# check must now pass because PUBLIC EXECUTE has been removed.
r90_runtime = read(ROOT / "supabase/tests/verify_r90_phase11_runtime.sql")
need(
    "r90_legacy_endpoint_bypass_still_exposed" in r90_runtime,
    "R90 inherited legacy bypass regression assertion is missing",
)

# R94 must be part of both the static current-project gate and the Local runtime
# suite, and the Local schema synchronizer must require the R94 migration.
verify_project = read(ROOT / "tool/verify_project.py")
runner = read(ROOT / "tool/run_r89_r92_local_runtime_tests.py")
schema_sync = read(ROOT / "tool/ensure_local_supabase_schema.py")
need(
    '"verify_r94_legacy_endpoint_acl_closure.py"' in verify_project,
    "verify_project does not execute the R94 static closure",
)
need(
    '"supabase/tests/verify_r94_legacy_endpoint_acl_runtime.sql"' in runner
    and "R89-R94 LOCAL PostgreSQL runtime verification PASS" in runner,
    "Local runtime runner does not include R94",
)
need(
    '"20260820233000"' in schema_sync
    and "required R88-R94 migrations" in schema_sync
    and "erp_r57_maintenance_cost_reconciliation" in schema_sync,
    "Local schema synchronizer does not require and validate R94",
)

# Database/runtime identity is centralized in AppReleaseInfo and consumed by the
# web generator/verifier. This prevents schema R94 from shipping as an R93/R74
# cache/database contract.
release = read(ROOT / "lib/core/release/app_release_info.dart")
prepare_web = read(ROOT / "tool/prepare_web_release.py")
verify_web = read(ROOT / "tool/verify_web_release.py")
web_index = read(ROOT / "web/index.html")
web_version = read(ROOT / "web/version.json")
for marker in (
    "r94-legacy-acl-runtime-closure-20260820",
    "static const String databaseContract = 'R94'",
):
    need(marker in release, f"R94 canonical release metadata missing: {marker}")
need(
    'dart_string("databaseContract")' in prepare_web,
    "web release generator does not consume canonical databaseContract",
)
need(
    'release_string("databaseContract")' in verify_web,
    "web release verifier does not consume canonical databaseContract",
)
need(
    "22.9.8+229008-r94-legacy-acl-runtime-closure-20260820" in web_index,
    "web fallback runtime identity is not R94",
)
need(
    '"databaseContract": "R94"' in web_version
    and '"runtimeToken": "r94-legacy-acl-runtime-closure-20260820"' in web_version,
    "committed web/version.json is not synchronized to R94",
)

if errors:
    print("R94 legacy endpoint ACL closure FAILED")
    for error in errors:
        print(f" - {error}")
    raise SystemExit(1)

print("R94 legacy endpoint ACL closure PASS")
print("  - all R90 legacy browser bypasses revoke inherited PUBLIC/anon/authenticated EXECUTE")
print("  - service_role retains explicit internal execution")
print("  - Flutter has no literal calls to the revoked legacy RPC set")
print("  - governed R89/R90 browser wrappers remain the active client API")
print("  - R94 is wired into current-project static verification and Local runtime")
print("  - Local schema synchronization requires and validates the R94 ACL closure")
print("  - web runtime/database metadata is centrally synchronized to R94")
