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
    assert (ROOT / rel).is_dir(), f'missing ERP feature area: {rel}'

# Every feature area must expose a presentation layer and a data-access layer.
for rel in required_dirs:
    files = [p for p in (ROOT / rel).rglob('*.dart')]
    assert files, f'no Dart implementation files: {rel}'
    text = '\n'.join(p.read_text(encoding='utf-8', errors='ignore') for p in files)
    assert re.search(r'class .*Repository', text), f'repository layer missing: {rel}'

# Prevent obvious placeholder/stub business operations from being certified as complete.
for p in (ROOT / 'lib').rglob('*.dart'):
    text = p.read_text(encoding='utf-8', errors='ignore')
    bad = re.findall(r'\b(TODO|FIXME|NotImplementedException)\b|throw\s+UnimplementedError\s*\(', text)
    assert not bad, f'functional placeholder in {p.relative_to(ROOT)}: {bad[:3]}'

print('PASS R56 functional ERP audit structural gate')
