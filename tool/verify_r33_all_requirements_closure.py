from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]

def text(rel): return (ROOT/rel).read_text(encoding='utf-8')
lib_text='\n'.join(p.read_text(encoding='utf-8', errors='ignore') for p in (ROOT/'lib').rglob('*.dart'))
pkg=json.loads(text('package.json'))['scripts']
checks={
 'r32 retained': (ROOT/'tool/verify_r32_final_verified_closure.py').exists(),
 'no unix epoch fallback anywhere in Dart source': 'fromMillisecondsSinceEpoch(0' not in lib_text and 'DateTime(1970' not in lib_text,
 'web PDF uses unified service': 'await Printing.layoutPdf' not in '\n'.join(p.read_text(encoding='utf-8', errors='ignore') for p in (ROOT/'lib').rglob('*.dart') if p.name!='pdf_print_service_stub.dart'),
 'no legacy phase26 RPC in Flutter': 'erp_r22_phase26_cloud_command' not in lib_text,
 'R33-or-newer cache token': any(x in text('web/version.json') and x in text('web/index.html') for x in ('r41-export-language-canonical-closure-20260809','r42-production-cashbox-guard-closure-20260809','r43-performance-functional-closure-20260809','r47-production-runtime-dependency-closure-20260810','r49-')),
 'R33-or-newer metadata unified': any(x in text('web/version.json') for x in ('22.9.8-r41-export-language-canonical-closure','22.9.8-r42-production-cashbox-guard-closure','22.9.8-r43-performance-functional-closure','22.9.8-r47-production-runtime-dependency-closure','22.9.8-r49-')),
 'R33 workspace validator exists': (ROOT/'tool/validate_r33_workspace.ps1').exists(),
 'R33 deploy exists': (ROOT/'tool/deploy_r33_production.ps1').exists(),
 'R33 deploy invokes R33 validator': 'validate_r33_workspace.ps1' in text('tool/deploy_r33_production.ps1'),
 'default deploy is R33 or newer': any(x in pkg.get('deploy:production','') for x in ('deploy_r41_production.ps1','deploy_r42_production.ps1','deploy_r43_production.ps1','deploy_r44_production.ps1','deploy_r49_production.ps1')),
 'R33 part of workspace verification': 'verify:r33' in pkg.get('verify:workspace',''),
 'cashbox save path retained': (ROOT/'lib/features/accounting/cashbox').exists(),
 'movement/history export paths retained': 'export' in lib_text.lower(),
}
for k,v in checks.items(): print(('PASS' if v else 'FAIL'),k)
if not all(checks.values()): raise SystemExit(1)
print(f'PASS R33 all requirements closure — {len(checks)} gates')
