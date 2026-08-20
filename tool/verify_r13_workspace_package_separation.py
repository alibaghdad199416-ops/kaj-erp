#!/usr/bin/env python3
"""R13: enforce clean-delivery / installed-workspace separation without stale gate aliases."""
from __future__ import annotations

import ast
import json
from pathlib import Path

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

# verify:workspace remains the historical installed-workspace chain. verify:all
# is intentionally the current superset, adding Phase 11 R88-R93 gates. This
# avoids silently certifying only the historical R58 endpoint.
verify_all = str(scripts.get("verify:all", ""))
need(
    "npm run verify:workspace" in verify_all,
    "verify:all must include installed-workspace verification",
)
for latest_gate in (
    "verify:r88",
    "verify:r89",
    "verify:r90",
    "verify:r91",
    "verify:r92",
    "verify:r93",
):
    need(
        f"npm run {latest_gate}" in verify_all,
        f"verify:all omits current closure gate {latest_gate}",
    )

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

# CI must verify the pristine delivery before dependency generation, then check
# formatting without mutating the checked-out commit, then run the complete
# verify:all superset. This is intentionally stricter than historical validators.
workflow = read(".github/workflows/quality-gates.yml")
workflow_order = [
    "run: npm run verify:delivery",
    "run: npm ci",
    "run: flutter pub get",
    "run: npm run format:check",
    "run: npm run verify:all",
    "run: npm run analyze",
    "run: npm run test",
    "run: npm run build:web",
]
workflow_pos = [workflow.find(marker) for marker in workflow_order]
need(
    all(position >= 0 for position in workflow_pos)
    and workflow_pos == sorted(workflow_pos),
    "CI pipeline is not delivery-first, non-mutating, and complete",
)
workflow_lines = {line.strip() for line in workflow.splitlines()}
need(
    "run: npm run format" not in workflow_lines,
    "CI must not auto-format and hide committed formatting defects",
)

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
print("  - package cleanliness remains enforced by verify:package only")
print("  - analyzer/test/web build remain fail-fast")
print("  - Local Supabase/Firebase baseline hashes are unchanged")
