from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
config = (root / "lib/core/cloud/supabase_config.dart").read_text(encoding="utf-8")
bootstrap = (root / "lib/core/cloud/cloud_bootstrap.dart").read_text(encoding="utf-8")
tenant = (root / "lib/core/cloud/cloud_tenant_context.dart").read_text(encoding="utf-8")
defines = (root / "dart_defines.json").read_text(encoding="utf-8")
package = json.loads((root / "package.json").read_text(encoding="utf-8"))

expected_local_id = "quality_line_erp_local_dev"
expected_url = "http://127.0.0.1:54321"

for source_name, source in {
    "supabase_config.dart": config,
    "dart_defines.json": defines,
}.items():
    assert ".supabase.co" not in source, f"{source_name} still permits Hosted Supabase"
    assert "havlqebmnjdcwmpaaqew" not in source, f"{source_name} still embeds the retired Hosted project"

assert expected_url in config
assert expected_url in defines
assert expected_local_id in config
assert "browserStorageNamespace" in config
assert "authPersistSessionKey" in config
assert "projectRefFor" in config
assert "storageNamespaceFor" in config
assert "validateRuntime" in config
assert "isConfigured => validateRuntime() == null" in config
assert "_isLoopback(uri.host)" in config
assert "Local Supabase فقط" in config
assert "expectedProductionProjectRef" not in config

# Auth must never fall back to an ambiguous/default browser key. Bootstrap and
# tenant cache remain backend-scoped even though the only allowed backend is local.
assert "SharedPreferencesLocalStorage" in bootstrap
assert "SupabaseConfig.authPersistSessionKey" in bootstrap
assert "if (!isLoopback)" not in bootstrap
assert "return const FlutterAuthClientOptions();" not in bootstrap
assert "Supabase bootstrap target: ${SupabaseConfig.projectRef}" in bootstrap
assert "SupabaseConfig.validateRuntime()" in bootstrap
assert "SupabaseConfig.validate() == null" not in bootstrap
assert "Supabase runtime configuration rejected" in bootstrap

assert "SupabaseConfig.browserStorageNamespace" in tenant
assert "_scopedKey" in tenant
assert "_removeLegacyUnscopedKeys" in tenant
assert "preferences.remove(_companyUuidKey)" in tenant
assert "preferences.remove(_scopedKey(_companyUuidKey))" in tenant
assert "preferences.setString(_scopedKey(_companyKey)" in tenant

scripts = package.get("scripts", {})
assert scripts.get("run:web") == scripts.get("run:web:local")
assert "run_current_web.ps1" in scripts.get("run:web", "")
assert "run_production_web.ps1" not in scripts.get("run:web", "")

print("PASS R71 Local Supabase runtime/auth/tenant isolation")
print(f"  - required local project: {expected_local_id}")
print(f"  - required API: {expected_url}")
print("  - Hosted Supabase is rejected by active runtime configuration")
print("  - auth storage remains backend-scoped")
print("  - tenant cache remains backend-scoped")
print("  - legacy unscoped tenant cache is discarded")
