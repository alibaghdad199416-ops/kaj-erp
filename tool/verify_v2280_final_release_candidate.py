from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
checks = []


def need(path, text=None):
    p = ROOT / path
    ok = p.exists() and (text is None or text in p.read_text(encoding='utf-8', errors='ignore'))
    checks.append((ok, f'{path}' + (f' contains {text}' if text else ' exists')))


# This verifier name is retained for backward compatibility with existing
# automation, but its release contract is now the final cross-stage identity.
need('pubspec.yaml', 'version: 22.9.8+229008')
need('lib/core/release/app_release_info.dart', "version = '22.9.8'")
need('lib/core/release/app_release_info.dart', 'buildNumber = 229008')
need('lib/core/release/app_release_info.dart', "channel = 'final'")
need('lib/core/release/app_release_info.dart', 'final-cross-stage-integrity-20260826')
need('lib/core/release/app_release_info.dart', '22.9.8-final-cross-stage-integrity-r57-r58-r59')
need('web/version.json', '"releaseToken": "final-cross-stage-integrity-20260826"')
need('web/version.json', '"channel": "final"')
need('tool/audit_ui_localization.py')
need('tool/final_release_check.ps1')

for f in [
    'kaj_universal_components.dart',
    'kaj_shell_components.dart',
    'kaj_entry_components.dart',
    'kaj_inventory_stage4_components.dart',
    'kaj_relationship_stage5_components.dart',
    'kaj_commercial_stage6_components.dart',
    'kaj_finance_stage7_components.dart',
    'kaj_admin_stage8_components.dart',
]:
    need('lib/design_system/' + f)

failed = [m for ok, m in checks if not ok]
if failed:
    print('FAIL Stage 09 current-release contract verification')
    for x in failed:
        print('-', x)
    sys.exit(1)

print('PASS Stage 09 current-release contract verification')
print(f'- {len(checks)} release, design-system, audit and delivery contracts verified')
print('- This verifier does not replace database/RPC integration or device/browser QA')
