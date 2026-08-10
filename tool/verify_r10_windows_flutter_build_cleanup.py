#!/usr/bin/env python3
"""R10 closure for Windows UTF-8 verifiers and Flutter compile blockers."""
from __future__ import annotations

import ast
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


def sha(relative: str) -> str:
    return normalized_text_sha256(ROOT / relative)


# Production connection/hosting text must stay content-identical to the
# user-supplied R9 baseline across Git LF/CRLF worktrees.
expected_hashes = {
    "dart_defines.json": "1b0cbea9cf00177e68700f226832d17a083762a04fd271d9ca8b75d36aafb3c7",
    ".firebaserc": "f56fa212a1a202d098575515c3bf7e3210d8c7b9d74865c90e6fa6e5c0f2e4a8",
    "firebase.json": "ba6d0df13954597d2070d0d3acd628d06836bd36d17e072e04e3a82d4085031a",
}
for relative, expected in expected_hashes.items():
    need(sha(relative) == expected, f"production configuration changed: {relative}")

permission_codes = read("lib/features/settings/access/models/permission_codes.dart")
need("static const settingsView = 'settings.view';" in permission_codes,
     "PermissionCodes.settingsView compile contract is missing")
need("static const recycleBinView = 'settings.recycle_bin.view';" in permission_codes,
     "recycle-bin view permission contract is missing")
need("static const periodsView = 'periods.view';" in permission_codes,
     "operational-period view permission contract is missing")

recycle_bin = read("lib/features/settings/recycle_bin/pages/recycle_bin_page.dart")
operational_periods = read("lib/features/settings/operational_periods/pages/operational_periods_page.dart")
need("PermissionCodes.settingsView" not in recycle_bin and "PermissionCodes.recycleBinView" in recycle_bin,
     "recycle-bin field visibility is not scoped to recycleBinView")
need("PermissionCodes.settingsView" not in operational_periods and "PermissionCodes.periodsView" in operational_periods,
     "operational-period field visibility is not scoped to periodsView")

purchase_card = read("lib/features/purchases/widgets/purchase_card.dart")
sale_card = read("lib/features/sales/widgets/sale_card.dart")
need("final VoidCallback? onEdit;" in purchase_card and "if (onEdit != null)" in purchase_card,
     "PurchaseCard read-only mode is not null-safe")
need("final VoidCallback? onEdit;" in sale_card and "if (onEdit != null)" in sale_card,
     "SaleCard read-only mode is not null-safe")

purchases_page = read("lib/features/purchases/pages/purchases_page.dart")
sales_page = read("lib/features/sales/pages/sales_page.dart")
need("onEdit: null" not in purchases_page,
     "legacy purchase page still passes an explicit null edit callback")
need("onEdit: null" not in sales_page and "onResell: null" not in sales_page,
     "legacy sales page still passes explicit null callbacks")

# Analyzer warnings from the user's real Flutter 3.44.6 run must stay removed.
need("String _exportText(" not in read("lib/core/exporting/excel_export_service.dart"),
     "unused Excel _exportText helper returned")
need("features/settings/access/models/user_model.dart" not in read("lib/core/widgets/app_workspace_top_bar.dart"),
     "unused user_model import returned")
need("features/settings/access/widgets/permission_action.dart" not in read("lib/features/accounting/installments/pages/installments_page.dart"),
     "unused installments PermissionAction import returned")
need("core/widgets/app_module_dialog.dart" not in purchases_page,
     "unused purchases app_module_dialog import returned")
need("core/widgets/app_module_dialog.dart" not in sales_page,
     "unused sales app_module_dialog import returned")

cashbox = read("lib/features/accounting/cashbox/pages/cashbox_page.dart")
need(re.search(
    r"if \(!await PermissionAction\.require\(context, 'accounting\.update'\)\) return;\s*if \(!mounted\) return;\s*final controller = context\.read<CashboxController>\(\);",
    cashbox,
) is not None, "cashbox transfer still uses BuildContext after an async gap without a mounted guard")

package = json.loads(read("package.json"))
build_web = package.get("scripts", {}).get("build:web", "")
need("--pwa-strategy" not in build_web,
     "deprecated Flutter --pwa-strategy flag returned to build:web")
need("--no-wasm-dry-run" in build_web and "--no-web-resources-cdn" in build_web,
     "self-contained web release flags regressed")
need(package.get("scripts", {}).get("check") ==
     "npm run verify:workspace && npm run format:check && npm run analyze && npm run test",
     "canonical check command does not run every installed-workspace source gate")
need(package.get("scripts", {}).get("check:release") ==
     "npm run format && npm run check && npm run build:web",
     "canonical release check must auto-format before verifying/analyzing/testing/building")
need((ROOT / "tool/validate_r10_windows.ps1").is_file(),
     "Windows fail-fast release validation script is missing")

web_index = read("web/index.html")
firebase = read("firebase.json")
need("navigator.serviceWorker.getRegistrations()" in web_index and "registration.unregister()" in web_index,
     "stale service-worker cleanup is missing from web/index.html")
need("no-store, no-cache, must-revalidate, max-age=0" in firebase,
     "Firebase runtime no-cache headers are missing")

# Every Python verifier must parse and every Path.read_text() call must declare an encoding.
for path in sorted((ROOT / "tool").rglob("*.py")):
    source = path.read_text(encoding="utf-8", errors="strict")
    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError as exc:
        errors.append(f"invalid Python verifier {path.name}: {exc}")
        continue
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Attribute) and func.attr == "read_text":
            if not any(keyword.arg == "encoding" for keyword in node.keywords):
                errors.append(
                    f"Windows-locale unsafe read_text() without encoding in {path.relative_to(ROOT)}:{node.lineno}"
                )

# Specifically protect the verifier that failed on the user's Windows cp1252 locale.
# Inspect the AST rather than matching one exact call spelling.
v741 = read("tool/verify_v741_complete_requirements.py")
try:
    v741_tree = ast.parse(v741, filename="verify_v741_complete_requirements.py")
except SyntaxError:
    v741_tree = None
v741_utf8_reads = 0
if v741_tree is not None:
    for node in ast.walk(v741_tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if not (isinstance(func, ast.Attribute) and func.attr == "read_text"):
            continue
        for keyword in node.keywords:
            if keyword.arg != "encoding":
                continue
            if isinstance(keyword.value, ast.Constant) and str(keyword.value.value).lower().replace("_", "-") == "utf-8":
                v741_utf8_reads += 1
need(v741_utf8_reads > 0, "V7.4.1 verifier is not UTF-8 explicit")

if errors:
    print("FAIL R10 Windows/Flutter build cleanup verification")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS R10 Windows/Flutter build cleanup verification")
print("  - production Supabase/Firebase text is unchanged across LF/CRLF worktrees")
print("  - settings permission and legacy read-only cards are compile-safe")
print("  - analyzer warnings reported by the user's Flutter run are removed")
print("  - cashbox async BuildContext usage is mounted-guarded")
print("  - Python verifiers are UTF-8 deterministic on Windows")
print("  - deprecated --pwa-strategy is removed while cache cleanup remains")
