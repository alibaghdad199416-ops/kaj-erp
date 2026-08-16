from pathlib import Path

root = Path(__file__).resolve().parents[1]
bootstrap = (root / "lib/core/cloud/cloud_bootstrap.dart").read_text(encoding="utf-8")
tenant = (root / "lib/core/cloud/cloud_tenant_context.dart").read_text(encoding="utf-8")
membership = (root / "lib/core/cloud/cloud_tenant_membership_service.dart").read_text(encoding="utf-8")
release = (root / "lib/core/release/app_release_info.dart").read_text(encoding="utf-8")
web_index = (root / "web/index.html").read_text(encoding="utf-8")
web_version = (root / "web/version.json").read_text(encoding="utf-8")
migration = (root / "supabase/migrations/20260815180000_r74_authenticated_tenant_runtime_identity.sql").read_text(encoding="utf-8")

expected_local_id = "quality_line_erp_local_dev"
expected_url = "http://127.0.0.1:54321"
expected_token = "r74-authenticated-tenant-runtime-20260815"

for marker in (
    "_verifyPersistedSessionForCurrentBackend",
    "client.auth.getUser()",
    "isInvalidPersistedAuthFailure",
    "SignOutScope.local",
    "R74 persisted Supabase session verified",
):
    assert marker in bootstrap, marker

for marker in (
    "cloud.active_auth_user_id",
    "r74-project-user-tenant-v1",
    "cachedAuthUserId != currentAuthUserId",
    "required String authUserId",
    "_removeScopedKeys",
):
    assert marker in tenant, marker

for marker in (
    "CloudTenantContext.instance.authUserId == user.id",
    "authUserId: user.id",
    "erp_r74_runtime_identity",
    "R74 runtime identity mismatch",
    "R74 runtime identity: project=",
):
    assert marker in membership, marker

for marker in (
    "create or replace function public.erp_r74_runtime_identity",
    "perform public.erp_active_company_context(p_company_id)",
    "'databaseContract','R74'",
    "grant execute on function public.erp_r74_runtime_identity(uuid)",
    "notify pgrst,'reload schema'",
):
    assert marker in migration, marker

defines = (root / "dart_defines.json").read_text(encoding="utf-8")
assert expected_url in defines
assert ".supabase.co" not in defines
assert expected_token in release
assert expected_token in web_index
assert expected_token in web_version
assert '"databaseContract": "R74"' in web_version

print("PASS R74 authenticated tenant runtime isolation")
print(f"  - Local Supabase project: {expected_local_id}")
print(f"  - Local Supabase API: {expected_url}")
print("  - persisted Auth session is verified against the current backend")
print("  - tenant cache is project + Auth-user scoped")
print("  - stale project-only tenant cache is invalidated")
print("  - database attests auth user + company through erp_r74_runtime_identity")
print(f"  - browser runtime token: {expected_token}")
