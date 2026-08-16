#!/usr/bin/env python3
"""Verify R6 deployment/analyzer closure without requiring Flutter CLI."""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []

web = (ROOT / "lib/core/exporting/excel_download_service_web.dart").read_text(encoding="utf-8")
if "avoid_web_libraries_in_flutter" not in web.splitlines()[0]:
    errors.append("web-only Excel downloader must explicitly suppress the web-library lint in its conditional implementation")

maintenance = (ROOT / "lib/features/maintenance/pages/add_maintenance_order_page.dart").read_text(encoding="utf-8")
needle = "if (selected == null || !context.mounted) return;"
if needle not in maintenance:
    errors.append("maintenance date/time picker must guard BuildContext with context.mounted")

access = (ROOT / "lib/features/settings/access/repositories/access_repository.dart").read_text(encoding="utf-8")
if "import 'dart:convert';" in access:
    errors.append("access repository still has the analyzer-reported unused dart:convert import")

verify_target = (ROOT / "tool/verify_deployment_target.py").read_text(encoding="utf-8")
for marker in (
    'EXPECTED_SUPABASE_URL = "http://127.0.0.1:54321"',
    'EXPECTED_LOCAL_PROJECT_ID = "quality_line_erp_local_dev"',
    'active_runtime_path = ROOT / "dart_defines.json"',
    "Hosted Supabase endpoints are forbidden in the active runtime defines",
):
    if marker not in verify_target:
        errors.append(f"deployment verifier is missing Local Supabase contract marker: {marker}")

configure = (ROOT / "tool/configure_production.ps1").read_text(encoding="utf-8")
if "keeping the existing dart_defines.json unchanged" not in configure:
    errors.append("production configurator does not preserve the active runtime file when the optional template is absent")

proc = subprocess.run(
    [sys.executable, "-B", str(ROOT / "tool/verify_deployment_target.py")],
    cwd=ROOT,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    check=False,
)
if proc.returncode != 0:
    errors.append("verify_deployment_target.py does not pass against the packaged active runtime configuration")

if errors:
    print("FAILED R6 deployment/analyzer closure")
    for error in errors:
        print(f"- {error}")
    print(proc.stdout.rstrip())
    raise SystemExit(1)

print("PASS R6 deployment/analyzer closure")
print("- deployment target verifier enforces the current Local Supabase runtime contract")
print("- legacy production configurator cannot overwrite the active local dart_defines.json when its optional template is absent")
print("- all three analyzer findings from the user run are closed at source")
print(proc.stdout.rstrip())
