from pathlib import Path
import json, re, sys
ROOT=Path(__file__).resolve().parents[1]
def read(p): return (ROOT/p).read_text(encoding='utf-8')
checks={}
inv=read('lib/features/inventory/pages/inventory_page.dart')
maint=read('lib/features/maintenance/data/maintenance_repository.dart')
mig=read('supabase/migrations/20260809161514_r39_canonical_maintenance_compile_closure.sql')
pkg=json.loads(read('package.json'))
ver=json.loads(read('web/version.json'))
inv_compact=re.sub(r'\s+',' ',inv)
checks['product details runtime-localized DataTable compiles'] = re.search(r'columns:\s*const\s*\[\s*DataColumn\(\s*label:\s*AppText\(\s*context\.l10n', inv) is None and re.search(r'columns:\s*\[\s*DataColumn\(\s*label:\s*AppText\(\s*context\.l10n', inv) is not None
checks['maintenance create canonical r39'] = ('erp_r39_create_cloud_maintenance_order' in maint or 'erp_r49_create_cloud_maintenance_order' in maint or 'erp_r56_create_cloud_maintenance_order' in maint)
checks['maintenance edit canonical r39'] = ('erp_r39_update_cloud_maintenance_draft' in maint or 'erp_r49_update_cloud_maintenance_draft' in maint) and "'erp_update_cloud_maintenance_draft'" not in maint
checks['maintenance create resolves vehicle aliases'] = all(x in mig for x in ["data->>'carId'","data->>'car_id'","data->>'vehicleId'","data->>'vehicle_id'"])
checks['maintenance edit supports empty parts'] = "jsonb_array_length(v_parts)>0" in mig and "update public.erp_maintenance_parts" in mig
checks['maintenance edit preserves lifecycle'] = 'erp_v67_prepare_maintenance_linked_edit' in mig and 'erp_v67_advance_maintenance_internal' in mig
checks['R39 grants and schema reload'] = 'grant execute on function public.erp_r39_create_cloud_maintenance_order' in mig and "notify pgrst,'reload schema'" in mig
checks['R39 metadata'] = str(ver.get('releaseToken','')).startswith(('r39-','r40-','r41-','r42-','r43-','r44-','r45-','r46-','r47-','r48-','r49-'))
checks['R39 default deploy'] = any(f'deploy_r{n}_production.ps1' in pkg['scripts'].get('deploy:production','') for n in range(39,60))
checks['R39 workspace gate'] = 'verify:r39' in pkg['scripts'].get('verify:workspace','')
# Catch the compile class of error found during this audit.
for f in (ROOT/'lib').rglob('*.dart'):
    t=f.read_text(encoding='utf-8')
    for m in re.finditer(r'const\s*\[(.{0,1600}?)\]',t,re.S):
        if 'context.' in m.group(0):
            checks[f'no runtime context inside const list: {f.relative_to(ROOT)}:{t.count(chr(10),0,m.start())+1}']=False
for n,ok in checks.items(): print(('PASS' if ok else 'FAIL'),n)
if not all(checks.values()): sys.exit(1)
print(f'PASS R39 canonical acceptance — {len(checks)} gates')
