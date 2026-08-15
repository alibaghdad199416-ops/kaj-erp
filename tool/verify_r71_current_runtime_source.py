from pathlib import Path

root = Path(__file__).resolve().parents[1]
dashboard = (root / "lib/features/dashboard/data/dashboard_repository.dart").read_text(
    encoding="utf-8"
)
defines = (root / "dart_defines.json").read_text(encoding="utf-8")
config = (root / "lib/core/cloud/supabase_config.dart").read_text(encoding="utf-8")

expected_ref = "havlqebmnjdcwmpaaqew"
expected_rpc = "erp_r65_get_authoritative_dashboard_snapshot"
legacy_rpc_prefix = "erp_r16_get_authorita"

assert expected_rpc in dashboard, (
    "stale dashboard source: current runtime must call " + expected_rpc
)
assert legacy_rpc_prefix not in dashboard, (
    "stale R16 dashboard RPC is still present in the local source"
)
assert expected_ref in defines, "dart_defines.json targets an unexpected Supabase project"
assert expected_ref in config, "Supabase runtime config targets an unexpected project"
assert "validateRuntime" in config, "fail-closed Supabase runtime validation is missing"

print("PASS R71 current runtime source")
print(f"  - Supabase project: {expected_ref}")
print(f"  - dashboard RPC: {expected_rpc}")
print("  - legacy R16 dashboard RPC: absent")
