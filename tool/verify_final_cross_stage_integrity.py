from __future__ import annotations
import json, re, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
errors=[]
def read(rel):
    p=ROOT/rel
    if not p.is_file(): errors.append(f'missing required file: {rel}'); return ''
    return p.read_text(encoding='utf-8', errors='strict')
def need(ok,msg):
    if not ok: errors.append(msg)
package_text=read('package.json')
try: package=json.loads(package_text)
except Exception as exc: package={'scripts':{}}; errors.append(f'package.json invalid: {exc}')
scripts=package.get('scripts',{})
pubspec=read('pubspec.yaml'); vm=re.search(r'^version:\s*([^\s]+)',pubspec,re.M); canonical=vm.group(1) if vm else ''
need(canonical=='22.9.8+229008','unexpected canonical version')
need(str(package.get('version',''))==canonical.split('+',1)[0],'package.json version does not match pubspec')
ops=read('README.md')+'\n'+read('README_AR.md')+'\n'+read('START_HERE_AR.md')
need('22.9.8+229008' in ops,'canonical version absent from operational docs')
need('Final Cross-Stage Integrity Closure' in ops,'final closure identity absent from operational docs')
need('R49 focused final completion' not in ops,'obsolete R49 final state remains in operational docs')
need('R49_FOCUSED_FINAL_COMPLETION_AR.md' not in ops,'obsolete R49 report remains referenced')
ws=scripts.get('verify:workspace','')
need(scripts.get('verify:all')=='npm run verify:workspace','verify:all is not workspace alias')
need('npm run verify:final-cross-stage' in ws,'workspace omits final cross-stage audit')
need('npm run verify:final-cross-stage' in scripts.get('verify:final',''),'verify:final omits final cross-stage audit')
for n in ('verify:stage11','verify:stage12','verify:stage12:storage','verify:final-cross-stage'): need(f'npm run {n}' in ws,f'{n} is not reachable from workspace')
config=read('supabase/config.toml'); seed=read('supabase/seed.sql')
need(re.search(r'\[db\.seed\][\s\S]*?enabled\s*=\s*true',config) is not None,'Supabase seed is not enabled')
need('sql_paths = ["./seed.sql"]' in config,'Supabase seed path is not ./seed.sql')
need('canonical Quality Line company is missing' in seed,'seed canonical company contract missing')
need('canonical MAIN branch is missing' in seed,'seed canonical branch contract missing')
need('IQD currency is missing' in seed and 'USD currency is missing' in seed,'seed currency contract missing')
md=ROOT/'supabase/migrations'; migrations=sorted(p.name for p in md.glob('*.sql')) if md.is_dir() else []
required=['20260826220000_r57_stage11_state_health_closure.sql','20260826230000_r58_stage12_document_path_integrity_closure.sql','20260826233000_r59_stage12_storage_object_version_closure.sql','20260826240000_r60_stage12_storage_helper_tenant_scope.sql','20260826250000_full_application_rpc_authorization_closure.sql','20260826260000_full_application_accounting_rpc_boundary_closure.sql','20260826270000_full_application_security_definer_execute_closure.sql']
for r in required: need(r in migrations,f'required closure migration is missing: {r}')
ids=[int(re.match(r'^(\d{14})_',n).group(1)) for n in migrations if re.match(r'^(\d{14})_',n)]; need(all(a<b for a,b in zip(ids,ids[1:])),'migration filenames are not strictly ordered')
for p in md.glob('*.sql'):
    t=p.read_text(encoding='utf-8',errors='strict'); low=t.lower()
    need(not re.search(r'\btruncate\s+',low),f'forbidden TRUNCATE in {p.name}')
    need(not re.search(r'\bdrop\s+database\b',low),f'forbidden DROP DATABASE in {p.name}')
    need(not re.search(r'\bdrop\s+schema\s+public\b',low),f'forbidden public schema drop in {p.name}')
r57=read('supabase/migrations/20260826220000_r57_stage11_state_health_closure.sql'); r58=read('supabase/migrations/20260826230000_r58_stage12_document_path_integrity_closure.sql'); r59=read('supabase/migrations/20260826233000_r59_stage12_storage_object_version_closure.sql'); r60=read('supabase/migrations/20260826240000_r60_stage12_storage_helper_tenant_scope.sql')
need('erp_r16_current_state_health' in r57 and 'erp_canonical_reconciliation_issues' in r57 and 'erp_canonical_deletion_tombstones' in r57,'R57 state-health closure incomplete')
need("p_company_id::text || '/' || p_document_id::text || '/' || p_version_id::text || '.bin'" in r58,'R58 canonical storage path missing')
need('erp_r59_document_storage_identity_valid' in r59 and "v.data->>'documentId'=d.id::text" in r59,'R59 identity binding incomplete')
need('public.erp_is_active_company_member(v_company)' in r60 and 'revoke all on function public.erp_r59_document_storage_identity_valid(text) from public,anon' in r60,'R60 tenant boundary incomplete')
client=read('lib/core/documents/repositories/document_storage_repository.dart'); need("$_companyId/$documentId/$versionId.bin" in client,'Flutter storage writer path contract missing')
v762=read('supabase/migrations/20260826250000_full_application_rpc_authorization_closure.sql'); v763=read('supabase/migrations/20260826260000_full_application_accounting_rpc_boundary_closure.sql'); exe=read('supabase/migrations/20260826270000_full_application_security_definer_execute_closure.sql')
need('erp_v762_assert_posted_journal_balanced' in v762 and "'sales.approve'" in v762 and "'purchases.approve'" in v762 and "'cashbox.payment'" in v762,'V7.6.2 authorization closure incomplete')
need('erp_v763_accounting_integrity_audit' in v763 and 'erp_cloud_trial_balance' in v763,'V7.6.3 accounting closure incomplete')
need('erp_v759_accounting_integrity_audit' in exe and 'erp_v761_accounting_integrity_audit' in exe and 'erp_v762_approve_workflow_invoice' in exe,'SECURITY DEFINER execute closure incomplete')
for p in md.glob('*.sql'):
    t=p.read_text(encoding='utf-8',errors='strict')
    for m in re.finditer(r'grant\s+execute\s+on\s+function\s+([^;]+?)\s+to\s+([^;]+);',t,re.I|re.S):
        if not re.search(r'\b(?:public|anon)\b',m.group(2).lower()): continue
        sig=re.sub(r'\s+',' ',m.group(1).strip()); closed=False
        for later in sorted(md.glob('*.sql')):
            if later.name<=p.name: continue
            lt=later.read_text(encoding='utf-8',errors='strict')
            if re.search(r'revoke\s+all\s+on\s+function\s+'+re.escape(sig)+r'\s+from\s+[^;]*\b(?:public|anon)\b[^;]*;',lt,re.I|re.S): closed=True; break
        need(closed,f'unsafe PUBLIC/anon execute grant in {p.name}: {m.group(0).strip()}')
    if 'security definer' in t.lower():
        for d in re.finditer(r'create\s+(?:or\s+replace\s+)?function\b[\s\S]*?(?=\n\s*create\s+(?:or\s+replace\s+)?function\b|\Z)',t,re.I):
            if re.search(r'\bsecurity\s+definer\b',d.group(0),re.I): need(re.search(r'\bset\s+search_path\s*=',d.group(0),re.I) is not None,f'SECURITY DEFINER without pinned search_path in {p.name}')
all_dart='\n'.join(p.read_text(encoding='utf-8',errors='strict') for p in (ROOT/'lib').rglob('*.dart')); all_sql='\n'.join(p.read_text(encoding='utf-8',errors='strict') for p in (ROOT/'supabase').rglob('*.sql'))
for domain,terms in {'accounting':('debit','credit','journal'),'inventory':('stock','movement'),'sales':('invoice','payment'),'purchases':('purchase','supplier'),'cash/bank':('cashbox','bank'),'partners/CRM':('customer','supplier'),'maintenance':('maintenance','vehicle')}.items(): need(any(x in all_dart.lower() for x in terms),f'{domain} source surface is not discoverable')
need('company_id' in all_sql.lower() and 'auth.uid()' in all_sql.lower() and 'create policy' in all_sql.lower(),'database tenant/RLS contracts incomplete')
for rel in ('tool/verify_stage11_full_program_closure.py','tool/verify_stage12_full_program_closure.py','tool/verify_stage12_storage_object_closure.py'): need((ROOT/rel).is_file(),f'missing closure verifier: {rel}')
need('erp_r16_current_state_health' in read('tool/verify_stage11_full_program_closure.py'),'Stage 11 verifier incomplete')
need('erp_r59_document_storage_identity_valid' in read('tool/verify_stage12_storage_object_closure.py'),'Stage 12 storage verifier incomplete')
need('erp_register_cloud_document_blob' in read('tool/verify_stage12_full_program_closure.py'),'Stage 12 registration verifier incomplete')
deploy=read('tool/deploy_r49_production.ps1'); need('$ExpectedMigrations' not in deploy and 'R57' not in deploy and 'R58' not in deploy and 'R59' not in deploy,'legacy deployment script still contains release-specific assumptions')
if errors:
    print('FAIL FINAL CROSS-STAGE INTEGRITY AUDIT'); [print('-',e) for e in errors]; sys.exit(1)
print('PASS FINAL CROSS-STAGE INTEGRITY AUDIT'); print(f'- canonical application version: {canonical}'); print('- R57/R58/R59/R60, authorization, tenant, RLS and historical execute-boundary closures checked')
