#!/usr/bin/env python3
"""R17: deployment orchestration must separate pristine delivery from installed workspace validation.

R19 note: R17 deliberately does NOT fingerprint Dart runtime source. Dart format can
perform semantics-preserving token rewrites (for example trailing-comma changes), so
runtime correctness is certified by the R8-R16 contract gates plus analyzer/tests/build.
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


expected_config = {
    "dart_defines.json": "4c7d0bbe2c68df5bd459d1b06081921b80f531c9887fe464dd70532718764c2f",
    ".firebaserc": "f56fa212a1a202d098575515c3bf7e3210d8c7b9d74865c90e6fa6e5c0f2e4a8",
    "firebase.json": "ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a",
}
for relative, digest in expected_config.items():
    actual = normalized_text_sha256(ROOT / relative)
    need(actual == digest, f"local runtime/hosting baseline changed: {relative}")

scripts = json.loads(read("package.json"))["scripts"]
need(scripts.get("verify:r17") == "python -B tool/verify_r17_deployment_orchestration.py", "verify:r17 command missing")
need(scripts.get("validate:r17:workspace") == "powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r17_workspace.ps1", "R17 workspace validator command missing")
need(scripts.get("validate:r17:windows") == "powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r17_windows.ps1", "R17 Windows validator command missing")
need(scripts.get("deploy:r17:production") == "powershell -NoProfile -ExecutionPolicy Bypass -File tool/deploy_r17_production.ps1", "R17 production deploy command missing")
deploy_production = scripts.get("deploy:production", "")
deploy_match = re.search(r"tool/deploy_r(\d+)_production\.ps1", deploy_production)
current_deploy_release = int(deploy_match.group(1)) if deploy_match else 0
current_deploy_script = ROOT / f"tool/deploy_r{current_deploy_release}_production.ps1"
need(current_deploy_release >= 17 and current_deploy_script.is_file(),
     "deploy:production must point at R17 or an existing verified later orchestrator")
need("npm run verify:r16" in scripts.get("verify:workspace", ""), "workspace gate must retain R16 canonical-state verification")
need("npm run verify:r17" in scripts.get("verify:workspace", ""), "workspace gate does not include R17")
need("verify:delivery" not in scripts.get("verify:workspace", ""), "workspace gate must never run pristine package verification")

# Runtime/source identity is intentionally not checked in R17. R19 owns the regression guard.

workspace_validator = read("tool/validate_r17_workspace.ps1")
for forbidden in ("verify:delivery", "verify:package", "validate:r17:windows"):
    need(forbidden not in workspace_validator, f"installed-workspace validator incorrectly invokes {forbidden}")
for required in (
    "npm ci",
    "flutter pub get",
    "npm run format",
    "npm run format:check",
    "npm run verify:workspace",
    "npm run analyze",
    "npm run test",
    "npm run build:web",
):
    need(required in workspace_validator, f"workspace validator missing mandatory stage: {required}")

windows_validator = read("tool/validate_r17_windows.ps1")
need("$present.Count -eq 0" in windows_validator, "Windows validator does not distinguish pristine package from installed workspace")
need("npm run verify:delivery" in windows_validator, "Windows validator lost pristine delivery verification")
need("npm run validate:r17:workspace" in windows_validator, "Windows validator does not delegate to installed-workspace validation")
need(windows_validator.index("npm run verify:delivery") < windows_validator.index("npm run validate:r17:workspace"), "pristine delivery gate must precede workspace generation when applicable")

production = read("tool/deploy_r17_production.ps1")
need("npm run validate:r17:workspace" in production, "production deploy must validate/rebuild installed workspace")
need("npm run validate:r17:windows" not in production, "production deploy must not rerun pristine Windows validation inside an installed workspace")
need("npm run verify:delivery" not in production, "production deploy must not run pristine delivery gate after build artifacts exist")
need("supabase db push --linked --dry-run" in production, "production deploy lost Supabase dry-run")
need("Unexpected pending migrations. Refusing production push" in production, "production deploy does not reject unexpected migrations")
for migration in (
    "20260808001500_r14_runtime_rpc_invoice_root_closure.sql",
    "20260808014500_r15_canonical_state_reconciliation.sql",
    "20260808024500_r16_persistent_canonical_state.sql",
):
    need(migration in production, f"production deploy does not pin expected migration: {migration}")
need(production.index("supabase db push --linked --yes") < production.index("firebase-tools deploy --only hosting"), "database must deploy before Firebase Hosting")
need(production.index("npm run validate:r17:workspace") < production.index("supabase db push --linked --dry-run"), "fresh source validation/build must precede production database/hosting deployment")

if errors:
    print("FAILED R17 deployment orchestration")
    for error in errors:
        print("  -", error)
    raise SystemExit(1)

print("PASS R17 deployment orchestration")
print("  - runtime identity is certified by contract gates + Dart analyzer/tests/build, not post-format source hashes")
print("  - pristine ZIP cleanliness is checked only before generated workspace artifacts exist")
print("  - installed workspace validation rebuilds and rechecks source without package-cleanliness false failures")
print("  - production deploy never calls pristine validation from an already-built workspace")
print("  - Supabase dry-run/push remains before Firebase Hosting and rejects unexpected migrations")
print("  - Local Supabase/Firebase baseline hashes are unchanged")
