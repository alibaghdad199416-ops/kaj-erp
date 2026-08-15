from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[1]
release = (root / "lib/core/release/app_release_info.dart").read_text(encoding="utf-8")
index = (root / "web/index.html").read_text(encoding="utf-8")
version = json.loads((root / "web/version.json").read_text(encoding="utf-8"))

expected_token = "r73-current-schema-runtime-20260815"
expected_revision = "r73-current-schema-runtime"
expected_build = f"22.9.8+229008-{expected_token}"
legacy_build = "22.9.8+229008-r49-focused-final-completion-20260810"

assert f"currentRuntimeRevision = '{expected_revision}'" in release
assert expected_token in release
assert "runtimeSignature => '$displayVersion/$currentRuntimeToken'" in release
assert version.get("runtimeRevision") == expected_revision
assert version.get("runtimeToken") == expected_token
assert version.get("databaseContract") == "R72"
assert expected_build in index
assert "data.runtimeToken || data.releaseToken" in index

fallback = re.search(r"const FALLBACK_BUILD = '([^']+)'", index)
assert fallback, "FALLBACK_BUILD is missing"
assert fallback.group(1) == expected_build, fallback.group(1)
assert fallback.group(1) != legacy_build

# R49 remains only as historical compatibility metadata. The browser runtime
# identity must be R73 even while historical R49 verification remains valid.
assert version.get("releaseToken") == "r49-focused-final-completion-20260810"
assert legacy_build in index

print("PASS R73 current runtime identity")
print(f"  - runtime token: {expected_token}")
print("  - database contract: R72")
print("  - browser cache key prefers runtimeToken over historical releaseToken")
print("  - stale R49 token is audit-only and is not FALLBACK_BUILD")
