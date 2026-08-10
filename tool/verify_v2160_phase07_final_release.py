from pathlib import Path
import json, re, sys
ROOT=Path(__file__).resolve().parents[1]
errors=[]
def need(path, text):
 p=ROOT/path
 if not p.exists(): errors.append(f"missing {path}"); return
 s=p.read_text(encoding='utf-8', errors='ignore')
 if text not in s: errors.append(f"{path}: missing {text}")
need(Path('pubspec.yaml'),'version: 21.6.0+216000')
need(Path('lib/core/release/app_release_info.dart'),"channel = 'production'")
need(Path('lib/core/release/app_release_info.dart'),'v2160-phase07-final-release-20260807')
need(Path('package.json'),'verify:final')
need(Path('COMMANDS_21.6.0_FINAL_AR.md'),'npm run verify:final')
need(Path('docs/releases/RELEASE_21.6.0_FINAL_AR.md'),'المرحلة 7')
# structural anti-regression checks
for p in (ROOT/'lib').rglob('*.dart'):
 s=p.read_text(encoding='utf-8', errors='ignore')
 if '<<<<<<<' in s or '>>>>>>>' in s or '\n=======' in s: errors.append(f'merge marker: {p.relative_to(ROOT)}')
 if re.search(r'fontWeight:\s*FontWeight\.w(\d+)',s):
  for n in re.findall(r'fontWeight:\s*FontWeight\.w(\d+)',s):
   if n not in {'100','200','300','400','500','600','700','800','900'}: errors.append(f'unsupported weight w{n}: {p.relative_to(ROOT)}')
# required phase design layers
for f in ['kaj_signature_components.dart','kaj_inventory_components.dart','kaj_phase4_components.dart','kaj_phase5_components.dart','kaj_phase6_components.dart']:
 if not (ROOT/'lib/design_system'/f).exists(): errors.append(f'missing design system layer {f}')
if errors:
 print('FAIL V21.6 final release verification')
 for e in errors: print('-',e)
 sys.exit(1)
print('PASS V21.6 Phase 7 final release verification')
print('- production release metadata aligned')
print('- final command and release documentation present')
print('- design-system phase layers present')
print('- no unresolved merge markers or unsupported weights')
