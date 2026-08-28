from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / 'lib'

# Legacy query controllers must not return in feature pages.
legacy = []
for path in (LIB / 'features').rglob('*.dart'):
    text = path.read_text(encoding='utf-8', errors='ignore')
    for pattern in (r'\b_searchController\b', r'\bsearchController\b', r'\b_filterController\b'):
        if re.search(pattern, text):
            legacy.append((path.relative_to(ROOT).as_posix(), pattern))
if legacy:
    raise SystemExit(f'legacy query state detected: {legacy}')

# Asset history had accumulated duplicate state/widget declarations in an earlier
# repair chain. Keep one public widget and one private State implementation.
asset = (LIB / 'features/inventory/asset_history/pages/asset_history_page.dart').read_text(encoding='utf-8')
if len(re.findall(r'\bclass\s+AssetHistoryPage\b', asset)) != 1:
    raise SystemExit('AssetHistoryPage declaration count is not exactly one')
if len(re.findall(r'\bclass\s+_AssetHistoryPageState\b', asset)) != 1:
    raise SystemExit('AssetHistoryPage State declaration count is not exactly one')
if len(re.findall(r'\bState<AssetHistoryPage>\s+createState\s*\(', asset)) != 1:
    raise SystemExit('AssetHistoryPage createState declaration count is not exactly one')
if asset.count('final UnifiedQueryController _queryController') != 1:
    raise SystemExit('Asset history must have exactly one unified query controller')

# The report customizer must retain business-facing fields and suppress only
# technical identifiers/raw payload columns.
customizer = (LIB / 'features/settings/reports/services/contextual_report_customizer.dart').read_text(encoding='utf-8')
for forbidden in ('productcode', 'internalcode', 'nameen', 'englishname'):
    if forbidden in customizer.lower():
        raise SystemExit(f'business report field incorrectly suppressed: {forbidden}')
for required in ('sectionQueries', 'sectionFilters', 'sortRules', 'UnifiedFilterEngine.apply'):
    if required not in customizer:
        raise SystemExit(f'report unified pipeline marker missing: {required}')

print('PHASE4 R99 LARGE REPAIR STATIC AUDIT: PASS')
