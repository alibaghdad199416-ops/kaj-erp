#!/usr/bin/env python3
"""R19: authoritative-gates deployment closure.

Eliminates all post-format Dart source identity comparisons. Dart runtime correctness is
certified by the project/DB contracts, R8-R16 functional gates, analyzer, tests and a
fresh release build. Delivery cleanliness remains a pristine-package concern only.
"""
from __future__ import annotations

from verification_text import normalized_text_sha256
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def need(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8", errors="strict")


for relative, digest in {
    "dart_defines.json": "4c7d0bbe2c68df5bd459d1b06081921b80f531c9887fe464dd70532718764c2f",
    ".firebaserc": "f56fa212a1a202d098575515c3bf7e3210d8c7b9d74865c90e6fa6e5c0f2e4a8",
    "firebase.json": "ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a",
}.items():
    need(normalized_text_sha256(ROOT / relative) == digest, f"local runtime/hosting baseline changed: {relative}")

# No release verifier may again use the removed semantic fingerprint helper or a
# post-format lib hash as a runtime gate.
need(not (ROOT / "tool/semantic_dart_fingerprint.py").exists(), "obsolete semantic Dart fingerprint helper is still packaged")
for relative in (
    "tool/verify_r17_deployment_orchestration.py",
    "tool/verify_r18_formatter_invariant_deployment.py",
):
    text = read(relative)
    for forbidden in ("dart_semantic_tree_hash", "expected_lib_semantic", 'tree_hash("lib")'):
        need(forbidden not in text, f"{relative} contains forbidden post-format runtime fingerprint: {forbidden}")

scripts = json.loads(read("package.json"))["scripts"]
need(scripts.get("verify:r19") == "python -B tool/verify_r19_authoritative_gates.py", "verify:r19 command missing")
need(scripts.get("validate:r19:workspace") == "powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r19_workspace.ps1", "R19 workspace validator command missing")
need(scripts.get("validate:r19:windows") == "powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r19_windows.ps1", "R19 Windows validator command missing")
need(scripts.get("deploy:r19:production") == "powershell -NoProfile -ExecutionPolicy Bypass -File tool/deploy_r19_production.ps1", "R19 production deploy command missing")
deploy_command = scripts.get("deploy:production", "")
deploy_match = re.search(r"tool/deploy_r(\d+)_production\.ps1", deploy_command)
deploy_release = int(deploy_match.group(1)) if deploy_match else 0
need(deploy_release >= 19 and (ROOT / f"tool/deploy_r{deploy_release}_production.ps1").is_file(),
     "deploy:production must point at R19 or an existing verified later orchestrator")
workspace_chain=scripts.get("verify:workspace", "")
for required in ("verify:r14", "verify:r15", "verify:r16", "verify:r17", "verify:r18", "verify:r19"):
    need(f"npm run {required}" in workspace_chain, f"workspace verification missing {required}")
need("verify:delivery" not in workspace_chain, "workspace verification must not run pristine delivery checks")

workspace=read("tool/validate_r19_workspace.ps1")
order=("npm run format", "npm run format:check", "npm run verify:workspace", "npm run analyze", "npm run test", "npm run build:web")
for required in order:
    need(required in workspace, f"R19 workspace validator missing: {required}")
positions=[workspace.index(x) for x in order if x in workspace]
need(len(positions)==len(order) and positions==sorted(positions), "R19 authoritative gates are not in the required order")

windows=read("tool/validate_r19_windows.ps1")
need("npm run verify:delivery" in windows, "R19 pristine Windows validation lost delivery check")
need("npm run validate:r19:workspace" in windows, "R19 Windows validation does not run workspace gates")
need(windows.index("npm run verify:delivery") < windows.index("npm run validate:r19:workspace"), "delivery check must precede workspace generation")

production=read("tool/deploy_r19_production.ps1")
need("npm run validate:r19:workspace" in production, "R19 production deployment does not rebuild/revalidate workspace")
need("npm run verify:delivery" not in production, "R19 deployment must not rerun pristine delivery checks in installed workspace")
need("supabase db push --linked --dry-run" in production, "R19 deployment lost Supabase dry-run")
need("Unexpected pending migrations. Refusing production push" in production, "R19 deployment does not reject unexpected migrations")
for migration in (
    "20260808001500_r14_runtime_rpc_invoice_root_closure.sql",
    "20260808014500_r15_canonical_state_reconciliation.sql",
    "20260808024500_r16_persistent_canonical_state.sql",
):
    need(migration in production, f"R19 production deployment does not pin migration: {migration}")
need(production.index("supabase db push --linked --yes") < production.index("firebase-tools deploy --only hosting"), "R19 must deploy database before Firebase Hosting")

if errors:
    print("FAILED R19 authoritative-gates deployment closure")
    for error in errors:
        print("  -", error)
    raise SystemExit(1)

print("PASS R19 authoritative-gates deployment closure")
print("  - post-format Dart hash/token identity gates are removed permanently")
print("  - R14/R15/R16 runtime, invoice and canonical-state contracts remain mandatory")
print("  - format-check, analyzer, tests and fresh web build are the authoritative Dart gates")
print("  - pristine package cleanliness remains separate from installed-workspace validation")
print("  - production deploy validates/builds first, then Supabase dry-run/push, then Firebase Hosting")
print("  - Local Supabase/Firebase baseline hashes are unchanged")
