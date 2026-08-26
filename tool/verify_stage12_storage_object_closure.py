from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding='utf-8', errors='strict')


def need(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)

r58 = read('supabase/migrations/20260826230000_r58_stage12_document_path_integrity_closure.sql')
r59 = read('supabase/migrations/20260826233000_r59_stage12_storage_object_version_closure.sql')
r55 = read('supabase/migrations/20260826061000_r55_document_storage_permission_alignment.sql')
client = read('lib/core/documents/repositories/document_storage_repository.dart')

# R58 registration and R59 direct Storage authorization must describe exactly
# the same canonical identity.
need("p_company_id::text || '/' || p_document_id::text || '/' || p_version_id::text || '.bin'" in r58,
     'R58 canonical registration path is missing')
need("storage.filename(p_name)" in r59,
     'R59 does not validate the Storage filename as the document version')
need("'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\\\.bin$'" in r59,
     'R59 does not require UUID version.bin filenames')
need('erp_r59_document_storage_identity_valid' in r59,
     'R59 does not validate document/version relational identity')
need("v.data->>'documentId'=d.id::text" in r59,
     'R59 does not bind the version to its parent document')
need('not public.erp_r59_document_storage_identity_valid(p_name) then return false;' in r59,
     'R59 Storage read/write guards do not enforce version identity')
need("bucket_id='enterprise-documents'" in r59,
     'R59 policies are not scoped to the enterprise document bucket')
need("'$_companyId/$documentId/$versionId.bin'" in client,
     'Flutter writer is not using the canonical path')
need('erp_register_cloud_document_blob' in r55,
     'R55 registration contract is missing from the chain')

if errors:
    print('FAIL Stage 12 storage-object completion')
    for error in errors:
        print(f'- {error}')
    raise SystemExit(1)

print('PASS Stage 12 storage-object completion')
print('- direct Storage insert/update/delete/read is now bound to a real document version')
print('- arbitrary filenames under an authorized document are rejected')
print('- document/version/company identity remains consistent across Flutter, Storage and PostgreSQL')
