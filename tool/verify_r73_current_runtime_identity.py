from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[1]
release = (root / "lib/core/release/app_release_info.dart").read_text(encoding="utf-8")
index = (root / "web/index.html").read_text(encoding="utf-8")
version = json.loads((root / "web/version.json").read_text(encoding="utf-8"))

expected_token = "r74-authenticated-tenant-runtime-20260815"
legacy_r73_token = "r73-current-schema-runtime-20260815"
expected_revision = "r74-authenticated-tenant-runtime"
expected_build = f"22.9.8+229008-{expected_token}"
legacy_build = "22.9.8+229008-r49-focused-final-completion-20260810"

assert re.search(rf"currentRuntimeRevision\s*=\s*'{re.escape(expected_revision)}'", release)
assert expected_token in release
assert "runtimeSignature => '$displayVersion/$currentRuntimeToken'" in release
assert version.get("runtimeRevision") == expected_revision
assert version.get("runtimeToken") == expected_token
assert version.get("databaseContract") == "R74"
assert legacy_r73_token in version.get("legacyReleaseTokens", [])
assert legacy_r73_token in index
assert expected_build in index
assert "data.runtimeToken || data.releaseToken" in index

fallback = re.search(r"const FALLBACK_BUILD = '([^']+)'", index)
assert fallback, "FALLBACK_BUILD is missing"
assert fallback.group(1) == expected_build, fallback.group(1)
assert fallback.group(1) != legacy_build

# R49 remains only as historical compatibility metadata. The browser runtime
# identity may advance beyond R73 while historical R49/R73 verification remains valid.
assert version.get("releaseToken") == "r49-focused-final-completion-20260810"
assert legacy_build in index

print("PASS R73 current runtime identity")
print(f"  - runtime token: {expected_token}")
print("  - database contract: R74")
print("  - browser cache key prefers runtimeToken over historical releaseToken")
print("  - R73 and R49 tokens are audit-only; R74 owns the active browser identity")
