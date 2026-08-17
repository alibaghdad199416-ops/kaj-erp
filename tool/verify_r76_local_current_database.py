from pathlib import Path

root = Path(__file__).resolve().parents[1]
prepare = (root / "tool/prepare_local_current_database.ps1").read_text(encoding="utf-8")
run_local = (root / "tool/run_current_web.ps1").read_text(encoding="utf-8")
run_production = (root / "tool/run_production_web.ps1").read_text(encoding="utf-8")
package = (root / "package.json").read_text(encoding="utf-8")
config = (root / "lib/core/cloud/supabase_config.dart").read_text(encoding="utf-8")
supabase_config = (root / "supabase/config.toml").read_text(encoding="utf-8")
active_defines = (root / "dart_defines.json").read_text(encoding="utf-8")
seed = (root / "supabase/seed.sql").read_text(encoding="utf-8")
gitignore = (root / ".gitignore").read_text(encoding="utf-8")

expected_local_id = "quality_line_erp_local_dev"
expected_local_url = "http://127.0.0.1:54321"
known_orphans = (
    "20260815044500",
    "20260815055000",
    "20260815060000",
    "20260815080000",
    "20260815083000",
    "20260815083800",
    "20260815120500",
)

for marker in (
    "supabase @Arguments",
    "@('start')",
    "@('status', '-o', 'env')",
    "@('migration', 'up', '--local', '--include-all')",
    "@('migration', 'list', '--local')",
    "@('db', 'dump', '--local', '--data-only'",
    "@('db', 'dump', '--local', '--file'",
    "SUPABASE_LOCAL_PROJECT_ID",
    "SUPABASE_ALLOW_LOCAL_DEV",
    "dart_defines.local.generated.json",
    "Refusing non-local Supabase API URL",
    "UTF8Encoding($false)",
    "KnownOrphanedLocalMigrationVersions",
    "migration repair",
    "'--status', 'reverted', '--local'",
    "Refusing automatic migration-history repair",
    "Retrying forward-only local migration update after history reconciliation",
):
    assert marker in prepare, marker

for version in known_orphans:
    assert version in prepare, version

# No executable destructive or remote database command may exist in the local
# repair path. Human-readable safety messages may mention those command names.
assert "@('db', 'reset'" not in prepare
assert "@('db', 'push'" not in prepare
assert "@('link'" not in prepare
assert "'--linked'" not in prepare

# Migration-history repair must be fail-closed to the exact known legacy set.
assert "$_ -notin $KnownOrphanedLocalMigrationVersions" in prepare
assert "migration-history drift" in prepare
assert "tracking history only" in prepare

assert expected_local_id in supabase_config
assert "localProjectId" in config
assert "resolveLocalDevelopmentOptIn" in config
assert "!allowLocalDev" in config and "_isLoopback(uri.host)" in config
assert expected_local_url in active_defines
assert ".supabase.co" not in active_defines
assert "dart_defines.json" in run_production
assert "Existing local business data is intentionally preserved" in seed

for marker in (
    "prepare_local_current_database.ps1",
    "dart_defines.local.generated.json",
    "verify_r76_local_current_database.py",
    "LOCAL Supabase",
):
    assert marker in run_local, marker

assert "--dart-define-from-file=dart_defines.local.generated.json" in run_local
assert ".supabase.co" not in run_local, "default local launcher must not target Hosted Supabase"

for marker in (
    '"run:web": "powershell -NoProfile -ExecutionPolicy Bypass -File tool/run_current_web.ps1"',
    '"run:web:local": "powershell -NoProfile -ExecutionPolicy Bypass -File tool/run_current_web.ps1"',
    '"db:local:update": "powershell -NoProfile -ExecutionPolicy Bypass -File tool/prepare_local_current_database.ps1"',
):
    assert marker in package, marker

assert ".local_backups/" in gitignore
assert "dart_defines.local.generated.json" in gitignore

print("PASS R76 current local database runtime")
print(f"  - local project id: {expected_local_id}")
print("  - npm run run:web launches local Supabase")
print("  - local credentials are read from supabase status, never from hosted defines")
print("  - existing local data + schema are backed up before migration")
print("  - seven known orphaned migration-history rows are repaired locally only")
print("  - unexpected migration-history drift fails closed")
print("  - pending migrations are then applied with --local --include-all")
print("  - no local db reset and no linked/remote database operation")
print("  - active dart_defines.json is Local Supabase only")
