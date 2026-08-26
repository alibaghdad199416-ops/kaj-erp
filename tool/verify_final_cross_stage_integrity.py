from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def read(rel: str) -> str:
    path = ROOT / rel
    if not path.is_file():
        errors.append(f'missing required file: {rel}')
        return ''
    return path.read_text(encoding='utf-8', errors='strict')


def need(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)


package_text = read('package.json')
try:
    package = json.loads(package_text)
except json.JSONDecodeError as exc:
    package = {'scripts': {}}
    errors.append(f'package.json is not valid JSON: {exc}')

scripts = package.get('scripts', {})
need(isinstance(scripts, dict), 'package.json scripts must be an object')
package_version = str(package.get('version', ''))
pubspec = read('pubspec.yaml')
version_match = re.search(r'^version:\s*([^\s]+)', pubspec, re.MULTILINE)
need(version_match is not None, 'pubspec.yaml has no canonical version')
canonical_version = version_match.group(1) if version_match else ''
canonical_base = canonical_version.split('+', 1)[0]

readme = read('README.md')
readme_ar = read('README_AR.md')
start_here = read('START_HERE_AR.md')
operational_docs = readme + '\n' + readme_ar + '\n' + start_here
need(canonical_version == '22.9.8+229008', 'unexpected canonical version')
need(package_version == canonical_base, 'package.json version does not match pubspec')
need('R49 focused final completion' not in operational_docs, 'obsolete R49 final state remains in operational docs')
need('R49_FOCUSED_FINAL_COMPLETION_AR.md' not in operational_docs, 'obsolete R49 report remains referenced')
need('22.9.8+229008' in operational_docs, 'canonical version is absent from operational docs')
need('Final Cross-Stage Integrity Closure' in operational_docs, 'final closure identity is absent from operational docs')

verify_workspace = scripts.get('verify:workspace', '')
verify_all = scripts.get('verify:all', '')
verify_final = scripts.get('verify:final', '')
need('npm run verify:final-cross-stage' in verify_workspace, 'workspace omits final cross-stage audit')
need(verify_all == 'npm run verify:workspace', 'verify:all is not the workspace alias')
need('npm run verify:final-cross-stage' in verify_final, 'verify:final omits final cross-stage audit')

workspace_refs = set(re.findall(r'npm run (verify:r\d+)', verify_workspace))
package_r_verifiers = {name for name, command in scripts.items() if re.fullmatch(r'verify:r\d+', name) and isinstance(command, str)}
missing_r_verifiers = sorted(package_r_verifiers - workspace_refs, key=lambda x: int(x[8:]))
need(not missing_r_verifiers, 'workspace omits release verifiers: ' + ', '.join(missing_r_verifiers))

for script_name, expected in {
    'verify:stage11': 'tool/verify_stage11_full_program_closure.py',
    'verify:stage12': 'tool/verify_stage12_full_program_closure.py',
    'verify:stage12:storage': 'tool/verify_stage12_storage_object_closure.py',
    'verify:final-cross-stage': 'tool/verify_final_cross_stage_integrity.py',
}.items():
    need(scripts.get(script_name) == f'python -B {expected}', f'{script_name} wiring mismatch')
    need(f'npm run {script_name}' in verify_workspace, f'{script_name} is not reachable from workspace')

migrations_dir = ROOT / 'supabase' / 'migrations'
migrations = sorted(p.name for p in migrations_dir.glob('*.sql')) if migrations_dir.is_dir() else []
for required in (
    '20260826220000_r57_stage11_state_health_closure.sql',
    '20260826230000_r58_stage12_document_path_integrity_closure.sql',
    '20260826233000_r59_stage12_storage_object_version_closure.sql',
    '20260826240000_r60_stage12_storage_helper_tenant_scope.sql',
    '20260826250000_full_application_rpc_authorization_closure.sql',
    '20260826260000_full_application_accounting_rpc_boundary_closure.sql',
):
    need(required in migrations, f'required closure migration is missing: {required}')

migration_ids: list[tuple[int, str]] = []
for name in migrations:
    match = re.match(r'^(\d{14})_', name)
    if match:
        migration_ids.append((int(match.group(1)), name))
need(all(a[0] < b[0] for a, b in zip(migration_ids, migration_ids[1:])), 'migration filenames are not strictly ordered')

for sql in migrations_dir.glob('*.sql'):
    text = sql.read_text(encoding='utf-8', errors='strict')
    lower = text.lower()
    need(not re.search(r'\btruncate\s+', lower), f'forbidden TRUNCATE in {sql.name}')
    need(not re.search(r'\bdrop\s+database\b', lower), f'forbidden DROP DATABASE in {sql.name}')
    need(not re.search(r'\bdrop\s+schema\s+public\b', lower), f'forbidden public schema drop in {sql.name}')

r57 = read('supabase/migrations/20260826220000_r57_stage11_state_health_closure.sql')
need('create or replace function public.erp_r16_current_state_health(p_company_id uuid)' in r57, 'R57 health RPC missing')
need('from public.erp_canonical_reconciliation_issues' in r57, 'R57 health omits reconciliation issues')
need('from public.erp_canonical_deletion_tombstones' in r57, 'R57 health omits tombstones')
need("'persistentDeletionConflictCount'" in r57, 'R57 health omits persistent deletion conflicts')
need("'unresolvedCanonicalReconciliationIssueCount'" in r57, 'R57 health omits unresolved canonical issues')
need("'canonicalStateVersion', 16" in r57, 'R57 health omits canonical state version')
need('public.erp_r15_reconcile_company_state(p_company_id)' not in r57, 'R57 health calls mutating reconciliation')
need(re.search(r'v_conflicts\s*:=\s*v_conflicts\s*\+', r57) is not None, 'R57 conflict count is not cumulative')
need('revoke all on function public.erp_r16_current_state_health(uuid) from anon' in r57, 'R57 health remains executable by anon')

r58 = read('supabase/migrations/20260826230000_r58_stage12_document_path_integrity_closure.sql')
r59 = read('supabase/migrations/20260826233000_r59_stage12_storage_object_version_closure.sql')
r60 = read('supabase/migrations/20260826240000_r60_stage12_storage_helper_tenant_scope.sql')
r55 = read('supabase/migrations/20260826061000_r55_document_storage_permission_alignment.sql')
client_storage = read('lib/core/documents/repositories/document_storage_repository.dart')
canonical_path = "p_company_id::text || '/' || p_document_id::text || '/' || p_version_id::text || '.bin'"
need(canonical_path in r58, 'R58 storage path contract missing')
need("if p_storage_path is distinct from v_expected_path then" in r58, 'R58 does not reject identity mismatch')
need("'document_write_permission_required'" in r58, 'R58 lacks document authorization')
need('erp_r59_document_storage_identity_valid' in r59, 'R59 identity validation missing')
need("v.data->>'documentId'=d.id::text" in r59, 'R59 version/document binding missing')
need("v_file !~*" in r59 and r"\\.bin$" in r59, 'R59 filename contract missing')
need('not public.erp_r59_document_storage_identity_valid(p_name) then return false;' in r59, 'R59 guards do not enforce identity')
need("bucket_id='enterprise-documents'" in r59, 'R59 bucket scope missing')
need("'$_companyId/$documentId/$versionId.bin'" in client_storage, 'Flutter storage writer path contract missing')
need('erp_register_cloud_document_blob' in r55, 'R55 registration contract missing')
need('public.erp_is_active_company_member(v_company)' in r60, 'R60 tenant membership boundary missing')
need("revoke all on function public.erp_r59_document_storage_identity_valid(text) from public,anon" in r60, 'R60 helper is not closed to public/anon')

v762_fix = read('supabase/migrations/20260826250000_full_application_rpc_authorization_closure.sql')
need('public.erp_v762_assert_posted_journal_balanced' in v762_fix, 'V7.6.2 journal helper closure missing')
need("revoke all on function public.erp_v762_assert_posted_journal_balanced(uuid,text,text) from public,anon,authenticated" in v762_fix, 'V7.6.2 journal helper remains directly callable by browser sessions')
need('public.is_active_company_member(p_company_id)' in v762_fix, 'V7.6.2 tenant membership check missing')
need("'sales.approve'" in v762_fix and "'purchases.approve'" in v762_fix, 'V7.6.2 approval permission checks missing')
need("'cashbox.payment'" in v762_fix, 'V7.6.2 payment permission check missing')
need("'maintenance.view'" in v762_fix, 'V7.6.2 maintenance view boundary missing')

v763_fix = read('supabase/migrations/20260826260000_full_application_accounting_rpc_boundary_closure.sql')
need('public.erp_v763_accounting_integrity_audit' in v763_fix, 'V7.6.3 accounting audit closure missing')
need('public.erp_cloud_trial_balance' in v763_fix, 'V7.6.3 trial-balance closure missing')
need('public.is_active_company_member(p_company_id)' in v763_fix, 'V7.6.3 tenant membership check missing')
need('revoke all on function public.erp_v763_accounting_integrity_audit(uuid) from public,anon' in v763_fix, 'V7.6.3 audit RPC grant boundary missing')

for sql in migrations_dir.glob('*.sql'):
    text = sql.read_text(encoding='utf-8', errors='strict')
    for match in re.finditer(r'grant\s+execute\s+on\s+function\s+([^;]+?)\s+to\s+(public|anon)\s*;', text, re.IGNORECASE | re.DOTALL):
        errors.append(f'unsafe PUBLIC/anon execute grant in {sql.name}: {match.group(0).strip()}')
    if 'security definer' in text.lower():
        defs = re.finditer(r'create\s+(?:or\s+replace\s+)?function\b.*?security\s+definer.*?as\s+\$\$', text, re.IGNORECASE | re.DOTALL)
        for definition in defs:
            need(re.search(r'set\s+search_path\s*=', definition.group(0), re.IGNORECASE) is not None, f'SECURITY DEFINER without pinned search_path in {sql.name}')

all_dart = '\n'.join(p.read_text(encoding='utf-8', errors='strict') for p in (ROOT / 'lib').rglob('*.dart')) if (ROOT / 'lib').is_dir() else ''
all_sql = '\n'.join(p.read_text(encoding='utf-8', errors='strict') for p in (ROOT / 'supabase').rglob('*.sql')) if (ROOT / 'supabase').is_dir() else ''
all_dart_lower = all_dart.lower()
all_sql_lower = all_sql.lower()
for domain, terms in {
    'accounting': ('debit', 'credit', 'journal'),
    'inventory': ('stock', 'movement'),
    'sales': ('invoice', 'payment'),
    'purchases': ('purchase', 'supplier'),
    'cash/bank': ('cashbox', 'bank'),
    'partners/CRM': ('customer', 'supplier'),
    'maintenance': ('maintenance', 'vehicle'),
}.items():
    need(any(term in all_dart_lower for term in terms), f'{domain} source surface is not discoverable')
need('company_id' in all_sql_lower, 'database source contains no company scoping contract')
need('auth.uid()' in all_sql_lower, 'database source contains no authenticated-user boundary')
need('create policy' in all_sql_lower, 'database source contains no RLS policy definitions')

deploy_r49 = read('tool/deploy_r49_production.ps1')
need('$ExpectedMigrations' not in deploy_r49, 'legacy deployment script still hard-codes R49 migration allow-list')
need('supabase\\migrations' in deploy_r49.lower() or 'supabase/migrations' in deploy_r49.lower(), 'deployment orchestration does not discover migrations')
need('R57' not in deploy_r49 and 'R58' not in deploy_r49 and 'R59' not in deploy_r49, 'legacy deployment script contains release-specific assumptions')
deploy_production = read('tool/deploy_production.ps1')
need('deploy_production.ps1' in scripts.get('deploy:supabase', ''), 'deploy:supabase wiring mismatch')
need('deploy_production.ps1' in scripts.get('deploy:firebase', ''), 'deploy:firebase wiring mismatch')

stage11 = read('tool/verify_stage11_full_program_closure.py')
stage12 = read('tool/verify_stage12_full_program_closure.py')
storage12 = read('tool/verify_stage12_storage_object_closure.py')
need('erp_r16_current_state_health' in stage11, 'Stage 11 regression verifier missing')
need('erp_r59_document_storage_identity_valid' in storage12, 'Stage 12 storage regression verifier missing')
need('erp_register_cloud_document_blob' in stage12, 'Stage 12 registration regression verifier missing')

if errors:
    print('FAIL FINAL CROSS-STAGE INTEGRITY AUDIT')
    for error in errors:
        print(f'- {error}')
    raise SystemExit(1)

print('PASS FINAL CROSS-STAGE INTEGRITY AUDIT')
print(f'- canonical application version: {canonical_version}')
print('- R57/R58/R59/R60 plus independent V7.6.2/V7.6.3 authorization closures are checked')
print('- canonical state, storage identity, tenant authorization, SECURITY DEFINER boundaries and ERP domain surfaces are checked')
