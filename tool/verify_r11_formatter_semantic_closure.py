#!/usr/bin/env python3
"""R11 compatibility gate: formatter-invariant verification after real Windows runs.

R12 centralizes formatter-invariant Dart matching in verification_text.py. This
legacy gate now validates the semantic contract rather than requiring a specific
historical helper implementation.
"""
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


expected_hashes = {
    "dart_defines.json": "1b0cbea9cf00177e68700f226832d17a083762a04fd271d9ca8b75d36aafb3c7",
    ".firebaserc": "003c25fc2e4659367989cfd4ca9703505abad207657fe6effc49c9317877098e",
    "firebase.json": "ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a",
}
for relative, expected in expected_hashes.items():
    need(sha(relative) == expected, f"production configuration changed: {relative}")

helper = read("tool/verification_text.py")
need("def compact_code(text: str)" in helper and "def contains_code(text: str, snippet: str)" in helper,
     "central formatter-invariant verification helper is missing")
need('state = "string"' in helper and 'state = "block_comment"' in helper,
     "central verifier helper does not preserve strings/remove comments safely")

v741 = read("tool/verify_v741_complete_requirements.py")
need("from verification_text import contains_code" in v741,
     "V7.4.1 does not use the central formatter-invariant matcher")
need("has_sales_invoice_fallback" in v741 and "has_details_invoice_fallback" in v741,
     "V7.4.1 invoice fallbacks are not verified semantically")
need("def compact(text: str)" not in v741,
     "V7.4.1 regressed to its legacy whitespace-only helper")

r9 = read("tool/verify_r9_complete_closure.py")
need("users_compact" in r9 and "TabBarView(controller:_tabs" in r9,
     "R9 TabController verification is still line-layout sensitive")
need("TabBarView(\\n" not in r9,
     "R9 verifier still embeds a physical Dart newline")

v2293r1 = read("tool/verify_v2293_r1_compile_corrections.py")
need("re.search" in v2293r1 and "WorkflowOperationException\\.fromPostgrest" in v2293r1,
     "V22.9.3 R1 maintenance verifier is not formatter-invariant")
need("WorkflowOperationException.fromPostgrest(\\n" not in v2293r1,
     "V22.9.3 R1 still embeds a physical Dart newline")

v735 = read("tool/verify_v735_workflow_performance_ui.py")
need("maintenance_controller_compact" in v735,
     "V7.3.5 maintenance dependency verification is not formatter-invariant")
need("AppDataChangeBus.instance.publish(\\n" not in v735,
     "V7.3.5 still embeds a formatted Dart publish layout")

v757 = read("tool/verify_v757_multicurrency_payment_hardening.py")
need("re.search" in v757 and r"\.where\(" in v757,
     "V7.5.7 currency-filter guard is not formatter-invariant")
need(".where(\\n" not in v757,
     "V7.5.7 still embeds a physical Dart newline")

# Guard against explicit physical-newline membership assertions in Python gates.
# The merge-marker check intentionally searches for a newline before =======.
for path in sorted((ROOT / "tool").glob("verify_*.py")):
    if path.name == Path(__file__).name:
        continue
    source = path.read_text(encoding="utf-8", errors="strict")
    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError as exc:
        errors.append(f"invalid verifier {path.name}: {exc}")
        continue
    for node in ast.walk(tree):
        if not isinstance(node, ast.Compare):
            continue
        if not any(isinstance(op, (ast.In, ast.NotIn)) for op in node.ops):
            continue
        for value in (node.left, *node.comparators):
            if not isinstance(value, ast.Constant) or not isinstance(value.value, str):
                continue
            literal = value.value
            if "\n" in literal and literal != "\n=======":
                errors.append(
                    f"formatter-sensitive multiline membership literal in {path.name}:{node.lineno}"
                )

package = json.loads(read("package.json"))
scripts = package.get("scripts", {})
need("verify:r11" in scripts, "verify:r11 package command missing")
need("validate:r11:windows" in scripts, "R11 Windows validation command missing")
workspace = scripts.get("verify:workspace", scripts.get("verify:all", ""))
need("npm run verify:r11" in workspace,
     "installed-workspace verification does not include R11 formatter-semantic gate")
need((ROOT / "tool/validate_r11_windows.ps1").is_file(),
     "R11 fail-fast Windows validation script missing")

if errors:
    print("FAIL R11 formatter/semantic closure verification")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS R11 formatter/semantic closure verification")
print("  - formatter-invariant matching is centralized in verification_text.py")
print("  - V7.4.1 invoice fallback checks are semantic and layout-independent")
print("  - R9/V22.9.3/V7.3.5/V7.5.7 legacy gates remain formatter-invariant")
print("  - multiline membership literals are blocked from verifier regressions")
print("  - Supabase/Firebase production configuration hashes are unchanged")
