from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
errors: list[str] = []

pubspec = (root / 'pubspec.yaml').read_text(encoding='utf-8')
if 'version: 20.0.2+200002' not in pubspec:
    errors.append('pubspec version is not 20.0.1+200001')

all_dart = '\n'.join(
    p.read_text(encoding='utf-8')
    for p in (root / 'lib').rglob('*.dart')
)

checks = {
    'PDF widgets still use invalid pw.AppText': 'pw.AppText(' in all_dart,
    'obsolete KajBrandMotifDensity remains': 'KajBrandMotifDensity' in all_dart,
    'unsupported motif density argument remains': re.search(r'KajBrandMotif\s*\([^)]*\bdensity\s*:', all_dart, re.S) is not None,
}
for message, failed in checks.items():
    if failed:
        errors.append(message)

tokens = (root / 'lib/design_system/kaj_design_tokens.dart').read_text(encoding='utf-8')
for token in ('staticGreen', 'champagneGold'):
    if not re.search(rf'static const Color\s+{token}\s*=', tokens):
        errors.append(f'missing compatibility token: {token}')

if errors:
    print('FAIL V20.0.2 stabilization verification')
    for error in errors:
        print(f'  - {error}')
    raise SystemExit(1)

print('PASS V20.0.2 stabilization verification')
print('  - invalid PDF AppText calls removed')
print('  - Phase 4-6 design-token compatibility restored')
print('  - KAJ motif API usage matches the implemented widget')
