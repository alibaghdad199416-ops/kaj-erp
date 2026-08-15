from pathlib import Path

root = Path(__file__).resolve().parents[1]
config = (root / "lib/core/cloud/supabase_config.dart").read_text(encoding="utf-8")
bootstrap = (root / "lib/core/cloud/cloud_bootstrap.dart").read_text(encoding="utf-8")
tenant = (root / "lib/core/cloud/cloud_tenant_context.dart").read_text(encoding="utf-8")
defines = (root / "dart_defines.json").read_text(encoding="utf-8")
production = (root / "tool/configure_production.ps1").read_text(encoding="utf-8")
deploy = (root / "tool/deploy_production.ps1").read_text(encoding="utf-8")

expected = "havlqebmnjdcwmpaaqew"
expected_url = f"https://{expected}.supabase.co"

for source_name, source in {
    "supabase_config.dart": config,
    "dart_defines.json": defines,
    "configure_production.ps1": production,
    "deploy_production.ps1": deploy,
}.items():
    assert expected in source, f"{source_name} does not target {expected}"

assert expected_url in config
assert expected_url in defines
assert "expectedProductionProjectRef" in config
assert "browserStorageNamespace" in config
assert "authPersistSessionKey" in config
assert "projectRefFor" in config
assert "storageNamespaceFor" in config
assert "validateRuntime" in config
assert "projectRef != expectedProductionProjectRef" in config
assert "isConfigured => validateRuntime() == null" in config

# Hosted auth must no longer fall back to Supabase's generic/default browser key,
# and bootstrap must reject every hosted project except the approved one.
assert "SharedPreferencesLocalStorage" in bootstrap
assert "SupabaseConfig.authPersistSessionKey" in bootstrap
assert "if (!isLoopback)" not in bootstrap
assert "return const FlutterAuthClientOptions();" not in bootstrap
assert "Supabase bootstrap target: ${SupabaseConfig.projectRef}" in bootstrap
assert "SupabaseConfig.validateRuntime()" in bootstrap
assert "SupabaseConfig.validate() == null" not in bootstrap
assert "Supabase runtime configuration rejected" in bootstrap

# Tenant/company cache must be project-scoped, and legacy ambiguous keys must be
# removed rather than silently migrated into the currently selected backend.
assert "SupabaseConfig.browserStorageNamespace" in tenant
assert "_scopedKey" in tenant
assert "_removeLegacyUnscopedKeys" in tenant
assert "preferences.remove(_companyUuidKey)" in tenant
assert "preferences.remove(_scopedKey(_companyUuidKey))" in tenant
assert "preferences.setString(_scopedKey(_companyKey)" in tenant

print("PASS R71 Supabase runtime/auth/tenant project isolation")
print(f"  - required project: {expected}")
print("  - unexpected hosted Supabase projects fail closed")
print("  - hosted auth storage is project-scoped")
print("  - tenant cache is project-scoped")
print("  - legacy unscoped tenant cache is discarded")
