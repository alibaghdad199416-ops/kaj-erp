#!/usr/bin/env python3
from pathlib import Path
import re
ROOT = Path(__file__).resolve().parents[1]
errors=[]
release=(ROOT/'lib/core/release/app_release_info.dart').read_text(encoding='utf-8')
pub=(ROOT/'pubspec.yaml').read_text(encoding='utf-8')
if "static const String version = '20.0.3';" not in release: errors.append('AppReleaseInfo.version')
if 'static const int buildNumber = 200003;' not in release: errors.append('AppReleaseInfo.buildNumber')
if not re.search(r'(?m)^version: 20\.0\.3\+200003$', pub): errors.append('pubspec version')
for path in ROOT.joinpath('lib').rglob('*.dart'):
    text=path.read_text(encoding='utf-8',errors='ignore')
    if "core/localization/app_localizations.dart" in text and 'AppText' not in text and 'AppTranslation' not in text and 'AppLocalizations' not in text:
        errors.append(f'unused localization import candidate: {path.relative_to(ROOT)}')
if errors:
    print('FAILED V20.0.3 stabilization verification')
    for e in errors: print('  -',e)
    raise SystemExit(1)
print('PASS V20.0.3 stabilization verification')
print('  - release metadata matches pubspec')
print('  - known analyzer blockers removed')
