from pathlib import Path

root = Path(__file__).resolve().parents[1]
migrations = root / "supabase" / "migrations"
dashboard = (root / "lib/features/dashboard/data/dashboard_repository.dart").read_text(
    encoding="utf-8"
)
defines = (root / "dart_defines.json").read_text(encoding="utf-8")
guarded_push = (root / "tool/guarded_supabase_db_push.py").read_text(encoding="utf-8")

expected_local_id = "quality_line_erp_local_dev"
expected_url = "http://127.0.0.1:54321"
rpc = "erp_r65_get_authoritative_dashboard_snapshot"
required = {
    "20260814053406_r65_authoritative_dashboard_snapshot.sql": [
        f"create or replace function public.{rpc}",
        "grant execute on function public.erp_r65_get_authoritative_dashboard_snapshot(uuid,date,date)",
        "notify pgrst,'reload schema'",
    ],
    "20260814053911_r65_1_dashboard_snapshot_runtime_correction.sql": [
        "r65_1_currency_validation_source_fragment_not_found",
        "r65_1_currency_join_source_fragment_not_found",
    ],
    "20260814054028_r65_2_dashboard_reservation_contract_correction.sql": [
        "r65_2_reservation_status_source_fragment_not_found",
    ],
    "20260814054136_r65_3_dashboard_field_projection_correction.sql": [
        "r65_3_field_projection_source_fragment_not_found",
        "totalSalesByCurrency",
        "cashBalanceByCurrency",
    ],
    "20260814055604_r65_4_dashboard_snapshot_volatility_correction.sql": [
        "alter function public.erp_r65_get_authoritative_dashboard_snapshot(uuid,date,date)",
        "volatile",
    ],
    "20260815150000_r72_dashboard_runtime_schema_guard.sql": [
        "to_regprocedure",
        "r72_dashboard_contract_missing",
        "notify pgrst,'reload schema'",
    ],
}

assert expected_url in defines, "runtime does not target Local Supabase"
assert ".supabase.co" not in defines, "active runtime still targets Hosted Supabase"
assert rpc in dashboard, "Dashboard repository does not call the authoritative R65 RPC"
assert "erp_r16_get_authorita" not in dashboard, "legacy R16 Dashboard RPC is still referenced"
assert "db\", \"push\"" in guarded_push or '"db", "push"' in guarded_push
assert "--dry-run" in guarded_push, "guarded database push must perform a dry-run"
assert "remote_only_versions" in guarded_push, "guarded database push must reject unknown remote history"

for filename, markers in required.items():
    path = migrations / filename
    assert path.is_file(), f"required migration is missing: {filename}"
    text = path.read_text(encoding="utf-8")
    for marker in markers:
        assert marker in text, f"{filename} is missing contract marker: {marker}"

versions = sorted(
    path.name.split("_", 1)[0]
    for path in migrations.glob("*.sql")
    if path.name[:14].isdigit()
)
assert "20260814053406" in versions
assert "20260815150000" in versions
assert versions.index("20260814053406") < versions.index("20260815150000")

print("PASS R72 authoritative Dashboard database deployment contract")
print(f"  - Local Supabase project: {expected_local_id}")
print(f"  - Local Supabase API: {expected_url}")
print(f"  - runtime RPC: {rpc}")
print("  - R65 + R65.1/.2/.3/.4 migration chain: present")
print("  - R72 remote schema postcondition + PostgREST reload: present")
print("  - guarded chronological Supabase db push: required")
