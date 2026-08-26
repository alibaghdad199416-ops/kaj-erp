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


# ---------------------------------------------------------------------------
# Release identity and verification entrypoints
# ---------------------------------------------------------------------------
package_text = read('package.json')
try:
    package = json.loads(package_text)
except json.JSONDecodeError as exc:
    package = {'scripts': {}}
    errors.append(f'package.json is not valid JSON: {exc}')

scripts = package.get('scripts', {})
need(isinstance(scripts, dict), 'package.json scripts must be an object')

pubspec = read('pubspec.yaml')
version_match = re.search(r'^version:\s*([^\s]+)', pubspec, re.MULTILINE)
need(version_match is not None, 'pubspec.yaml has no canonical version')
canonical_version = version_match.group(1) if version_match else ''

readme = read('README.md')
readme_ar = read('README_AR.md')
start_here = read('START_HERE_AR.md')
operational_docs = readme + '\n' + readme_ar + '\n' + start_here

need(canonical_version == '22.9.8+229008', 'unexpected canonical version; do not change version without an explicit release decision')
need('R49 focused final completion' not in operational_docs, 'operational documentation still identifies R49 as the current final state')
need('R49_FOCUSED_FINAL_COMPLETION_AR.md' not in operational_docs, 'operational documentation still points at the obsolete R49 final report')
need('22.9.8+229008' in operational_docs, 'operational documentation does not identify the canonical application version')
need('Final Cross-Stage Integrity Closure' in operational_docs, 'operational documentation does not identify the final cross-stage closure state')

verify_workspace = scripts.get('verify:workspace', '')
verify_all = scripts.get('verify:all', '')
verify_final = scripts.get('verify:final', '')
need('npm run verify:final-cross-stage' in verify_workspace, 'verify:workspace does not include the authoritative final cross-stage audit')
need(verify_all == 'npm run verify:workspace', 'verify:all is not an exact alias of the authoritative workspace chain')
need('npm run verify:final-cross-stage' in verify_final, 'verify:final does not include the final cross-stage audit')

# Every numbered R verifier that is exposed by package.json must be on the
# workspace chain; otherwise a new release verifier can silently become dead code.
workspace_refs = set(re.findall(r'npm run (verify:r\d+)', verify_workspace))
package_r_verifiers = {
    name for name, command in scripts.items()
    if re.fullmatch(r'verify:r\d+', name) and isinstance(command, str)
}
missing_r_verifiers = sorted(package_r_verifiers - workspace_refs, key=lambda x: int(x[8:]))
need(not missing_r_verifiers, 'verify:workspace omits package release verifiers: ' + ', '.join(missing_r_verifiers))

# Stage verifiers are discovered from the repository rather than maintained as
# a fragile hard-coded list. Every stage 0..12 must have at least one verifier,
# and every discovered stage verifier must be reachable from the final chain.
stage_files = sorted((ROOT / 'tool').glob('verify_stage*.py'))
stage_numbers: dict[int, list[Path]] = {}
for path in stage_files:
    match = re.match(r'verify_stage(\d+)', path.name)
    if match:
        stage_numbers.setdefault(int(match.group(1)), []).append(path)
for stage in range(13):
    need(stage in stage_numbers, f'missing verifier coverage for stage {stage}')
for path in stage_files:
    name = path.stem
    command_name = f'verify:{name}'
    need(command_name in scripts, f'stage verifier {path.name} is not exposed in package.json as {command_name}')
    if command_name in scripts:
        need(f'npm run {command_name}' in verify_workspace, f'{command_name} is not reachable from verify:workspace')

# ---------------------------------------------------------------------------
# Migration ordering and forward-only safety
# ---------------------------------------------------------------------------
migrations_dir = ROOT / 'supabase' / 'migrations'
migrations = sorted(p.name for p in migrations_dir.glob('*.sql')) if migrations_dir.is_dir() else []
need('20260826220000_r57_stage11_state_health_closure.sql' in migrations, 'R57 migration is missing')
need('20260826230000_r58_stage12_document_path_integrity_closure.sql' in migrations, 'R58 migration is missing')
need('20260826233000_r59_stage12_storage_object_version_closure.sql' in migrations, 'R59 migration is missing')

migration_ids: list[tuple[int, str]] = []
for name in migrations:
    match = re.match(r'^(\d{14})_', name)
    if match:
        migration_ids.append((int(match.group(1)), name))
need(all(a[0] < b[0] for a, b in zip(migration_ids, migration_ids[1:])), 'migration filenames are not strictly ordered')

for sql in (ROOT / 'supabase' / 'migrations').glob('*.sql'):
    text = sql.read_text(encoding='utf-8', errors='strict')
    lower = text.lower()
    need(not re.search(r'\btruncate\s+', lower), f'forbidden TRUNCATE found in migration {sql.name}')
    need(not re.search(r'\bdrop\s+database\b', lower), f'forbidden DROP DATABASE found in migration {sql.name}')
    need(not re.search(r'\bdrop\s+schema\s+public\b', lower), f'forbidden public schema drop found in migration {sql.name}')

# ---------------------------------------------------------------------------
# Canonical state contract (R16/R21/R22/R23/R57 successors)
# ---------------------------------------------------------------------------
r57 = read('supabase/migrations/20260826220000_r57_stage11_state_health_closure.sql')
need('create or replace function public.erp_r16_current_state_health(p_company_id uuid)' in r57, 'R57 does not restore the canonical state health RPC')
need('from public.erp_canonical_reconciliation_issues' in r57, 'R57 health does not read reconciliation issues')
need('from public.erp_canonical_deletion_tombstones' in r57, 'R57 health does not read deletion tombstones')
need("'persistentDeletionConflictCount'" in r57, 'R57 health omits persistent deletion conflicts')
need("'unresolvedCanonicalReconciliationIssueCount'" in r57, 'R57 health omits unresolved canonical issues')
need("'canonicalStateVersion', 16" in r57, 'R57 health does not identify canonical state version 16')
need('public.erp_r15_reconcile_company_state(p_company_id)' not in r57, 'R57 health calls the mutating reconciliation RPC')
need(re.search(r'v_conflicts\s*:=\s*v_conflicts\s*\+', r57) is not None, 'R57 conflict counting is not cumulative')
need('revoke all on function public.erp_r16_current_state_health(uuid) from anon' in r57, 'R57 health RPC is not closed to anon')

# ---------------------------------------------------------------------------
# Storage identity and authorization (R54/R55/R58/R59)
# ---------------------------------------------------------------------------
r58 = read('supabase/migrations/20260826230000_r58_stage12_document_path_integrity_closure.sql')
r59 = read('supabase/migrations/20260826233000_r59_stage12_storage_object_version_closure.sql')
r55 = read('supabase/migrations/20260826061000_r55_document_storage_permission_alignment.sql')
client_storage = read('lib/core/documents/repositories/document_storage_repository.dart')
canonical_path = "p_company_id::text || '/' || p_document_id::text || '/' || p_version_id::text || '.bin'"
need(canonical_path in r58, 'R58 registration RPC is not bound to company/document/version.bin')
need("if p_storage_path is distinct from v_expected_path then" in r58, 'R58 does not reject mismatched storage identity')
need("'document_write_permission_required'" in r58, 'R58 removed document-level authorization')
need('erp_r59_document_storage_identity_valid' in r59, 'R59 does not validate direct storage object identity')
need("v.data->>'documentId'=d.id::text" in r59, 'R59 does not bind version to parent document')
need("v_file !~*" in r59 and r"\\.bin$" in r59, 'R59 does not require a UUID version.bin filename')
need('not public.erp_r59_document_storage_identity_valid(p_name) then return false;' in r59, 'R59 read/write guards do not enforce version identity')
need("bucket_id='enterprise-documents'" in r59, 'R59 policies are not scoped to the enterprise-documents bucket')
need("'$_companyId/$documentId/$versionId.bin'" in client_storage, 'Flutter storage writer does not use canonical company/document/version identity')
need('erp_register_cloud_document_blob' in r55, 'R55 storage registration contract is missing from the successor chain')

# Public/anonymous execute grants are a direct authorization smell. Existing
# historical SQL is still scanned; a violation cannot be hidden by the latest migration.
for sql in (ROOT / 'supabase' / 'migrations').glob('*.sql'):
    text = sql.read_text(encoding='utf-8', errors='strict')
    for match in re.finditer(r'grant\s+execute\s+on\s+function\s+([^;]+?)\s+to\s+(public|anon)\s*;', text, re.IGNORECASE | re.DOTALL):
        errors.append(f'unsafe PUBLIC/anon function execute grant in {sql.name}: {match.group(0).strip()}')

# SECURITY DEFINER functions must pin search_path; this is enforced statically
# for every definition in the migration set.
for sql in (ROOT / 'supabase' / 'migrations').glob('*.sql'):
    text = sql.read_text(encoding='utf-8', errors='strict')
    if 'security definer' in text.lower():
        defs = re.finditer(r'create\s+(?:or\s+replace\s+)?function\b.*?security\s+definer.*?as\s+\$\$', text, re.IGNORECASE | re.DOTALL)
        for definition in defs:
            snippet = definition.group(0)
            need('set search_path=' in snippet.lower(), f'SECURITY DEFINER function without pinned search_path in {sql.name}')

# ---------------------------------------------------------------------------
# ERP cross-stage source contracts
# ---------------------------------------------------------------------------
all_dart = '\n'.join(p.read_text(encoding='utf-8', errors='strict') for p in (ROOT / 'lib').rglob('*.dart')) if (ROOT / 'lib').is_dir() else ''
all_sql = '\n'.join(p.read_text(encoding='utf-8', errors='strict') for p in (ROOT / 'supabase').rglob('*.sql')) if (ROOT / 'supabase').is_dir() else ''

for domain, terms in {
    'accounting': ('debit', 'credit', 'journal'),
    'inventory': ('stock', 'movement'),
    'sales': ('invoice', 'payment'),
    'purchases': ('purchase', 'supplier'),
    'cash/bank': ('cashbox', 'bank'),
    'partners/CRM': ('customer', 'supplier'),
    'maintenance': ('maintenance', 'vehicle'),
}.items():
    need(any(term.lower() in all_dart.lower() for term in terms), f'{domain} source surface is not discoverable from lib/')

need('company_id' in all_sql.lower(), 'database source contains no company scoping contract')
need('auth.uid()' in all_sql.lower(), 'database source contains no authenticated-user boundary')
need('create policy' in all_sql.lower(), 'database source contains no RLS policy definitions')

# ---------------------------------------------------------------------------
# Deployment orchestration is source-only here; this verifier never deploys.
# ---------------------------------------------------------------------------
deploy_r49 = read('tool/deploy_r49_production.ps1')
need('$ExpectedMigrations' not in deploy_r49, 'deploy_r49_production.ps1 still hard-codes an R49-only ExpectedMigrations allow-list')
need('supabase/migrations' in deploy_r49, 'deployment orchestration does not discover the repository migration set')
need('R57' not in deploy_r49 and 'R58' not in deploy_r49 and 'R59' not in deploy_r49, 'legacy R49 deployment script contains release-specific migration assumptions')

# Deployment scripts must not be pulled into verification by actually running
# deployment commands. The final audit only checks source wiring.
deploy_production = read('tool/deploy_production.ps1')
need('deploy_production.ps1' in scripts.get('deploy:supabase', ''), 'deploy:supabase is not wired to the shared deployment orchestrator')
need('deploy_production.ps1' in scripts.get('deploy:firebase', ''), 'deploy:firebase is not wired to the shared deployment orchestrator')

# ---------------------------------------------------------------------------
# Regression protection for the two confirmed closure gaps.
# ---------------------------------------------------------------------------
stage11 = read('tool/verify_stage11_full_program_closure.py')
stage12 = read('tool/verify_stage12_full_program_closure.py')
storage12 = read('tool/verify_stage12_storage_object_closure.py')
need('erp_r16_current_state_health' in stage11, 'Stage 11 regression verifier is not present')
need('erp_r59_document_storage_identity_valid' in storage12, 'Stage 12 storage-object regression verifier is not present')
need('erp_register_cloud_document_blob' in stage12, 'Stage 12 registration regression verifier is not present')

if errors:
    print('FAIL FINAL CROSS-STAGE INTEGRITY AUDIT')
    for error in errors:
        print(f'- {error}')
    raise SystemExit(1)

print('PASS FINAL CROSS-STAGE INTEGRITY AUDIT')
print(f'- canonical application version: {canonical_version}')
print('- verification chain covers package release verifiers and discovered stage 0..12 verifiers')
print('- R57/R58/R59 migration ordering and forward-only safety are checked')
print('- canonical state, document/storage identity, authorization, and SECURITY DEFINER boundaries are checked')
print('- deployment migration discovery is checked without executing deployment')
print('- Flutter/database source contracts and ERP domain surfaces are checked')
