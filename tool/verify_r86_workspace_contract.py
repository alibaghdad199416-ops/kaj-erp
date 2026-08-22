#!/usr/bin/env python3
"""Static regression verifier for the R86 connected workspace contract."""
from pathlib import Path
from verification_text import contains_code

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


def require_code(text: str, needles: tuple[str, ...], label: str) -> None:
    missing = [needle for needle in needles if not contains_code(text, needle)]
    if missing:
        errors.append(f"{label}: missing {', '.join(missing)}")


def forbid(text: str, needles: tuple[str, ...], label: str) -> None:
    present = [needle for needle in needles if needle in text]
    if present:
        errors.append(f"{label}: forbidden {', '.join(present)}")


scope = read("lib/core/widgets/app_workspace_chrome_scope.dart")
shell = read("lib/core/widgets/app_module_shell.dart")
entity = read("lib/core/widgets/app_entity_page.dart")
route = read("lib/core/widgets/app_full_page_route.dart")
workspace_dialog = read("lib/core/widgets/app_workspace_dialog.dart")
floating_window = read("lib/core/widgets/app_floating_window.dart")
relationship = read("lib/design_system/kaj_relationship_stage5_components.dart")
phase3 = read("lib/design_system/kaj_phase3_components.dart")
phase4 = read("lib/design_system/kaj_phase4_components.dart")
phase5 = read("lib/design_system/kaj_phase5_components.dart")
phase6 = read("lib/design_system/kaj_phase6_components.dart")
signature = read("lib/design_system/kaj_signature_components.dart")

require(
    scope,
    (
        "class AppWorkspaceChromeScope extends InheritedWidget",
        "required this.hasWorkspaceTopBar",
        "static bool hasTopBarOf(BuildContext context)",
    ),
    "workspace chrome scope",
)
require(
    shell,
    (
        "AppWorkspaceTopBar(currentRoute: route)",
        "AppWorkspaceChromeScope(",
        "hasWorkspaceTopBar: false",
        "hasWorkspaceTopBar: true",
        "_WorkspaceCanvas(child: moduleContent)",
    ),
    "module shell ownership",
)
require_code(
    entity,
    (
        "AppWorkspaceChromeScope.hasTopBarOf(",
        "shellHasWorkspaceTopBar && !insideModuleWindow",
        "if (!effectiveHideHeader)",
        "module-command-rail",
        "module-continuous-workspace",
    ),
    "entity page duplicate-header suppression",
)

require(
    route,
    (
        "Desktop workspaces intentionally remain bounded",
        "double maxWidth = 1320",
        "double maxHeight = 840",
        "double minWidth = 760",
        "double minHeight = 520",
        "module-workspace-window",
        "class _WorkspaceHeader",
        "class _WorkspacePresentation",
        "_scaffoldAsHeaderlessWorkspace",
        "headerActions: child.actions",
        "headerActions: appBar?.actions",
        "headerActions: child.actions ?? const <Widget>[]",
        "if (child is AlertDialog)",
        "if (child is Dialog && child.child != null)",
    ),
    "bounded operational workspace",
)
forbid(
    route,
    (
        "class _PremiumWindowTheme",
        "class _WindowFooter",
        "class _ScaffoldAsWindow",
        "module-window-control-strip",
    ),
    "legacy nested/full-window chrome",
)
require(
    workspace_dialog,
    (
        "double maxWidth = 1180",
        "double maxHeight = 820",
        "showAppFloatingWindow<T>(",
        "maxWidth: maxWidth",
        "maxHeight: maxHeight",
    ),
    "workspace dialog delegates bounded size",
)
require(
    floating_window,
    (
        "double maxWidth = 1080",
        "double maxHeight = 780",
        "showAppFullPageRoute<T>(",
        "maxWidth: maxWidth",
        "maxHeight: maxHeight",
    ),
    "floating workspace delegates central bounds",
)

for label, text in (
    ("relationship hero", relationship),
    ("phase hero", phase3),
    ("partner hero", phase4),
    ("commercial hero", phase5),
    ("executive hero", phase6),
    ("signature hero", signature),
):
    require_code(
        text,
        ("AppWorkspaceChromeScope.hasTopBarOf(",),
        f"{label} workspace awareness",
    )

require(
    relationship,
    (
        "AppWorkspaceWindowScope.maybeOf(context) != null",
        "final functionalChrome = <Widget>[",
        "scrollDirection: Axis.horizontal",
    ),
    "relationship command rail",
)
require(
    phase3,
    (
        "AppWorkspaceWindowScope.maybeOf(context) != null",
        "final commands = <Widget>[?secondaryAction, ?primaryAction, ?trailing]",
        "final dense = compact || constraints.maxWidth < 900",
        "width: dense ? 126 : 148",
        "scrollDirection: Axis.horizontal",
    ),
    "phase hero and workflow density",
)
forbid(
    phase3,
    (
        "final vertical = compact || constraints.maxWidth < 720",
        "if (vertical) {\n          return Column(",
    ),
    "legacy vertical workflow stacking",
)

for label, text in (
    ("partner hero", phase4),
    ("commercial hero", phase5),
    ("executive hero", phase6),
    ("signature hero", signature),
):
    require(text, ("scrollDirection: Axis.horizontal",), f"{label} horizontal rail")

# Command strips must use intrinsic height. Hard 40/44px wrappers clipped
# two-line metrics and some localized buttons at 100% browser zoom.
for label, text in (
    ("partner hero", phase4),
    ("commercial hero", phase5),
    ("executive hero", phase6),
    ("signature hero", signature),
):
    forbid(
        text,
        (
            "return SizedBox(\n        height: 40,\n        child: SingleChildScrollView(",
            "return SizedBox(\n        height: 44,\n        child: SingleChildScrollView(",
        ),
        f"{label} fixed-height command rail",
    )

if errors:
    print("FAILED R86 connected workspace contract")
    for error in errors:
        print("  -", error)
    raise SystemExit(1)

print("PASS R86 connected workspace contract")
print("  - desktop AppWorkspaceTopBar owns module identity")
print("  - entity pages keep actions, metrics and filters on one canvas")
print("  - operational dialogs stay bounded with one promoted header")
print("  - page heroes collapse into intrinsic horizontal command rails")
print("  - compact workflows remain dense and horizontally scrollable")
