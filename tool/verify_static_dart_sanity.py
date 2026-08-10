from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'lib'
errors: list[str] = []
files = list(LIB.rglob('*.dart'))

for path in files:
    source = path.read_text(encoding='utf-8')
    relative = path.relative_to(ROOT)

    for match in re.finditer(r"(?:import|export)\s+'package:quality_line_erp/([^']+)'", source):
        target = LIB / match.group(1)
        if not target.is_file():
            errors.append(f'{relative}: missing package source {match.group(1)}')

    for match in re.finditer(r'FontWeight\.w(\d{3})', source):
        if match.group(1) not in {'100','200','300','400','500','600','700','800','900'}:
            line = source.count('\n', 0, match.start()) + 1
            errors.append(f'{relative}:{line}: unsupported FontWeight.w{match.group(1)}')

    # Catch merge-conflict remnants that make generated handoffs especially brittle.
    for marker in ('<<<<<<<', '=======', '>>>>>>>'):
        if marker in source:
            errors.append(f'{relative}: unresolved merge marker {marker}')

if errors:
    print('FAILED static Dart source sanity verification')
    for error in errors:
        print('  -', error)
    raise SystemExit(1)

print('PASS static Dart source sanity verification')
print(f'  - checked {len(files)} Dart files')
print('  - all quality_line_erp package imports and exports resolve')
print('  - FontWeight values are supported by Flutter')
print('  - no unresolved merge markers')
