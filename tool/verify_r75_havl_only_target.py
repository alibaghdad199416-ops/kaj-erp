from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
expected_ref = "havlqebmnjdcwmpaaqew"
expected_url = f"https://{expected_ref}.supabase.co"

runtime_files = [
    root / "dart_defines.json",
    root / "dart_defines.example.json",
    root / "lib/core/cloud/supabase_config.dart",
    root / "tool/configure_production.ps1",
    root / "tool/deploy_production.ps1",
    root / "tool/run_current_web.ps1",
    root / "tool/repair_r72_current_database_schema.ps1",
    root / "tool/repair_r74_auth_tenant_runtime.ps1",
    root / "tool/verify_deployment_target.py",
    root / "tool/verify_r71_current_runtime_source.py",
    root / "tool/verify_r71_supabase_runtime_isolation.py",
    root / "tool/verify_r72_dashboard_database_contract.py",
    root / "tool/verify_r74_authenticated_tenant_runtime.py",
]

production = root / "dart_defines.production.json"
if production.exists():
    runtime_files.append(production)

hosted_ref_pattern = re.compile(r"https://([a-z0-9]+)\.supabase\.co", re.I)
errors = []
seen_expected = set()

for path in runtime_files:
    if not path.is_file():
        errors.append(f"missing operational runtime file: {path.relative_to(root)}")
        continue
    text = path.read_text(encoding="utf-8")
    refs = {match.group(1).lower() for match in hosted_ref_pattern.finditer(text)}
    unexpected = sorted(ref for ref in refs if ref != expected_ref)
    if unexpected:
        errors.append(
            f"{path.relative_to(root)} contains unexpected Supabase project(s): "
            + ", ".join(unexpected)
        )
    if expected_ref in text or expected_url in text:
        seen_expected.add(path.relative_to(root).as_posix())

required_markers = {
    "dart_defines.json",
    "dart_defines.example.json",
    "lib/core/cloud/supabase_config.dart",
    "tool/configure_production.ps1",
    "tool/deploy_production.ps1",
    "tool/run_current_web.ps1",
    "tool/verify_deployment_target.py",
}
missing_expected = sorted(required_markers - seen_expected)
if missing_expected:
    errors.append(
        "approved Supabase project marker is missing from: "
        + ", ".join(missing_expected)
    )

config = (root / "lib/core/cloud/supabase_config.dart").read_text(encoding="utf-8")
if f"expectedProductionProjectRef =\n      '{expected_ref}'" not in config:
    errors.append("SupabaseConfig does not fail-closed to the approved project ref")
if "projectRef != expectedProductionProjectRef" not in config:
    errors.append("SupabaseConfig runtime project guard is missing")

if errors:
    print("FAIL R75 HAVL-only Supabase target verification")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS R75 HAVL-only Supabase target verification")
print(f"  - only hosted project allowed: {expected_ref}")
print(f"  - only hosted URL allowed: {expected_url}")
print("  - runtime, repair, deploy, and verification paths reject other hosted projects")
