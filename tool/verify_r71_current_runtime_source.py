from pathlib import Path
import json

root = Path(__file__).resolve().parents[1]
dashboard = (root / "lib/features/dashboard/data/dashboard_repository.dart").read_text(
    encoding="utf-8"
)
local_runtime = json.loads((root / "dart_defines.json").read_text(encoding="utf-8"))
production_runtime = json.loads(
    (root / "dart_defines.production.json").read_text(encoding="utf-8")
)
config = (root / "lib/core/cloud/supabase_config.dart").read_text(encoding="utf-8")

expected_local_url = "http://127.0.0.1:54321"
expected_production_ref = "havlqebmnjdcwmpaaqew"
expected_production_url = f"https://{expected_production_ref}.supabase.co"
expected_rpc = "erp_r65_get_authoritative_dashboard_snapshot"
legacy_rpc_prefix = "erp_r16_get_authorita"

assert expected_rpc in dashboard, (
    "stale dashboard source: current runtime must call " + expected_rpc
)
assert legacy_rpc_prefix not in dashboard, (
    "stale R16 dashboard RPC is still present in the current source"
)
assert local_runtime.get("SUPABASE_URL") == expected_local_url, (
    "dart_defines.json must remain the Local Supabase test baseline"
)
assert production_runtime.get("SUPABASE_URL") == expected_production_url, (
    "production runtime does not target the approved Hosted Supabase project"
)
assert str(production_runtime.get("SUPABASE_PUBLISHABLE_KEY") or "").startswith(
    "sb_publishable_"
)
assert expected_production_ref in config
assert "expectedProductionUrl" in config
assert "validateRuntime" in config
assert "isHostedProductionTarget" in config
assert "isLocalTarget" in config

print("PASS R71 current runtime source")
print(f"  - production Supabase: {expected_production_url}")
print(f"  - Local Supabase test baseline: {expected_local_url}")
print(f"  - dashboard RPC: {expected_rpc}")
print("  - legacy R16 dashboard RPC: absent")
