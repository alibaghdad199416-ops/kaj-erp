from pathlib import Path
import json, re, sys
ROOT=Path(__file__).resolve().parents[1]
checks=[]
def need(path, text=None):
 p=ROOT/path
 ok=p.exists() and (text is None or text in p.read_text(encoding='utf-8',errors='ignore'))
 checks.append((ok,f'{path}' + (f' contains {text}' if text else ' exists')))
need('pubspec.yaml','version: 22.8.0+228000')
need('package.json','verify:v2280')
need('lib/core/release/app_release_info.dart',"channel = 'release-candidate'")
need('lib/core/release/app_release_info.dart','v2280-stage09-final-audit-20260807')
need('tool/audit_ui_localization.py')
need('tool/final_release_check.ps1')
need('docs/releases/RELEASE_22.8.0_STAGE9_FINAL_AUDIT_AR.md')
need('FINAL_RELEASE_CHECKLIST_22.8.0_AR.md')
for f in ['kaj_universal_components.dart','kaj_shell_components.dart','kaj_entry_components.dart','kaj_inventory_stage4_components.dart','kaj_relationship_stage5_components.dart','kaj_commercial_stage6_components.dart','kaj_finance_stage7_components.dart','kaj_admin_stage8_components.dart']:
 need('lib/design_system/'+f)
failed=[m for ok,m in checks if not ok]
if failed:
 print('FAIL V22.8 final release-candidate verification')
 for x in failed: print('-',x)
 sys.exit(1)
print('PASS V22.8 Stage 09 final release-candidate verification')
print(f'- {len(checks)} release, design-system, audit and delivery contracts verified')
print('- This verifier does not replace Flutter analyze/test/build or visual browser QA')
