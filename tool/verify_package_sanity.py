#!/usr/bin/env python3
"""Validate a clean, browser-only Quality Line ERP source package."""
from __future__ import annotations

import json
import re
from pathlib import Path

from verification_gate_contract import (
    CANONICAL_CHECK_COMMAND,
    CURRENT_PHASE_VERIFY_SCRIPTS,
    verify_all_errors,
    workflow_errors,
)

ROOT = Path(__file__).resolve().parents[1]
EXPECTED_VERSION = "22.9.8+229008"
GENERATED_FILES = {
    ".flutter-plugins",
    ".flutter-plugins-dependencies",
    ".packages",
    "firebase-debug.log",
    "supabase-push-debug.txt",
    "supabase-debug.log",
    "lcov.info",
}

GENERATED_DIRS = {
    ".dart_tool",
    ".firebase",
    ".git",
    "__pycache__",
    "backups",
    "build",
    "coverage",
    "node_modules",
    "production",
    "release_logs",
}

# These source-inspection Flutter tests pre-date the clean-package rule. Keep the
# baseline explicit and frozen so R70+ cannot add more implementation-reading
# tests while the historical cases are migrated to tool/verify_*.py over time.
LEGACY_SOURCE_INSPECTION_TESTS = {
    "test/core/exporting/enterprise_document_presentation_contract_test.dart",
    "test/features/dashboard/dashboard_authoritative_snapshot_test.dart",
    "test/features/maintenance/maintenance_order_snapshot_test.dart",
    "test/features/maintenance/maintenance_partial_issue_ui_contract_test.dart",
    "test/features/maintenance/maintenance_pdf_privacy_contract_test.dart",
    "test/features/maintenance/maintenance_warehouse_issue_pdf_rows_test.dart",
    "test/partial_commercial_fulfillment_contract_test.dart",
    "test/r61_commercial_lifecycle_contract_test.dart",
    "test/r66_authenticated_runtime_defect_contract_test.dart",
    "test/r67_cancelled_order_purge_contract_test.dart",
    "test/r68_governed_bulk_financial_family_contract_test.dart",
    "test/r69_financial_family_runtime_convergence_contract_test.dart",
}

errors: list[str] = []

gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
for name in GENERATED_DIRS:
    marker = f"{name}/"
    if marker not in gitignore and name not in {".git", "production", "release_logs"}:
        errors.append(f".gitignore must exclude generated directory: {name}")

for local_config in (".env",):
    path = ROOT / local_config
    if path.exists():
        errors.append(f"local runtime configuration must not be packaged: {local_config}")

for generated_file in GENERATED_FILES:
    path = ROOT / generated_file
    if path.exists():
        errors.append(f"generated or local file must not be packaged: {generated_file}")

for generated in GENERATED_DIRS:
    if generated == ".git":
        continue
    path = ROOT / generated
    if path.exists():
        errors.append(f"generated or local directory must not be packaged: {generated}")

for path in sorted(ROOT.rglob("*.json")):
    if any(part in GENERATED_DIRS for part in path.relative_to(ROOT).parts):
        continue
    try:
        json.loads(path.read_text(encoding="utf-8"))
    except Exception as error:  # noqa: BLE001 - report the concrete file.
        errors.append(f"invalid JSON {path.relative_to(ROOT)}: {error}")

pubspec_text = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
version_match = re.search(r"(?m)^version:\s*([^\s#]+)", pubspec_text)
version = version_match.group(1).strip("\"'") if version_match else ""
if version != EXPECTED_VERSION:
    errors.append(f"unexpected pubspec version: {version!r}")

firebase = json.loads((ROOT / "firebase.json").read_text(encoding="utf-8"))
if set(firebase) != {"hosting"}:
    errors.append("firebase.json must contain Firebase Hosting only")
elif firebase["hosting"].get("public") != "build/web":
    errors.append("Firebase Hosting must publish build/web")

runtime_text = "\n".join(
    path.read_text(encoding="utf-8", errors="ignore")
    for base in (ROOT / "lib", ROOT / "web")
    for path in base.rglob("*")
    if path.is_file()
)

dependency_block = re.search(
    r"(?ms)^dependencies:\n(?P<body>.*?)(?=^dev_dependencies:)",
    pubspec_text,
)
if dependency_block:
    direct_packages = set(
        re.findall(
            r"(?m)^  ([a-zA-Z0-9_]+):\s*(?:\^|>=|[0-9])",
            dependency_block.group("body"),
        )
    )
    imported_packages = set(re.findall(r"package:([a-zA-Z0-9_]+)/", runtime_text))
    asset_only_packages = {"cupertino_icons"}
    unused_direct_packages = sorted(
        direct_packages - imported_packages - asset_only_packages
    )
    if unused_direct_packages:
        errors.append(
            "unused direct runtime dependencies: " + ", ".join(unused_direct_packages)
        )

for forbidden in ("FirebaseAuth", "cloud_firestore", "firebase_database"):
    if forbidden.lower() in runtime_text.lower():
        errors.append(f"forbidden Firebase runtime service: {forbidden}")

required = (
    ".env.example",
    ".firebaserc",
    ".github/workflows/quality-gates.yml",
    "README.md",
    "README_AR.md",
    "START_HERE_AR.md",
    "analysis_options.yaml",
    "dart_defines.example.json",
    "dart_defines.json",
    "firebase.json",
    "package.json",
    "pubspec.yaml",
    "lib/main.dart",
    "supabase/migrations",
    "web/index.html",
)
for relative in required:
    if not (ROOT / relative).exists():
        errors.append(f"missing required path: {relative}")

legacy_root_patterns = (
    "APPLY_*.ps1",
    "FIX_*.ps1",
    "REPAIR_*.ps1",
    "DEPLOY_*.ps1",
    "PREVIEW_*.ps1",
    "RUN_*.ps1",
    "VERIFY_*.ps1",
    "*.cmd",
)
for pattern in legacy_root_patterns:
    for path in ROOT.glob(pattern):
        errors.append(f"legacy root command must be removed: {path.name}")

for path in sorted((ROOT / "tool").glob("*.py")):
    try:
        compile(path.read_text(encoding="utf-8"), str(path), "exec")
    except SyntaxError as error:
        errors.append(f"invalid Python verifier {path.name}: {error}")

flutter_tests = sorted((ROOT / "test").rglob("*_test.dart"))
if len(flutter_tests) < 25:
    errors.append(f"too few executable Flutter test files: {len(flutter_tests)}")
for path in flutter_tests:
    text = path.read_text(encoding="utf-8", errors="ignore")
    relative = path.relative_to(ROOT).as_posix()
    if (
        ("readAsStringSync" in text or "import 'dart:io'" in text)
        and ("lib/" in text or "supabase/" in text or "web/" in text)
        and relative not in LEGACY_SOURCE_INSPECTION_TESTS
    ):
        errors.append(
            "implementation-source inspection must live in tool/verify_*.py, "
            "not Flutter tests: " + relative
        )

scripts = json.loads((ROOT / "package.json").read_text(encoding="utf-8"))["scripts"]
expected_scripts = {
    "format",
    "format:check",
    "analyze",
    "test",
    "verify",
    "verify:package",
    "check",
    "check:delivery",
    "run:web",
    "build:web",
    "check:release",
    "db:push",
    "hosting:deploy",
    "validate:r10:windows",
    "validate:r12:windows",
    "validate:r13:windows",
    "verify:delivery",
    "verify:preinstall",
    "verify:workspace",
    "verify:all",
    "verify:r13",
    *CURRENT_PHASE_VERIFY_SCRIPTS,
}
missing_scripts = expected_scripts.difference(scripts)
if missing_scripts:
    errors.append("missing package commands: " + ", ".join(sorted(missing_scripts)))

build_web = scripts.get("build:web", "")
build_web_semantic = build_web.replace("python -B tool/", "python tool/")
required_build_steps = (
    "python tool/prepare_web_release.py",
    "flutter build web",
    "python tool/prepare_local_canvaskit.py",
    "python tool/verify_web_release.py",
)
positions = [build_web_semantic.find(step) for step in required_build_steps]
if any(position < 0 for position in positions):
    errors.append(
        "build:web must prepare metadata, build, validate CanvasKit, and verify output"
    )
elif positions != sorted(positions):
    errors.append("build:web release steps are in the wrong order")
if "--no-wasm-dry-run" not in build_web:
    errors.append(
        "browser JavaScript release build must suppress irrelevant Wasm dry-run noise"
    )

if (
    scripts.get("verify:delivery")
    != "npm run verify:package && npm run verify:deployment-target"
):
    errors.append("verify:delivery must validate clean package and deployment target")
if scripts.get("check:delivery") != "npm run verify:delivery":
    errors.append("check:delivery must run the clean pre-install delivery gate")
if scripts.get("check") != CANONICAL_CHECK_COMMAND:
    errors.append(
        "check must run the complete verification chain, formatting, analyzer, and tests"
    )
errors.extend(verify_all_errors(scripts))

if scripts.get("check:release") != "npm run format && npm run check && npm run build:web":
    errors.append(
        "check:release must format, run all source gates, then build the production web release"
    )
if scripts.get("format") != "dart format lib test integration_test":
    errors.append("format command must include explicit Dart source paths")
if (
    scripts.get("validate:r10:windows")
    != "powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r10_windows.ps1"
):
    errors.append(
        "validate:r10:windows must use the fail-fast Windows Flutter validation script"
    )
if (
    scripts.get("validate:r12:windows")
    != "powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r12_windows.ps1"
):
    errors.append(
        "validate:r12:windows must use the R12 fail-fast Windows Flutter validation script"
    )
if scripts.get("verify:preinstall") != "npm run verify:delivery":
    errors.append("verify:preinstall must run the pristine delivery gate")
if (
    "verify:package" in scripts.get("verify:workspace", "")
    or "verify:delivery" in scripts.get("verify:workspace", "")
):
    errors.append("verify:workspace must not invoke clean-package checks")
if (
    scripts.get("validate:r13:windows")
    != "powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r13_windows.ps1"
):
    errors.append("validate:r13:windows must use the R13 fail-fast Windows validator")

workflow_path = ROOT / ".github/workflows/quality-gates.yml"
if workflow_path.is_file():
    workflow = workflow_path.read_text(encoding="utf-8")
    if "run: npm run build:web" not in workflow:
        errors.append("GitHub Actions must use the canonical build:web command")
    if "python tool/prepare_local_canvaskit.py" in workflow:
        errors.append("GitHub Actions must not validate CanvasKit before the web build")
    errors.extend(workflow_errors(workflow))

if errors:
    print("FAILED clean package sanity verification")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS clean package sanity verification")
print(f"  - pubspec version: {EXPECTED_VERSION}")
print("  - generated/local paths are excluded by .gitignore")
print("  - Supabase is the application backend; Firebase is Hosting only")
print("  - local credentials and generated folders are excluded")
print("  - new source-inspection tests are blocked outside tool/verify_*.py")
print("  - authoritative verify:all/check/CI topology comes from one contract")
