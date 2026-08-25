#!/usr/bin/env python3
"""R13: enforce hard separation between clean delivery and installed workspace gates."""
from __future__ import annotations

import ast
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def need(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8", errors="strict")


def sha(relative: str) -> str:
    return hashlib.sha256((ROOT / relative).read_bytes()).hexdigest()


# Production targets must remain untouched.
expected = {
    "dart_defines.json": "1b0cbea9cf00177e68700f226832d17a083762a04fd271d9ca8b75d36aafb3c7",
    ".firebaserc": "003c25fc2e4659367989cfd4ca9703505abad207657fe6effc49c9317877098e",
    "firebase.json": "ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a",
}
for relative, digest in expected.items():
    need(sha(relative) == digest, f"production configuration changed: {relative}")

scripts = json.loads(read("package.json")).get("scripts", {})
need(scripts.get("verify:preinstall") == "npm run verify:delivery",
     "verify:preinstall must be the clean-delivery gate")
need(scripts.get("verify:delivery") == "npm run verify:package && npm run verify:deployment-target",
     "verify:delivery contract changed")
need(scripts.get("verify:all") == "npm run verify:workspace",
     "verify:all must alias installed-workspace verification")
need(scripts.get("verify:preformat") == "npm run verify:preinstall",
     "verify:preformat compatibility alias is incorrect")
need(scripts.get("verify:postformat") == "npm run verify:workspace",
     "verify:postformat compatibility alias is incorrect")
workspace = scripts.get("verify:workspace", "")
need("verify:package" not in workspace and "verify:delivery" not in workspace,
     "workspace verification must not execute clean-package checks")
need("npm run verify:r13" in workspace,
     "workspace verification does not include R13")
need(scripts.get("validate:r13:windows") ==
     "powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r13_windows.ps1",
     "R13 Windows validator command missing")

validator = read("tool/validate_r13_windows.ps1")
order = [
    "verify:delivery (pristine package, before dependency generation)",
    "npm ci",
    "flutter pub get",
    "dart format",
    "format:check",
    "verify:workspace (generated dirs allowed)",
    "flutter analyze",
    "flutter test",
    "build:web",
]
pos = [validator.find(marker) for marker in order]
need(all(p >= 0 for p in pos) and pos == sorted(pos),
     "R13 validator stages missing or out of order")

# The historical R8 closure used to reject .dart_tool inside an installed
# workspace. It must now certify functionality only; package cleanliness is
# delegated exclusively to verify_package_sanity.py.
r8 = read("tool/verify_r8_release_closure.py")
for forbidden in (
    "generated directory packaged",
    "for rel in ('.dart_tool'",
    'for rel in (".dart_tool"',
):
    need(forbidden not in r8, f"R8 still performs workspace package-cleanliness assertion: {forbidden}")
need("Delivery cleanliness is verified separately by verify:package" in r8,
     "R8 does not document delegated delivery cleanliness")

# Only verify_package_sanity.py may reject generated runtime directories as a
# delivery artifact. Other release closure gates must not perform that check.
for path in sorted((ROOT / "tool").glob("verify_*.py")):
    source = path.read_text(encoding="utf-8", errors="strict")
    try:
        ast.parse(source, filename=str(path))
    except SyntaxError as exc:
        errors.append(f"invalid verifier {path.name}: {exc}")
        continue
    if path.name in {"verify_package_sanity.py", Path(__file__).name}:
        continue
    if "generated directory packaged:" in source:
        errors.append(f"package-cleanliness assertion leaked into workspace gate: {path.name}")

workflow = read(".github/workflows/quality-gates.yml")
workflow_order = ["run: npm run verify:delivery", "run: npm ci", "run: flutter pub get", "run: npm run format", "run: npm run verify:all", "run: npm run format:check", "run: npm run analyze", "run: npm run test", "run: npm run build:web"]
workflow_pos = [workflow.find(marker) for marker in workflow_order]
need(all(p >= 0 for p in workflow_pos) and workflow_pos == sorted(workflow_pos),
     "CI pipeline is not aligned with R13 Windows validation order")

package_gate = read("tool/verify_package_sanity.py")
for marker in ('".dart_tool"', '"node_modules"', '"build"'):
    need(marker in package_gate, f"delivery package gate no longer rejects {marker}")

if errors:
    print("FAIL R13 workspace/package separation")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS R13 workspace/package separation")
print("  - clean delivery is checked before npm/flutter generate workspace artifacts")
print("  - installed workspace verification allows .dart_tool/node_modules/build metadata")
print("  - package cleanliness remains enforced by verify:package only")
print("  - fail-fast analyzer/test/web build remain mandatory")
print("  - Supabase/Firebase production configuration hashes are unchanged")
