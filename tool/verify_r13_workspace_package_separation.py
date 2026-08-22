#!/usr/bin/env python3
"""R13: enforce clean-delivery / installed-workspace separation without stale gate aliases."""
from __future__ import annotations

import ast
import json
from pathlib import Path

from verification_gate_contract import verify_all_errors, workflow_errors
from verification_text import normalized_text_sha256

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def need(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8", errors="strict")


def sha(relative: str) -> str:
    return normalized_text_sha256(ROOT / relative)


# Local runtime/hosting targets must remain pinned to the current baseline.
expected = {
    "dart_defines.json": "4c7d0bbe2c68df5bd459d1b06081921b80f531c9887fe464dd70532718764c2f",
    ".firebaserc": "f56fa212a1a202d098575515c3bf7e3210d8c7b9d74865c90e6fa6e5c0f2e4a8",
    "firebase.json": "ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a",
}
for relative, digest in expected.items():
    need(sha(relative) == digest, f"local runtime/hosting baseline changed: {relative}")

scripts = json.loads(read("package.json")).get("scripts", {})
need(
    scripts.get("verify:preinstall") == "npm run verify:delivery",
    "verify:preinstall must be the clean-delivery gate",
)
need(
    scripts.get("verify:delivery")
    == "npm run verify:package && npm run verify:deployment-target",
    "verify:delivery contract changed",
)
errors.extend(verify_all_errors(scripts))

need(
    scripts.get("verify:preformat") == "npm run verify:preinstall",
    "verify:preformat compatibility alias is incorrect",
)
need(
    scripts.get("verify:postformat") == "npm run verify:workspace",
    "verify:postformat compatibility alias is incorrect",
)
workspace = str(scripts.get("verify:workspace", ""))
need(
    "verify:package" not in workspace and "verify:delivery" not in workspace,
    "workspace verification must not execute clean-package checks",
)
need(
    "npm run verify:r13" in workspace,
    "workspace verification does not include R13",
)
need(
    scripts.get("validate:r13:windows")
    == "powershell -NoProfile -ExecutionPolicy Bypass -File tool/validate_r13_windows.ps1",
    "R13 Windows validator command missing",
)

# The historical Windows validator is allowed to format an explicitly clean
# disposable validation worktree. The authoritative CI below is deliberately
# non-mutating and checks committed formatting before verification.
validator = read("tool/validate_r13_windows.ps1")
validator_order = [
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
validator_pos = [validator.find(marker) for marker in validator_order]
need(
    all(position >= 0 for position in validator_pos)
    and validator_pos == sorted(validator_pos),
    "R13 historical Windows validator stages missing or out of order",
)

# The historical R8 closure used to reject .dart_tool inside an installed
# workspace. It must now certify functionality only; package cleanliness is
# delegated exclusively to verify_package_sanity.py.
r8 = read("tool/verify_r8_release_closure.py")
for forbidden in (
    "generated directory packaged",
    "for rel in ('.dart_tool'",
    'for rel in (".dart_tool"',
):
    need(
        forbidden not in r8,
        f"R8 still performs workspace package-cleanliness assertion: {forbidden}",
    )
need(
    "Delivery cleanliness is verified separately by verify:package" in r8,
    "R8 does not document delegated delivery cleanliness",
)

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
        errors.append(
            f"package-cleanliness assertion leaked into workspace gate: {path.name}"
        )

# The authoritative CI topology is centralized. R13 owns the separation policy,
# while verification_gate_contract owns exact current stage ordering.
workflow = read(".github/workflows/quality-gates.yml")
errors.extend(workflow_errors(workflow))

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
print("  - verify:all adds R88-R93 on top of the historical workspace chain")
print("  - CI checks committed formatting without mutating source")
print("  - authoritative gate topology is centralized")
print("  - package cleanliness remains enforced by verify:package only")
print("  - analyzer/test/web build remain fail-fast")
print("  - Local Supabase/Firebase baseline hashes are unchanged")
