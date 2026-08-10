from pathlib import Path
import json, re, sys
root = Path(__file__).resolve().parents[1]
checks = []
def require(cond, msg):
    checks.append((cond,msg))
    if not cond:
        print('FAIL', msg)

require('version: 22.8.1+228001' in (root/'pubspec.yaml').read_text(encoding='utf-8'), 'pubspec version')
package=json.loads((root/'package.json').read_text(encoding='utf-8'))
require(package.get('version')=='22.8.1','package version')
require('verify:v2281' in package.get('scripts',{}),'v2281 verifier command')
commercial=(root/'lib/design_system/kaj_commercial_stage6_components.dart').read_text(encoding='utf-8')
require('KajSystemStateTone' not in commercial,'commercial state uses current API')
require('loading: true' not in commercial,'commercial loading uses current API')
require('actionLabel: actionLabel' not in commercial,'commercial empty action uses Widget API')
tokens=(root/'lib/design_system/kaj_design_tokens.dart').read_text(encoding='utf-8')
require('warningAmber = warning' in tokens,'warning semantic alias')
require('pageBackground(Brightness brightness)' in tokens,'page background semantic alias')
ps=(root/'tool/final_release_check.ps1').read_text(encoding='utf-8')
require('$LASTEXITCODE -ne 0' in ps and 'Invoke-Checked' in ps,'release check fails fast')
require("flutter analyze --fatal-infos --fatal-warnings" in ps,'fatal analyzer gate')
require("npm run build:web" in ps,'web build gate')
if not all(x for x,_ in checks): sys.exit(1)
print('PASS V22.8.1 final release corrective verification')
print(f'- {len(checks)} corrective contracts verified')
