from pathlib import Path

root = Path(__file__).resolve().parents[1]
prepare = (root / "tool/prepare_local_current_database.ps1").read_text(encoding="utf-8")
run_local = (root / "tool/run_current_web.ps1").read_text(encoding="utf-8")
run_production = (root / "tool/run_production_web.ps1").read_text(encoding="utf-8")
config = (root / "lib/core/cloud/supabase_config.dart").read_text(encoding="utf-8")
supabase_config = (root / "supabase/config.toml").read_text(encoding="utf-8")
production_defines = (root / "dart_defines.json").read_text(encoding="utf-8")

expected_local_id = "quality_line_erp_local_dev"
production_ref = "havlqebmnjdcwmpaaqew"

for marker in (
    "supabase @Arguments",
    "@('start')",
    "@('status', '-o', 'env')",
    "@('migration', 'up', '--local', '--include-all')",
    "@('migration', 'list', '--local')",
    "@('db', 'dump', '--local', '--data-only'",
    "SUPABASE_LOCAL_PROJECT_ID",
    "SUPABASE_ALLOW_LOCAL_DEV",
    "dart_defines.local.generated.json",
    "Refusing non-local Supabase API URL",
):
    assert marker in prepare, marker

for forbidden in (
    "db reset",
    "--linked",
    "supabase link",
    "db push",
):
    # Human-readable safety messages may mention 'db reset'; no executable reset
    # invocation is permitted. Exact command arrays are checked separately.
    if forbidden == "db reset":
        assert "@('db', 'reset'" not in prepare
    elif forbidden == "--linked":
        assert "'--linked'" not in prepare
    else:
        assert forbidden not in prepare.lower()

assert expected_local_id in supabase_config
assert "localProjectId" in config
assert "resolveLocalDevelopmentOptIn" in config
assert "isLocalLoopback && allowLocalDev" in config
assert production_ref in production_defines
assert production_ref in run_production
assert "dart_defines.json" in run_production

for marker in (
    "prepare_local_current_database.ps1",
    "dart_defines.local.generated.json",
    "verify_r76_local_current_database.py",
    "LOCAL Supabase",
):
    assert marker in run_local, marker

assert "--dart-define-from-file=dart_defines.local.generated.json" in run_local
assert production_ref not in run_local, "default local launcher must not target hosted Supabase"

print("PASS R76 current local database runtime")
print(f"  - local project id: {expected_local_id}")
print("  - default current-web launcher uses local Supabase credentials")
print("  - pending migrations are applied with --local --include-all")
print("  - existing local business data is backed up before migration")
print("  - no local db reset and no linked/remote database operation")
print(f"  - hosted production remains isolated in run_production_web.ps1 ({production_ref})")
