#!/usr/bin/env python3
"""Validate the generated, self-contained Flutter web release."""
from pathlib import Path
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build/web"
errors: list[str] = []

required_files = {
    "index.html": 100,
    "main.dart.js": 10_000,
    "version.json": 10,
    "flutter_bootstrap.js": 100,
    "canvaskit/canvaskit.js": 10_000,
    "canvaskit/canvaskit.wasm": 100_000,
    "_headers": 100,
    ".htaccess": 100,
}
for rel, minimum_size in required_files.items():
    path = BUILD / rel
    if not path.is_file():
        errors.append(f"missing build artifact: {rel}")
    elif path.stat().st_size < minimum_size:
        errors.append(
            f"invalid or incomplete build artifact: {rel} "
            f"({path.stat().st_size} bytes)",
        )

expected_runtime_token = ""
expected_runtime_revision = ""
expected_database_contract = ""
expected_fallback_build = ""
try:
    pub = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version:\s*([^+\s]+)\+(\d+)\s*$", pub, re.M)
    meta = json.loads((BUILD / "version.json").read_text(encoding="utf-8"))
    if not match:
        errors.append("invalid pubspec version")
    else:
        if meta.get("version") != match.group(1):
            errors.append("version.json version differs from pubspec")
        if meta.get("buildNumber") != int(match.group(2)):
            errors.append("version.json buildNumber differs from pubspec")
        release_info = (ROOT / "lib/core/release/app_release_info.dart").read_text(
            encoding="utf-8",
        )

        def release_string(name: str) -> str:
            value_match = re.search(
                rf"static const String {re.escape(name)}\s*=\s*(?:\n\s*)?'([^']+)'",
                release_info,
            )
            return value_match.group(1) if value_match else ""

        release_token = release_string("releaseToken")
        expected_runtime_token = release_string("currentRuntimeToken")
        expected_runtime_revision = release_string("currentRuntimeRevision")
        expected_database_contract = release_string("databaseContract")
        if not release_token:
            errors.append("AppReleaseInfo.releaseToken is missing")
        elif meta.get("releaseToken") != release_token:
            errors.append("version.json releaseToken differs from AppReleaseInfo")
        if not expected_runtime_token:
            errors.append("AppReleaseInfo.currentRuntimeToken is missing")
        elif meta.get("runtimeToken") != expected_runtime_token:
            errors.append("version.json runtimeToken differs from AppReleaseInfo")
        if not expected_runtime_revision:
            errors.append("AppReleaseInfo.currentRuntimeRevision is missing")
        elif meta.get("runtimeRevision") != expected_runtime_revision:
            errors.append("version.json runtimeRevision differs from AppReleaseInfo")
        if not expected_database_contract:
            errors.append("AppReleaseInfo.databaseContract is missing")
        elif meta.get("databaseContract") != expected_database_contract:
            errors.append("version.json databaseContract differs from AppReleaseInfo")
        if expected_runtime_token:
            expected_fallback_build = (
                f"{match.group(1)}+{match.group(2)}-{expected_runtime_token}"
            )
except Exception as exc:  # noqa: BLE001
    errors.append(f"metadata validation failed: {exc}")

try:
    bootstrap = (BUILD / "flutter_bootstrap.js").read_text(encoding="utf-8")
    normalized = re.sub(r"\s+", "", bootstrap)
    if "canvasKitBaseUrl:'canvaskit/'" not in normalized and 'canvasKitBaseUrl:"canvaskit/"' not in normalized:
        errors.append("flutter bootstrap does not use self-hosted CanvasKit")
except OSError as exc:
    errors.append(f"bootstrap validation failed: {exc}")

try:
    index = (BUILD / "index.html").read_text(encoding="utf-8")
    if "data.runtimeToken || data.releaseToken" not in index:
        errors.append("web boot does not prefer the current runtime token")
    if not expected_fallback_build:
        errors.append("current runtime fallback identity could not be derived")
    elif expected_fallback_build not in index:
        errors.append("web boot fallback differs from the canonical runtime identity")
except OSError as exc:
    errors.append(f"index validation failed: {exc}")

try:
    host_metadata = (BUILD / "_headers").read_text(encoding="utf-8") + (BUILD / ".htaccess").read_text(encoding="utf-8")
    if "no-store, no-cache, must-revalidate, max-age=0" not in host_metadata:
        errors.append("host metadata does not disable caching for Flutter runtime entry files")
except OSError as exc:
    errors.append(f"host metadata validation failed: {exc}")

if errors:
    print("FAIL web release verification")
    for error in errors:
        print(f" - {error}")
    sys.exit(1)

print("PASS web release verification")
print(" - CanvasKit is self-hosted under build/web/canvaskit")
print(f" - current runtime identity is synchronized: {expected_runtime_token}")
print(f" - database contract is {expected_database_contract}")
