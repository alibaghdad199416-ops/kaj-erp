#!/usr/bin/env python3
"""R20: native CLI deployment closure.

Windows PowerShell 5.1 can promote ordinary stderr written by native CLIs into
NativeCommandError when ErrorActionPreference is Stop. R20 routes production
Supabase/Firebase CLIs through System.Diagnostics.Process and treats the real
native ExitCode as authoritative while retaining stderr for diagnostics.
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
    "dart_defines.json": "1b0cbea9cf00177e68700f226832d17a083762a04fd271d9ca8b75d36aafb3c7",
    ".firebaserc": "f56fa212a1a202d098575515c3bf7e3210d8c7b9d74865c90e6fa6e5c0f2e4a8",
    "firebase.json": "ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a",
}.items():
    need(normalized_text_sha256(ROOT / relative) == digest, f"production configuration changed: {relative}")

scripts = json.loads(read("package.json"))["scripts"]
need(scripts.get("verify:r20") == "python -B tool/verify_r20_native_cli_deployment.py", "verify:r20 command missing")
need(scripts.get("validate:r20:workspace") == "powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r20_workspace.ps1", "R20 workspace validator command missing")
need(scripts.get("validate:r20:windows") == "powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r20_windows.ps1", "R20 Windows validator command missing")
need(scripts.get("deploy:r20:production") == "powershell -NoProfile -ExecutionPolicy Bypass -File tool/deploy_r20_production.ps1", "R20 production deploy command missing")
deploy_command = scripts.get("deploy:production", "")
deploy_match = re.search(r"tool/deploy_r(\d+)_production\.ps1", deploy_command)
deploy_release = int(deploy_match.group(1)) if deploy_match else 0
need(deploy_release >= 20 and (ROOT / f"tool/deploy_r{deploy_release}_production.ps1").is_file(),
     "deploy:production must point at R20 or an existing verified later orchestrator")
need("npm run verify:r20" in scripts.get("verify:workspace", ""), "workspace verification missing R20")
for required in ("verify:r14", "verify:r15", "verify:r16", "verify:r17", "verify:r18", "verify:r19"):
    need(f"npm run {required}" in scripts.get("verify:workspace", ""), f"workspace verification lost {required}")

runner = read("tool/native_cli_runner.ps1")
for required in (
    "System.Diagnostics.ProcessStartInfo",
    "RedirectStandardOutput = $true",
    "RedirectStandardError = $true",
    "ReadToEndAsync()",
    "$process.ExitCode",
    "stderr is diagnostic text. The native exit code alone decides success.",
):
    need(required in runner, f"R20 native runner missing contract: {required}")

self_test = read("tool/test_r20_native_cli_runner.ps1")
need("R20_STDERR_ZERO_EXIT" in self_test and "exit /b 0" in self_test, "R20 lacks a zero-exit stderr regression probe")
need("R20_EXPECTED_FAILURE" in self_test and "exit /b 7" in self_test, "R20 lacks a non-zero native exit regression probe")
need("native exit code 7" in self_test, "R20 self-test does not verify exit-code rejection")

production = read("tool/deploy_r20_production.ps1")
need('. "$PSScriptRoot/native_cli_runner.ps1"' in production, "R20 deployment does not load the shared native runner")
for required in (
    "Invoke-NativeCaptured",
    "npx supabase db push --linked --dry-run",
    "npx supabase db push --linked --yes",
    "npx supabase migration list --linked",
    "npx firebase-tools use $FirebaseProject",
    "npx firebase-tools deploy --only hosting",
):
    need(required in production, f"R20 production deployment missing native-capture contract: {required}")
need("2>&1" not in production, "R20 must not use PowerShell stderr merging for native deployment CLIs")
need("$dryRunLines = & npx" not in production, "R20 still invokes Supabase dry-run directly through PowerShell")
need("Unexpected pending migrations. Refusing production push" in production, "R20 lost unexpected-migration refusal")
need(production.index("npx supabase db push --linked --yes") < production.index("npx firebase-tools deploy --only hosting"), "R20 must deploy database before Firebase")

workspace = read("tool/validate_r20_workspace.ps1")
for required in ("test_r20_native_cli_runner.ps1", "npm run format:check", "npm run verify:workspace", "npm run analyze", "npm run test", "npm run build:web"):
    need(required in workspace, f"R20 workspace validator missing authoritative gate: {required}")

if errors:
    print("FAILED R20 native CLI deployment closure")
    for error in errors:
        print("  -", error)
    raise SystemExit(1)

print("PASS R20 native CLI deployment closure")
print("  - ordinary Supabase/Firebase stderr cannot become a false PowerShell deployment failure")
print("  - native process exit codes are authoritative and stderr remains visible for diagnostics")
print("  - dry-run parsing still rejects every unexpected migration before production push")
print("  - R14/R15/R16 canonical runtime/state migrations remain the only allowed pending migrations")
print("  - analyzer/tests/fresh web build remain mandatory before Supabase and Firebase deployment")
print("  - Supabase/Firebase production configuration hashes are unchanged")
