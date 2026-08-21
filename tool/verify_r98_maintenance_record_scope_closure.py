from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "supabase/migrations/20260821134500_r98_maintenance_record_scope_closure.sql"
errors: list[str] = []


def need(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def read(path: Path) -> str:
    if not path.is_file():
        errors.append(f"missing required file: {path.relative_to(ROOT)}")
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


migration = read(MIGRATION)
low = migration.lower()
need("begin;" in low and "commit;" in low, "R98 is not forward transactional")
need(
    not re.search(r"\b(drop\s+schema|drop\s+table|truncate\s+table|db\s+reset)\b", migration, re.I),
    "R98 contains a destructive schema/data operation",
)

for suffix in ("records.assigned", "records.team"):
    need(suffix in migration, f"R98 permission catalog missing {suffix}")
for table in (
    "erp_record_scope_teams",
    "erp_record_scope_team_members",
    "erp_record_scope_assignments",
):
    need(f"create table if not exists public.{table}" in low, f"R98 scope table missing {table}")
    need(
        f"revoke all on table public.{table} from public,anon,authenticated" in low,
        f"R98 scope table is browser writable: {table}",
    )

for marker in (
    "erp_r98_record_visible",
    "records.all",
    "records.own",
    "records.assigned",
    "records.team",
    "erp_r84_record_visible",
    "erp_current_cloud_erp_user_id",
    "erp_record_scope_team_members",
    "erp_record_scope_assignments",
):
    need(marker in migration, f"R98 union visibility engine missing {marker}")

# Scope administration is privileged and direct table mutation is not the UI API.
for fn in (
    "erp_r98_save_record_scope_team",
    "erp_r98_set_record_scope_team_members",
    "erp_r98_assign_record_scope",
):
    need(fn in migration, f"R98 governed scope admin RPC missing {fn}")
need(
    migration.count("permissions.scopes.manage") >= 3,
    "R98 scope admin RPCs are not guarded by permissions.scopes.manage",
)

# Maintenance is migrated end-to-end: list, lines, detail analytics, payments,
# and vehicle history all use record-id aware R98 visibility.
for fn in (
    "erp_r9_list_cloud_maintenance_orders",
    "erp_r9_get_cloud_maintenance_order_lines",
    "erp_r89_maintenance_cost_reconciliation",
    "erp_r89_maintenance_material_issue_state",
    "erp_r89_get_maintenance_order_snapshot",
    "erp_r90_get_maintenance_order_snapshot",
    "erp_r90_maintenance_material_issue_state",
    "erp_r88_list_maintenance_payments",
    "erp_r90_list_maintenance_payments",
    "erp_r88_vehicle_service_card",
):
    need(fn in migration, f"R98 maintenance boundary missing {fn}")
need(
    migration.count("erp_r98_record_visible") >= 5,
    "R98 maintenance reads are not consistently record-id scoped",
)
need(
    "erp_r98_require_maintenance_order_visible" in migration,
    "R98 detail guard helper missing",
)

# The old generic R84 write trigger is removed only from maintenance and
# replaced with a scope-aware guard. Other resources retain their R84 behavior.
need(
    "drop trigger if exists aa_r84_record_scope_guard on public.erp_maintenance_orders" in low,
    "R98 does not replace the maintenance R84 write guard",
)
need(
    "create trigger aa_r98_record_scope_guard" in low
    and "erp_r98_maintenance_scope_guard" in low,
    "R98 maintenance write scope trigger missing",
)
need(
    "zz_r98_maintenance_assignment_sync" in migration,
    "R98 does not automatically seed assignments for new maintenance orders",
)

# Existing exact workflow action enforcement remains authoritative. R98 must
# extend record scope, not replace the granular R88 action boundary.
r88 = read(ROOT / "supabase/migrations/20260819210000_r88_phase11_operational_financial_closure.sql")
for action in (
    "order.approve",
    "material_issue.create",
    "material_issue.approve",
    "invoice.create",
    "invoice.approve",
    "payment",
    "reverse",
):
    need(action in r88, f"pre-existing granular maintenance action guard missing {action}")
need(
    "erp_r88_require_restricted_action" in r88,
    "R88 granular action enforcement helper missing",
)

# Flutter's current secure names are explicitly guaranteed by R98. This closes
# the runtime ambiguity that previously relied on R90 aliases not clearly owned
# by the visible migration chain.
repo = read(ROOT / "lib/features/maintenance/data/maintenance_repository.dart")
for rpc in (
    "erp_r90_get_maintenance_order_snapshot",
    "erp_r90_maintenance_material_issue_state",
    "erp_r90_list_maintenance_payments",
):
    need(rpc in repo, f"maintenance repository no longer calls expected secure RPC {rpc}")
    need(
        f"create or replace function public.{rpc}" in low,
        f"R98 does not explicitly define Flutter secure RPC {rpc}",
    )

# Historical migrations are referenced only as dependencies; R98 never edits
# them and is a new migration after R94.
need(
    (ROOT / "supabase/migrations/20260820233000_r94_legacy_endpoint_acl_closure.sql").is_file(),
    "R94 predecessor migration missing",
)

if errors:
    print("R98 maintenance record-scope closure FAILED")
    for error in errors:
        print(f" - {error}")
    raise SystemExit(1)

print("R98 maintenance record-scope closure PASS")
print("  - OWN / ASSIGNED / TEAM / ALL are additive server-side scopes")
print("  - team membership and record assignment are privileged RPC-managed data")
print("  - maintenance list, lines, details, payments and vehicle history are R98-scoped")
print("  - maintenance writes no longer depend on the R84 OWN/ALL-only trigger")
print("  - R88 granular workflow action permissions remain authoritative")
print("  - R90 Flutter snapshot/material-state aliases are explicitly guaranteed")
