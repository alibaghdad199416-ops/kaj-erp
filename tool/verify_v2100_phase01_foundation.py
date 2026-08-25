from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
checks = {
    "typography": ROOT / "lib/design_system/kaj_typography.dart",
    "motion": ROOT / "lib/design_system/kaj_motion.dart",
    "breakpoints": ROOT / "lib/design_system/kaj_breakpoints.dart",
    "component tokens": ROOT / "lib/design_system/kaj_component_tokens.dart",
    "audit tool": ROOT / "tool/audit_ui_localization.py",
}
missing = [name for name, path in checks.items() if not path.exists()]
if missing:
    raise SystemExit("FAILED V21.0 Phase 0/1 foundation: missing " + ", ".join(missing))

pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
release = (ROOT / "lib/core/release/app_release_info.dart").read_text(encoding="utf-8")
theme = (ROOT / "lib/app/theme.dart").read_text(encoding="utf-8")
package = (ROOT / "package.json").read_text(encoding="utf-8")

assert "version: 21.0.0+210000" in pubspec
assert "version = '21.0.0'" in release
assert "buildNumber = 210000" in release
assert "KajTypography.theme(foreground, muted)" in theme
assert "KajTypography.primaryFamily" in theme
assert '"audit:ui"' in package
assert '"verify:v2100"' in package

print("PASS V21.0 Phase 0/1 design and localization foundation verification")
print("- release metadata synchronized")
print("- centralized typography, motion, breakpoints and component geometry added")
print("- theme consumes the signature typography scale")
print("- repeatable UI/localization audit command added")
