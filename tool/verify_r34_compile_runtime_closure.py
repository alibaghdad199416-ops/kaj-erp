from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[1]

def text(rel): return (ROOT/rel).read_text(encoding='utf-8')
lib_files=list((ROOT/'lib').rglob('*.dart'))
lib_text='\n'.join(p.read_text(encoding='utf-8', errors='ignore') for p in lib_files)
pkg=json.loads(text('package.json'))['scripts']

# Exact literal duplicate-key audit for the operational translation catalog.
catalog=text('lib/core/localization/module_translation_catalog.dart')
key_pattern=re.compile(r"^\s*'((?:\\'|[^'])*)'\s*:\s*", re.M)
keys=key_pattern.findall(catalog)
duplicate_keys=sorted({k for k in keys if keys.count(k)>1})

# Export enum contract: every ExportValueType.<name> must exist in the enum.
export_doc=text('lib/core/exporting/export_document.dart')
m=re.search(r'enum\s+ExportValueType\s*\{([^}]*)\}', export_doc, re.S)
allowed={x.strip() for x in m.group(1).split(',') if x.strip()} if m else set()
used=set(re.findall(r'ExportValueType\.([A-Za-z_]\w*)', lib_text))
unknown_export_types=sorted(used-allowed)

details=text('lib/features/sales/workflow/pages/order_details_dialog.dart')
pdf_web=text('lib/core/exporting/pdf_print_service_web.dart')
cash_repo=text('lib/features/accounting/cashbox/repositories/cashbox_repository.dart')

checks={
 'R33 retained': (ROOT/'tool/verify_r33_all_requirements_closure.py').exists(),
 'translation catalog has no duplicate literal keys': not duplicate_keys,
 'all ExportValueType references exist': not unknown_export_types,
 'order detail list rendering has no broken multiline quote': ".join(' | ')" in details and (".join('" + chr(10)) not in details,
 'web PDF has no impossible nullable-window branch': 'opened == null' not in pdf_web and 'final opened =' not in pdf_web,
 'cashbox repository has no unused legacy cloud field': 'CloudMasterDataService _cloud' not in cash_repo and 'cloud_master_data_service.dart' not in cash_repo,
 'no unix epoch fallback anywhere in Dart source': 'fromMillisecondsSinceEpoch(0' not in lib_text and 'DateTime(1970' not in lib_text,
 'no legacy phase26 RPC in Flutter': 'erp_r22_phase26_cloud_command' not in lib_text,
 'R34 cache token or newer': any(x in text('web/version.json') and x in text('web/index.html') for x in ('r41-export-language-canonical-closure-20260809','r42-production-cashbox-guard-closure-20260809','r43-performance-functional-closure-20260809','r47-production-runtime-dependency-closure-20260810','r49-')),
 'R34 metadata or newer unified': any(x in text('web/version.json') for x in ('22.9.8-r41-export-language-canonical-closure','22.9.8-r42-production-cashbox-guard-closure','22.9.8-r43-performance-functional-closure','22.9.8-r47-production-runtime-dependency-closure','22.9.8-r49-')),
 'R34 validator exists': (ROOT/'tool/validate_r34_workspace.ps1').exists(),
 'R34 deploy exists': (ROOT/'tool/deploy_r34_production.ps1').exists(),
 'R34 deploy invokes R34 validator': 'validate_r34_workspace.ps1' in text('tool/deploy_r34_production.ps1'),
 'default deploy is R34 or newer': any(x in pkg.get('deploy:production','') for x in ('deploy_r41_production.ps1','deploy_r42_production.ps1','deploy_r43_production.ps1','deploy_r44_production.ps1','deploy_r49_production.ps1')),
 'R34 part of workspace verification': 'verify:r34' in pkg.get('verify:workspace',''),
}
for k,v in checks.items(): print(('PASS' if v else 'FAIL'),k)
if duplicate_keys: print('duplicate keys:', duplicate_keys)
if unknown_export_types: print('unknown ExportValueType names:', unknown_export_types)
if not all(checks.values()): raise SystemExit(1)
print(f'PASS R34 compile/runtime closure — {len(checks)} gates')
