from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[1]
expected_local_id = "quality_line_erp_local_dev"
expected_url = "http://127.0.0.1:54321"

# R75's original purpose was to prevent runtime drift to an unapproved backend.
# The approved backend is now Local Supabase only.
runtime_files = [
    root / "dart_defines.json",
    root / "dart_defines.example.json",
    root / "lib/core/cloud/supabase_config.dart",
    root / "tool/run_current_web.ps1",
    root / "tool/prepare_local_current_database.ps1",
]

hosted_pattern = re.compile(r"https://[a-z0-9]+\.supabase\.co", re.I)
errors = []
seen_local = set()

for path in runtime_files:
    if not path.is_file():
        errors.append(f"missing operational runtime file: {path.relative_to(root)}")
        continue
    text = path.read_text(encoding="utf-8")
    if hosted_pattern.search(text):
        errors.append(f"{path.relative_to(root)} still contains a Hosted Supabase URL")
    if expected_url in text or expected_local_id in text:
        seen_local.add(path.relative_to(root).as_posix())

required_markers = {
    "dart_defines.json": expected_url,
    "dart_defines.example.json": expected_url,
    "lib/core/cloud/supabase_config.dart": expected_local_id,
    "tool/run_current_web.ps1": "LOCAL Supabase",
    "tool/prepare_local_current_database.ps1": expected_local_id,
}
for relative, marker in required_markers.items():
    source = (root / relative).read_text(encoding="utf-8")
    if marker not in source:
        errors.append(f"Local Supabase marker is missing from {relative}: {marker}")

config = (root / "lib/core/cloud/supabase_config.dart").read_text(encoding="utf-8")
for marker in (
    expected_url,
    expected_local_id,
    "validateRuntime",
    "isLocalTarget",
    "_isLoopback(uri.host)",
):
    if marker not in config:
        errors.append(f"SupabaseConfig is missing local-only guard: {marker}")
if "expectedProductionProjectRef" in config:
    errors.append("SupabaseConfig still contains the retired Hosted project guard")
if ".supabase.co" in config:
    errors.append("SupabaseConfig still contains a Hosted Supabase endpoint")

package = json.loads((root / "package.json").read_text(encoding="utf-8"))
scripts = package.get("scripts", {})
if scripts.get("run:web") != scripts.get("run:web:local"):
    errors.append("default web launcher is not the Local Supabase launcher")
if "run_current_web.ps1" not in scripts.get("run:web", ""):
    errors.append("default web launcher does not use run_current_web.ps1")

if errors:
    print("FAIL R75 Local-Supabase-only target verification")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS R75 Local-Supabase-only target verification")
print(f"  - only active project id: {expected_local_id}")
print(f"  - only active API URL: {expected_url}")
print("  - Hosted Supabase targets are rejected from active runtime paths")
print("  - default web launcher remains Local Supabase")
