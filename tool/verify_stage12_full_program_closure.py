from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding='utf-8', errors='strict')


def need(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)

stage12 = read('supabase/migrations/20260826230000_r58_stage12_document_path_integrity_closure.sql')
r55 = read('supabase/migrations/20260826061000_r55_document_storage_permission_alignment.sql')
client = read('lib/core/documents/repositories/document_storage_repository.dart')

# The canonical writer and the database registration contract must describe
# exactly the same tenant/document/version path.
need("v_expected_path := p_company_id::text || '/' || p_document_id::text || '/' || p_version_id::text || '.bin'" in stage12,
     'Stage 12 does not construct the canonical company/document/version path')
need("if p_storage_path is distinct from v_expected_path then" in stage12,
     'Stage 12 does not reject document/version path mismatches')
need("'document_write_permission_required'" in stage12,
     'Stage 12 removed the document-level write authorization boundary')
need("p_storage_path=p_company_id::text || '/%'" not in stage12,
     'Stage 12 still permits company-rooted but document-mismatched paths')
need('not p_storage_path like' not in stage12,
     'Stage 12 path validation must not be bypassed by a permissive alternate path')
need("'storagePath',p_storage_path" in stage12,
     'Stage 12 does not persist the canonical path after validation')
need('revoke all on function public.erp_register_cloud_document_blob(uuid,uuid,uuid,text,bigint) from public,anon' in stage12,
     'Stage 12 registration RPC is not closed to anonymous/public execution')
need('erp_register_cloud_document_blob' in r55 and "'enterprise-documents'" in r55,
     'Stage 12 is not anchored to the existing R55 document-storage contract')
need("'$_companyId/$documentId/$versionId.bin'" in client,
     'Flutter storage writer does not use the canonical company/document/version path')

if errors:
    print('FAIL Stage 12 full-program closure')
    for error in errors:
        print(f'- {error}')
    raise SystemExit(1)

print('PASS Stage 12 document/storage integrity closure')
print('- storage registration is now bound to the exact company/document/version.bin identity')
print('- document-level write permission and tenant membership remain mandatory')
print('- anonymous/public execution remains revoked')
print('- Flutter writer and PostgreSQL registration use the same canonical path')
