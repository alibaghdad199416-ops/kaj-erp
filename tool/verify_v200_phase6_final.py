from pathlib import Path

root = Path(__file__).resolve().parents[1]
checks = {
    'pubspec.yaml': ['version: 20.0.0+200000'],
    'lib/design_system/kaj_phase6_components.dart': [
        'class KajExecutiveHero',
        'class KajExecutiveMetricData',
        'class KajExecutiveMetric',
        'KajBrandMotif',
    ],
    'lib/features/accounting/pages/accounting_center_page.dart': [
        'KajExecutiveHero(',
        "'المركز المالي والمحاسبي'",
    ],
    'lib/features/settings/pages/settings_hub_page.dart': [
        'KajExecutiveHero(',
        "'Settings & Control Center'",
    ],
}
for rel, needles in checks.items():
    text = (root / rel).read_text(encoding='utf-8')
    for needle in needles:
        if needle not in text:
            raise SystemExit(f'FAIL {rel}: missing {needle}')
print('PASS V20.0 Phase 6 final accounting and administration luxury verification')
