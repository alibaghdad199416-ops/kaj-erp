from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
config = (root / "lib/core/cloud/supabase_config.dart").read_text(encoding="utf-8")
bootstrap = (root / "lib/core/cloud/cloud_bootstrap.dart").read_text(encoding="utf-8")
tenant = (root / "lib/core/cloud/cloud_tenant_context.dart").read_text(encoding="utf-8")
local_defines = (root / "dart_defines.json").read_text(encoding="utf-8")
production_defines = (root / "dart_defines.production.json").read_text(encoding="utf-8")
package = json.loads((root / "package.json").read_text(encoding="utf-8"))

expected_local_id = "quality_line_erp_local_dev"
expected_local_url = "http://127.0.0.1:54321"
expected_production_ref = "havlqebmnjdcwmpaaqew"
expected_production_url = f"https://{expected_production_ref}.supabase.co"

local_runtime = json.loads(local_defines)
production_runtime = json.loads(production_defines)
assert local_runtime.get("SUPABASE_URL") == expected_local_url
assert production_runtime.get("SUPABASE_URL") == expected_production_url
assert str(production_runtime.get("SUPABASE_PUBLISHABLE_KEY") or "").startswith("sb_publishable_")
assert "/rest/v1" not in str(production_runtime.get("SUPABASE_URL") or "")

for marker in (
    expected_production_ref,
    "expectedProductionUrl",
    expected_local_id,
    "browserStorageNamespace",
    "authPersistSessionKey",
    "projectRefFor",
    "storageNamespaceFor",
    "validateRuntime",
    "isHostedProductionTarget",
    "isLocalTarget",
    "SUPABASE_ALLOW_LOCAL_DEV",
):
    assert marker in config, marker
assert "isConfigured => validateRuntime() == null" in config

# Auth must never fall back to an ambiguous/default browser key. Bootstrap and
# tenant cache remain backend-scoped across both production and local runtimes.
assert "SharedPreferencesLocalStorage" in bootstrap
assert "SupabaseConfig.authPersistSessionKey" in bootstrap
assert "return const FlutterAuthClientOptions();" not in bootstrap
assert "Supabase bootstrap target: ${SupabaseConfig.projectRef}" in bootstrap
assert "SupabaseConfig.validateRuntime()" in bootstrap
assert "Supabase runtime configuration rejected" in bootstrap

assert "SupabaseConfig.browserStorageNamespace" in tenant
assert "_scopedKey" in tenant
assert "_removeLegacyUnscopedKeys" in tenant
assert "preferences.remove(_companyUuidKey)" in tenant
assert "preferences.remove(_scopedKey(_companyUuidKey))" in tenant
assert "preferences.setString(_scopedKey(_companyKey)" in tenant

scripts = package.get("scripts", {})
assert "run_current_web.ps1" in scripts.get("run:web:local", "")
assert "run_production_web.ps1" in scripts.get("run:web:production", "")

print("PASS R71 Supabase runtime/auth/tenant isolation")
print(f"  - production project: {expected_production_ref}")
print(f"  - production API: {expected_production_url}")
print(f"  - Local Supabase development API: {expected_local_url}")
print("  - auth storage is backend-scoped")
print("  - tenant cache is backend-scoped")
print("  - legacy unscoped tenant cache is discarded")
