#!/usr/bin/env python3
"""Verify V7.3.5 approval repair, performance, one-click login and command UI."""
from pathlib import Path
from verification_text import contains_code
import re

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.exists():
        errors.append(f"missing {relative}")
        return ""
    return path.read_text(encoding="utf-8-sig")


def require(text: str, needles: tuple[str, ...], label: str) -> None:
    missing = [needle for needle in needles if needle not in text]
    if missing:
        errors.append(f"{label}: missing {', '.join(missing)}")


migration = read(
    "supabase/migrations/20260805030000_v735_workflow_approval_performance_login_ui.sql"
)
action = read("lib/core/widgets/app_module_action_icon.dart")
card = read("lib/core/widgets/commercial_workflow_order_card.dart")
window = read("lib/core/widgets/app_full_page_route.dart")
login = read("lib/features/auth/pages/login_page.dart")
prefs = read("lib/core/preferences/app_preferences_controller.dart")
access = read("lib/features/settings/access/controllers/access_controller.dart")
startup = read("lib/core/startup/authenticated_data_loader.dart")
deps = read("lib/app/bootstrap/app_dependencies.dart")
sales = read("lib/features/sales/workflow/pages/sales_workflow_page.dart")
purchases = read("lib/features/purchases/pages/purchase_workflow_page.dart")
maintenance_controller = read(
    "lib/features/maintenance/controllers/maintenance_controller.dart"
)
maintenance_page = read("lib/features/maintenance/pages/maintenance_page.dart")
maintenance_details = read(
    "lib/features/maintenance/pages/maintenance_order_details_dialog.dart"
)
order_details = read("lib/features/sales/workflow/pages/order_details_dialog.dart")
release = read("lib/core/release/app_release_info.dart") + read("pubspec.yaml")
web_version = read("web/version.json")
web_index = read("web/index.html")
prepare_web = read("tool/prepare_web_release.py")

require(
    migration,
    (
        "erp_v735_ensure_operational_accounts",
        "'1390','المخزون التشغيلي العام'",
        "'5190','تكلفة المبيعات التشغيلية'",
        "'5290','مصروفات الصيانة التشغيلية'",
        "currency = 'MULTI'",
        "create or replace function public.erp_phase2_item_accounts",
        "accountBindingsRepairedAt",
        "erp_workflow_partner_account",
        "create or replace function public.erp_phase2_post_purchase_receipt",
        "create or replace function public.erp_phase3_post_maintenance_issue",
    ),
    "workflow accounting fallback migration",
)
require(
    action,
    (
        "const systemAccent = KajDesignTokens.electricBlue",
        "Meaning is carried by the icon and tooltip",
        "width: 38",
        "height: 38",
    ),
    "single-color module command icon",
)
if contains_code(action, "final moduleAccent = color"):
    errors.append("legacy per-action command colors are still active")
require(card, ("AppModuleActionIcon(", "tooltip:", "icon:"), "commercial cards")
require(
    maintenance_page + maintenance_details + order_details,
    ("AppModuleActionIcon(", "Icons.verified_outlined", "Icons.delete_outline_rounded"),
    "workflow action icon integration",
)
if re.search(r"class _StageAction[\s\S]{0,900}FilledButton", maintenance_details):
    errors.append("maintenance stage actions are still wide filled buttons")
if re.search(r"class _InlineComponentButton[\s\S]{0,900}FilledButton", order_details):
    errors.append("commercial component actions are still wide filled buttons")

# R77 superseded the earlier headless-dialog experiment with one consistent,
# bounded premium module window. Legacy Dialog/Scaffold bodies are still
# normalized, but the shared window now owns its header/footer, clipping,
# movable/resizable behavior and unsaved-change close flow.
require(
    window,
    (
        "one consistent premium, movable and resizable window",
        "class _PremiumWindowTheme",
        "class _WindowHeader",
        "class _WindowFooter",
        "class _ScaffoldAsWindow",
        "...?appBar?.actions",
        "scaffold.floatingActionButton",
        "class _AlertDialogAsWindow",
        "SingleChildScrollView(",
        "closeDock",
        "Clip.hardEdge",
    ),
    "premium integrated module window",
)
if "module-window-control-strip" in window:
    errors.append("legacy separate window control strip is still active")

require(
    login,
    (
        "bool _submitting = false",
        "if (_submitting) return",
        "await Future.wait<void>",
        "Post-login warm-up skipped",
        "pushNamedAndRemoveUntil",
    ),
    "one-click login",
)
if re.search(r"await\s+context\s*\.read<AppPreferencesController>\(\)\s*\.synchronizeForCurrentUser", login):
    errors.append("login still blocks navigation on preference synchronization")
require(
    prefs,
    (
        "Future<void>? _activationInFlight",
        "String? _activationTarget",
        "if (active != null && _activationTarget == userId) return active",
        "_activateUserNow",
    ),
    "preference activation coalescing",
)
require(
    access,
    ("unawaited(_startRealtimeAfterLogin())", "Future<void> _startRealtimeAfterLogin"),
    "non-blocking realtime login startup",
)
require(
    startup,
    ("runtime-readiness", "dashboard", "maxConcurrent: 2"),
    "small authenticated warm-up",
)
for forbidden in ("notification-count", "access.loadAccess", "NotificationCenterRepository"):
    if forbidden in startup:
        errors.append(f"authenticated warm-up still includes {forbidden}")

require(
    deps,
    (
        "sources: const {'sales'}",
        "sources: const {'purchases'}",
        "sources: const {'maintenance'}",
        "dashboard.hasLoaded",
        "reports.hasLoaded",
        "Duration(milliseconds: 2000)",
    ),
    "narrow lazy refresh graph",
)
require(
    sales + purchases,
    (
        "Future<void>? _loadInFlight",
        "Duration(milliseconds: 700)",
        "await _load(force: true)",
    ),
    "commercial workflow load coalescing",
)
require(
    sales,
    (
        "'approved'",
        "'posted'",
        "'completed'",
        "canCreateInvoice",
        "order['invoiceId']",
    ),
    "sales invoice prerequisite visibility",
)
require(
    purchases,
    (
        "'approved'",
        "'posted'",
        "'completed'",
        "'confirmed'",
        "canCreateInvoice",
        "order['invoiceId']",
    ),
    "purchase invoice prerequisite visibility",
)
require(
    maintenance_controller,
    (
        "Future<void>? _ordersLoadInFlight",
        "Duration(seconds: 20)",
        "loadOrders({bool force = false})",
    ),
    "maintenance refresh coalescing",
)
maintenance_controller_compact = re.sub(r"\s+", "", maintenance_controller)
for dependency in ("inventory", "accounting"):
    if f"AppDataChangeBus.instance.publish('{dependency}'" not in maintenance_controller_compact:
        errors.append(
            f"maintenance refresh dependency publish missing: {dependency}"
        )
require(
    release,
    ("18.9.8", "189800", "v738-full-verified-runtime-accounting-ui"),
    "release version",
)
require(
    web_version + web_index + prepare_web,
    (
        '"version": "18.9.8"',
        '"buildNumber": 189800',
        'v738-full-verified-runtime-accounting-ui-20260806',
        "FALLBACK_BUILD = '18.9.8+189800-v738-full-verified-runtime-accounting-ui-20260806'",
        'dart_string("releaseToken")',
    ),
    "web release cache identity",
)

if errors:
    print("FAILED V7.3.5 workflow approval, performance, login and UI")
    for error in errors:
        print("  -", error)
    raise SystemExit(1)

print("PASS V7.3.5 workflow approval, performance, login and UI")
print("  - legacy item/account gaps are repaired during stock approvals")
print("  - sales, purchase and maintenance approval chains share robust fallbacks")
print("  - refresh requests are coalesced and aggregate screens remain lazy")
print("  - login routes after the first successful authentication click")
print("  - command actions use one icon-only system accent")
print("  - module work uses one clipped premium movable/resizable window")
