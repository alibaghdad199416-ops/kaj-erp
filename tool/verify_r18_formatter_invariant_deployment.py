#!/usr/bin/env python3
"""R18: formatter-safe deployment closure.

R19 correction: formatter safety means NOT comparing post-format Dart source against a
pre-format textual/token fingerprint. Functional correctness remains enforced by R8-R16,
flutter analyze, flutter test and a fresh release build.
"""
from __future__ import annotations

import hashlib
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
    "dart_defines.json": "1b0cbea9cf00177e68700f226832d17a083762a04fd271d9ca8b75d36aafb3c7",
    ".firebaserc": "003c25fc2e4659367989cfd4ca9703505abad207657fe6effc49c9317877098e",
    "firebase.json": "ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a",
}.items():
    need(hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() == digest, f"production configuration changed: {relative}")

# R18 validates orchestration only. R19 owns the regression guard that forbids
# reintroducing post-format source identity checks.
need(not (ROOT / "tool/semantic_dart_fingerprint.py").exists(), "obsolete semantic Dart fingerprint helper is still packaged")

scripts = json.loads(read("package.json"))["scripts"]
need(scripts.get("verify:r18") == "python -B tool/verify_r18_formatter_invariant_deployment.py", "verify:r18 command missing")
need("npm run verify:r16" in scripts.get("verify:workspace", ""), "workspace gate lost R16 functional/canonical-state verification")
need("npm run verify:r17" in scripts.get("verify:workspace", ""), "workspace gate lost R17")
need("npm run verify:r18" in scripts.get("verify:workspace", ""), "workspace gate does not include R18")
deploy_command = scripts.get("deploy:production", "")
deploy_match = re.search(r"tool/deploy_r(\d+)_production\.ps1", deploy_command)
deploy_release = int(deploy_match.group(1)) if deploy_match else 0
need(deploy_release >= 18 and (ROOT / f"tool/deploy_r{deploy_release}_production.ps1").is_file(),
     "deploy:production must point at R18 or an existing verified later orchestrator")

workspace = read("tool/validate_r18_workspace.ps1")
for required in (
    "npm run format",
    "npm run format:check",
    "npm run verify:workspace",
    "npm run analyze",
    "npm run test",
    "npm run build:web",
):
    need(required in workspace, f"R18 workspace validation missing authoritative gate: {required}")

production = read("tool/deploy_r18_production.ps1")
need("npm run verify:delivery" not in production, "R18 deploy incorrectly reruns pristine delivery validation")
need("npm run validate:r18:workspace" in production, "R18 deploy does not run installed-workspace validation")
need("supabase db push --linked --dry-run" in production, "R18 deploy lost Supabase dry-run")
need(production.index("supabase db push --linked --yes") < production.index("firebase-tools deploy --only hosting"), "R18 must deploy database before Hosting")

if errors:
    print("FAILED R18 formatter-safe deployment closure")
    for error in errors:
        print("  -", error)
    raise SystemExit(1)

print("PASS R18 formatter-safe deployment closure")
print("  - no post-format Dart source/token fingerprint can create false runtime failures")
print("  - R16 functional/canonical-state gates remain mandatory")
print("  - analyzer/tests/fresh web build remain the authoritative Dart runtime gates")
print("  - production deploy remains workspace-safe and database-before-hosting")
print("  - Supabase/Firebase production configuration hashes are unchanged")
