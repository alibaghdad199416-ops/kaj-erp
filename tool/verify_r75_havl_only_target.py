from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
expected_ref = "havlqebmnjdcwmpaaqew"
expected_url = f"https://{expected_ref}.supabase.co"
expected_local_url = "http://127.0.0.1:54321"

errors = []

production_path = root / "dart_defines.production.json"
local_path = root / "dart_defines.json"
config_path = root / "lib/core/cloud/supabase_config.dart"
run_production_path = root / "tool/run_production_web.ps1"
run_local_path = root / "tool/run_current_web.ps1"

for path in (production_path, local_path, config_path, run_production_path, run_local_path):
    if not path.is_file():
        errors.append(f"missing operational runtime file: {path.relative_to(root)}")

if production_path.is_file():
    production = json.loads(production_path.read_text(encoding="utf-8"))
    key = str(production.get("SUPABASE_PUBLISHABLE_KEY") or "")
    if production.get("SUPABASE_URL") != expected_url:
        errors.append("production runtime does not target the approved havl Supabase project")
    if not key.startswith("sb_publishable_"):
        errors.append("production runtime does not use a publishable browser key")
    if "service_role" in key.lower() or key.lower().startswith("sb_secret_"):
        errors.append("production runtime contains a secret Supabase key")
    if "/rest/v1" in str(production.get("SUPABASE_URL") or ""):
        errors.append("production runtime must use the Supabase project base URL")

if local_path.is_file():
    local = json.loads(local_path.read_text(encoding="utf-8"))
    if local.get("SUPABASE_URL") != expected_local_url:
        errors.append("dart_defines.json must remain the Local Supabase test baseline")

if config_path.is_file():
    config = config_path.read_text(encoding="utf-8")
    for marker in (
        expected_ref,
        "expectedProductionUrl",
        "isHostedProductionTarget",
        "SUPABASE_ALLOW_LOCAL_DEV",
        "validateRuntime",
    ):
        if marker not in config:
            errors.append(f"SupabaseConfig is missing separated runtime guard: {marker}")

if run_production_path.is_file():
    production_runner = run_production_path.read_text(encoding="utf-8")
    for marker in (expected_ref, "dart_defines.production.json"):
        if marker not in production_runner:
            errors.append(f"production launcher is missing target marker: {marker}")

if run_local_path.is_file():
    local_runner = run_local_path.read_text(encoding="utf-8")
    if "dart_defines.local.generated.json" not in local_runner:
        errors.append("local launcher does not use its generated Local Supabase runtime")

package = json.loads((root / "package.json").read_text(encoding="utf-8"))
scripts = package.get("scripts", {})
if "run_current_web.ps1" not in scripts.get("run:web:local", ""):
    errors.append("explicit Local Supabase launcher is missing")
if "run_production_web.ps1" not in scripts.get("run:web:production", ""):
    errors.append("explicit hosted production launcher is missing")

if errors:
    print("FAIL R75 approved production target verification")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS R75 approved production target verification")
print(f"  - production Supabase project: {expected_ref}")
print(f"  - production API: {expected_url}")
print(f"  - local test API remains separate: {expected_local_url}")
print("  - production uses only a publishable browser key")
print("  - production and Local Supabase launchers remain explicitly separated")
