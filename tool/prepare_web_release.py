#!/usr/bin/env python3
"""Synchronize web/version.json with the canonical release constants."""
from pathlib import Path
import json
import re
import sys

root = Path(__file__).resolve().parents[1]
pub = (root / "pubspec.yaml").read_text(encoding="utf-8")
release = (root / "lib/core/release/app_release_info.dart").read_text(
    encoding="utf-8",
)
version_match = re.search(r"^version:\s*([^+\s]+)\+(\d+)\s*$", pub, re.M)
if not version_match:
    sys.exit("Invalid pubspec version")


def dart_string(name: str) -> str:
    match = re.search(
        rf"static const String {re.escape(name)}\s*=\s*(?:\n\s*)?'([^']+)'",
        release,
    )
    if not match:
        sys.exit(f"Missing AppReleaseInfo.{name}")
    return match.group(1)


version = version_match.group(1)
build = int(version_match.group(2))
if dart_string("version") != version:
    sys.exit("AppReleaseInfo.version differs from pubspec")

path = root / "web/version.json"
meta = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
meta.update(
    {
        "version": version,
        "build": build,
        "buildNumber": build,
        "channel": dart_string("channel"),
        "releaseStage": "F",
        "syncEngine": dart_string("syncEngine"),
        "releaseToken": dart_string("releaseToken"),
        "operationalRevision": dart_string("operationalRevision"),
        "runtimeRevision": dart_string("currentRuntimeRevision"),
        "runtimeToken": dart_string("currentRuntimeToken"),
    }
)
path.write_text(
    json.dumps(meta, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
print(
    f"Prepared web release {version}+{build}-"
    f"{dart_string('currentRuntimeToken')}"
)
