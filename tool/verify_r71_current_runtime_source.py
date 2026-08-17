from pathlib import Path

root = Path(__file__).resolve().parents[1]
dashboard = (root / "lib/features/dashboard/data/dashboard_repository.dart").read_text(
    encoding="utf-8"
)
defines = (root / "dart_defines.json").read_text(encoding="utf-8")
config = (root / "lib/core/cloud/supabase_config.dart").read_text(encoding="utf-8")

expected_local_id = "quality_line_erp_local_dev"
expected_url = "http://127.0.0.1:54321"
expected_rpc = "erp_r65_get_authoritative_dashboard_snapshot"
legacy_rpc_prefix = "erp_r16_get_authorita"

assert expected_rpc in dashboard, (
    "stale dashboard source: current runtime must call " + expected_rpc
)
assert legacy_rpc_prefix not in dashboard, (
    "stale R16 dashboard RPC is still present in the local source"
)
assert expected_url in defines, "dart_defines.json does not target Local Supabase"
assert expected_url in config, "Supabase runtime config does not default to Local Supabase"
assert expected_local_id in config, "Supabase runtime config is missing the local project identity"
assert ".supabase.co" not in defines, "active dart_defines.json still targets Hosted Supabase"
assert ".supabase.co" not in config, "Supabase runtime config still permits Hosted Supabase"
assert "validateRuntime" in config, "fail-closed Supabase runtime validation is missing"

print("PASS R71 current runtime source")
print(f"  - Local Supabase project: {expected_local_id}")
print(f"  - Local Supabase API: {expected_url}")
print(f"  - dashboard RPC: {expected_rpc}")
print("  - legacy R16 dashboard RPC: absent")
