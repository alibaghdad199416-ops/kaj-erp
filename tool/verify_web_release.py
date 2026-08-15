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
        token_match = re.search(
            r"static const String releaseToken\s*=\s*(?:\n\s*)?'([^']+)'",
            release_info,
        )
        runtime_token_match = re.search(
            r"static const String currentRuntimeToken\s*=\s*(?:\n\s*)?'([^']+)'",
            release_info,
        )
        runtime_revision_match = re.search(
            r"static const String currentRuntimeRevision\s*=\s*(?:\n\s*)?'([^']+)'",
            release_info,
        )
        if not token_match:
            errors.append("AppReleaseInfo.releaseToken is missing")
        elif meta.get("releaseToken") != token_match.group(1):
            errors.append("version.json releaseToken differs from AppReleaseInfo")
        if not runtime_token_match:
            errors.append("AppReleaseInfo.currentRuntimeToken is missing")
        elif meta.get("runtimeToken") != runtime_token_match.group(1):
            errors.append("version.json runtimeToken differs from AppReleaseInfo")
        if not runtime_revision_match:
            errors.append("AppReleaseInfo.currentRuntimeRevision is missing")
        elif meta.get("runtimeRevision") != runtime_revision_match.group(1):
            errors.append("version.json runtimeRevision differs from AppReleaseInfo")
        if meta.get("databaseContract") != "R74":
            errors.append("version.json databaseContract is not R74")
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
    if "22.9.8+229008-r74-authenticated-tenant-runtime-20260815" not in index:
        errors.append("web boot fallback is not the current R74 runtime identity")
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
print(" - current R74 runtime identity is synchronized and cache-busting")
print(" - database contract is R74")
