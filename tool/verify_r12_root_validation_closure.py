#!/usr/bin/env python3
"""R12 root closure for formatter-safe Windows validation."""
from __future__ import annotations

import ast
from verification_text import normalized_text_sha256
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def need(ok: bool, msg: str) -> None:
    if not ok:
        errors.append(msg)


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="strict")


def sha(rel: str) -> str:
    return normalized_text_sha256(ROOT / rel)

expected = {
    "dart_defines.json": "1b0cbea9cf00177e68700f226832d17a083762a04fd271d9ca8b75d36aafb3c7",
    ".firebaserc": "f56fa212a1a202d098575515c3bf7e3210d8c7b9d74865c90e6fa6e5c0f2e4a8",
    "firebase.json": "ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a",
}
for rel, digest in expected.items():
    need(sha(rel) == digest, f"production configuration changed: {rel}")

helper = read("tool/verification_text.py")
need("def compact_code" in helper and "def contains_code" in helper,
     "formatter-safe helper missing")
need("line_comment" in helper and "block_comment" in helper and 'state = "string"' in helper,
     "formatter-safe helper is not code-aware")

v741 = read("tool/verify_v741_complete_requirements.py")
need("from verification_text import contains_code" in v741,
     "V7.4.1 is not wired to formatter-safe helper")
need("has_sales_invoice_fallback" in v741 and "has_details_invoice_fallback" in v741,
     "V7.4.1 semantic fallback checks missing")

# Every Python verifier must be UTF-8 explicit and syntactically valid.
for path in sorted((ROOT / "tool").glob("verify_*.py")):
    source = path.read_text(encoding="utf-8", errors="strict")
    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError as exc:
        errors.append(f"invalid verifier {path.name}: {exc}")
        continue
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Attribute) and func.attr == "read_text":
            if not any(keyword.arg == "encoding" for keyword in node.keywords):
                errors.append(
                    f"platform-default text decoding remains in {path.name}:{node.lineno}"
                )

package = json.loads(read("package.json"))
scripts = package.get("scripts", {})
need(scripts.get("verify:r12") == "python -B tool/verify_r12_root_validation_closure.py",
     "verify:r12 package script missing or incorrect")
workspace = scripts.get("verify:workspace", scripts.get("verify:all", ""))
need("npm run verify:r12" in workspace,
     "installed-workspace verification does not include R12")
need("verify:package" not in workspace and "verify:deployment-target" not in workspace and "verify:delivery" not in workspace,
     "installed-workspace verification incorrectly mixes clean-package checks")
need(scripts.get("verify:delivery") == "npm run verify:package && npm run verify:deployment-target",
     "verify:delivery clean-package gate is missing")
need(scripts.get("validate:r12:windows") == "powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r12_windows.ps1",
     "R12 Windows validation command missing")
need((ROOT / "tool/validate_r12_windows.ps1").is_file(), "R12 Windows validation script missing")

validation_script = read("tool/validate_r12_windows.ps1")
required_validation_order = [
    "verify:delivery (clean source package)",
    "npm ci",
    "flutter pub get",
    "dart format",
    "verify:all (post-format semantic gates)",
    "format:check",
    "flutter analyze",
    "flutter test",
    "build:web",
]
positions = [validation_script.find(marker) for marker in required_validation_order]
need(all(position >= 0 for position in positions) and positions == sorted(positions),
     "R12 Windows validation stages are missing or out of order")

workflow = read(".github/workflows/quality-gates.yml")
workflow_order = ["run: npm run verify:delivery", "run: npm ci", "run: flutter pub get", "run: npm run verify:all", "run: npm run analyze", "run: npm run test", "run: npm run build:web"]
workflow_positions = [workflow.find(marker) for marker in workflow_order]
need(all(position >= 0 for position in workflow_positions) and workflow_positions == sorted(workflow_positions),
     "CI does not separate pre-install delivery checks from installed-workspace gates")

# All npm Python verification commands must suppress bytecode generation so
# verify:all is idempotent and cannot create the cache that package gates reject.
for name, command in scripts.items():
    if "python " in command and "python -B " not in command:
        errors.append(f"Python script can generate __pycache__: {name}")

# Python orchestration scripts must also propagate -B to child interpreters.
for rel in ("tool/verify_project.py", "tool/verify_r6_deployment_closure.py"):
    child_source = read(rel)
    if "[sys.executable," in child_source and '[sys.executable, "-B",' not in child_source:
        errors.append(f"child Python verifier can generate __pycache__: {rel}")

# Clean source-package contents are enforced by verify:package before dependencies are installed.

if errors:
    print("FAIL R12 root validation closure")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS R12 root validation closure")
print("  - Python verifier decoding is explicit UTF-8")
print("  - V7.4.1 semantic invoice fallback checks are formatter-safe")
print("  - verify:all includes R12 and Windows validation is fail-fast")
print("  - production Supabase/Firebase configuration hashes are unchanged")
print("  - package cleanliness is delegated to the pre-install verify:delivery gate")
