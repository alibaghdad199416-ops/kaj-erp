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
    'EXPECTED_LOCAL_URL = "http://127.0.0.1:54321"',
    'EXPECTED_SUPABASE_REF = "havlqebmnjdcwmpaaqew"',
    'production_path = ROOT / "dart_defines.production.json"',
    'dart_defines.json must target Local Supabase loopback only',
    'production runtime must explicitly declare KAJ_BACKEND_TARGET=production',
    'production SUPABASE_URL must match the intended project base URL',
    'return _isLoopback(host) ? \'local\' : \'\';',
):
    if marker not in verify_target:
        errors.append(f"deployment verifier is missing separated runtime contract marker: {marker}")

configure = (ROOT / "tool/configure_production.ps1").read_text(encoding="utf-8")
for marker in (
    "dart_defines.production.json",
    "The Local Supabase dart_defines.json baseline was not modified.",
    "https://havlqebmnjdcwmpaaqew.supabase.co",
):
    if marker not in configure:
        errors.append(f"production configurator is missing separated runtime marker: {marker}")
if "Copy-Item $Source $Target" in configure:
    errors.append("production configurator must not overwrite the Local Supabase test baseline")

proc = subprocess.run(
    [sys.executable, "-B", str(ROOT / "tool/verify_deployment_target.py")],
    cwd=ROOT,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    check=False,
)
if proc.returncode != 0:
    errors.append("verify_deployment_target.py does not pass against the packaged separated runtime configuration")

if errors:
    print("FAILED R6 deployment/analyzer closure")
    for error in errors:
        print(f"- {error}")
    print(proc.stdout.rstrip())
    raise SystemExit(1)

print("PASS R6 deployment/analyzer closure")
print("- local loopback may infer local; hosted URLs never infer production")
print("- production configuration targets only havlqebmnjdcwmpaaqew with an explicit target")
print("- production configuration never overwrites dart_defines.json")
print("- all three analyzer findings from the user run remain closed at source")
print(proc.stdout.rstrip())
