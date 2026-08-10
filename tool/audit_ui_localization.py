from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'lib'

RAW_TEXT_CALL = re.compile(r'\bText\(\s*([\'\"])(.*?)\1', re.DOTALL)
APP_TEXT_CALL = re.compile(r'\bAppText\(\s*([\'\"])(.*?)\1', re.DOTALL)
COLOR_LITERAL = re.compile(r'Color\(0x[0-9A-Fa-f]{8}\)')
RADIUS_LITERAL = re.compile(r'BorderRadius\.circular\((\d+(?:\.\d+)?)\)')

ui_excluded_prefixes = (
    'lib/core/printing/', 'lib/core/exporting/',
    'lib/features/settings/reports/services/',
    'lib/core/localization/',
)
visual_excluded_prefixes = (
    'lib/design_system/', 'lib/app/theme.dart', 'lib/app/brand_identity.dart',
    'lib/core/printing/', 'lib/core/exporting/',
)

raw_ui_text = []
runtime_localized_app_text = []
color_literals = []
radius_literals = []
paths = sorted(LIB.rglob('*.dart'))
for path in paths:
    rel = path.relative_to(ROOT).as_posix()
    text = path.read_text(encoding='utf-8')
    if not rel.startswith(ui_excluded_prefixes):
        for pattern, target in ((RAW_TEXT_CALL, raw_ui_text), (APP_TEXT_CALL, runtime_localized_app_text)):
            for match in pattern.finditer(text):
                value = match.group(2).strip()
                if value and not value.startswith(('$', '\\u')):
                    target.append({'file': rel, 'line': text.count('\n', 0, match.start()) + 1, 'value': value[:160]})
    if not rel.startswith(visual_excluded_prefixes):
        for match in COLOR_LITERAL.finditer(text):
            color_literals.append({'file': rel, 'line': text.count('\n', 0, match.start()) + 1, 'value': match.group(0)})
        for match in RADIUS_LITERAL.finditer(text):
            radius_literals.append({'file': rel, 'line': text.count('\n', 0, match.start()) + 1, 'value': match.group(1)})

report = {
    'dartFiles': len(paths),
    'unlocalizedRawUiTextCandidates': len(raw_ui_text),
    'runtimeLocalizedAppTextLiterals': len(runtime_localized_app_text),
    'nonDesignSystemColorLiterals': len(color_literals),
    'nonDesignSystemRadiusLiterals': len(radius_literals),
    'rawUiText': raw_ui_text,
    'runtimeLocalizedAppText': runtime_localized_app_text,
    'colorLiterals': color_literals,
    'radiusLiterals': radius_literals,
}
out = ROOT / 'docs' / 'audit'
out.mkdir(parents=True, exist_ok=True)
(out / 'final_ui_localization_audit.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
(out / 'FINAL_UI_LOCALIZATION_AUDIT.md').write_text(
    '# Final UI and localization audit\n\n'
    f"- Dart files: {report['dartFiles']}\n"
    f"- Raw `Text` UI candidates: {report['unlocalizedRawUiTextCandidates']}\n"
    f"- Runtime-localized `AppText` literals: {report['runtimeLocalizedAppTextLiterals']}\n"
    f"- Color literals outside central visual layers: {report['nonDesignSystemColorLiterals']}\n"
    f"- Radius literals outside central visual layers: {report['nonDesignSystemRadiusLiterals']}\n",
    encoding='utf-8',
)
print('PASS final UI and localization audit generated')
for key in ('dartFiles','unlocalizedRawUiTextCandidates','runtimeLocalizedAppTextLiterals','nonDesignSystemColorLiterals','nonDesignSystemRadiusLiterals'):
    print(f'- {key}: {report[key]}')
