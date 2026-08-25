from pathlib import Path
import json, sys

root = Path(__file__).resolve().parents[1]
checks = []

def require(path, needles):
    text = (root / path).read_text(encoding='utf-8')
    for needle in needles:
        if needle not in text:
            raise AssertionError(f'{path}: missing {needle!r}')
    checks.append(path)

require('pubspec.yaml', ['version: 22.7.0+227000'])
require('package.json', ['"version": "22.7.0"', 'verify:v2270'])
require('lib/core/release/app_release_info.dart', ["version = '22.7.0'", 'buildNumber = 227000', 'stage08'])
require('lib/design_system/kaj_admin_stage8_components.dart', [
    'class KajAdminWorkspace', 'class KajAdminSection', 'class KajAdminState', 'class KajAdminMetricData'
])
for page in [
    'lib/features/settings/pages/settings_hub_page.dart',
    'lib/features/settings/pages/settings_page.dart',
    'lib/features/settings/access/pages/users_page.dart',
    'lib/features/settings/system_monitor/pages/system_monitor_page.dart',
    'lib/features/settings/recycle_bin/pages/recycle_bin_page.dart',
    'lib/features/settings/operational_periods/pages/operational_periods_page.dart',
]:
    require(page, ['kaj_admin_stage8_components.dart'])

version = json.loads((root / 'web/version.json').read_text(encoding='utf-8'))
assert version['version'] == '22.7.0'
assert str(version['build']) == '227000'
assert version['releaseStage'] == 'REDESIGN-08'
checks.append('web/version.json')

print('PASS V22.7 full redesign stage 08 administration verification')
print(f'  - {len(checks)} administration, access, monitoring, recovery and release contracts verified')
