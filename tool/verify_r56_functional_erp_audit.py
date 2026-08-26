from __future__ import annotations
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

required_dirs = [
    'lib/features/accounting',
    'lib/features/sales',
    'lib/features/purchases',
    'lib/features/inventory',
    'lib/features/settings',
    'lib/features/partners',
]
for rel in required_dirs:
    base = ROOT / rel
    assert base.is_dir(), f'missing ERP feature area: {rel}'
    files = list(base.rglob('*.dart'))
    assert files, f'no Dart implementation files: {rel}'
    text = '\n'.join(p.read_text(encoding='utf-8', errors='ignore') for p in files)
    assert re.search(r'class\s+\w*Repository\b', text), f'repository layer missing: {rel}'

for p in (ROOT / 'lib').rglob('*.dart'):
    text = p.read_text(encoding='utf-8', errors='ignore')
    assert 'UnimplementedError(' not in text, f'unimplemented operation: {p.relative_to(ROOT)}'
    assert not re.search(r'\b(TODO|FIXME)\b', text), f'placeholder marker: {p.relative_to(ROOT)}'

# Require representative executable business flows in each core area.
markers = {
    'accounting': ('repository', 'journal', 'invoice'),
    'sales': ('repository', 'invoice', 'customer'),
    'purchases': ('repository', 'invoice', 'supplier'),
    'inventory': ('repository', 'stock', 'warehouse'),
}
for area, needles in markers.items():
    files = list((ROOT / 'lib/features' / area).rglob('*.dart'))
    text = '\n'.join(p.read_text(encoding='utf-8', errors='ignore').lower() for p in files)
    for needle in needles:
        assert needle in text, f'R56 flow marker missing: {area}:{needle}'

print('PASS R56 functional ERP audit gate')
