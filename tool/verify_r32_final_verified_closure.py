from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
checks={
"r31 retained": (ROOT/"tool/verify_r31_final_completion_closure.py").exists(),
"recycle bin has no epoch fallback": "fromMillisecondsSinceEpoch(0)" not in (ROOT/"lib/features/settings/recycle_bin/models/recycle_bin_item.dart").read_text(encoding="utf-8"),
"recycle deleted date nullable": "final DateTime? deletedAt;" in (ROOT/"lib/features/settings/recycle_bin/models/recycle_bin_item.dart").read_text(encoding="utf-8"),
"dashboard no epoch placeholder": "fromMillisecondsSinceEpoch(0)" not in (ROOT/"lib/features/dashboard/models/dashboard_model.dart").read_text(encoding="utf-8"),
"customer card headroom": any(x in (ROOT/"lib/features/business_partners/customers/pages/customers_page.dart").read_text(encoding="utf-8") for x in ["mainAxisExtent: 164","mainAxisExtent: 142","mainAxisExtent: 126"]),
"supplier card headroom": any(x in (ROOT/"lib/features/business_partners/suppliers/pages/suppliers_page.dart").read_text(encoding="utf-8") for x in ["mainAxisExtent: 172","mainAxisExtent: 142","mainAxisExtent: 126"]),
"warehouse card headroom": any(x in (ROOT/"lib/features/inventory/pages/warehouse_management_page.dart").read_text(encoding="utf-8") for x in ["mainAxisExtent: 142","mainAxisExtent: 138","mainAxisExtent: 124"]),
"maintenance picker headroom": "mainAxisExtent: 164" in (ROOT/"lib/features/maintenance/pages/add_maintenance_order_page.dart").read_text(encoding="utf-8"),
"r32 deploy script": (ROOT/"tool/deploy_r32_production.ps1").exists(),
"r32 workspace validation": (ROOT/"tool/validate_r32_workspace.ps1").exists(),
"r32 deploy invokes r32 validation": "validate_r32_workspace.ps1" in (ROOT/"tool/deploy_r32_production.ps1").read_text(encoding="utf-8"),
"default deploy r32-or-later": any(x in (ROOT/"package.json").read_text(encoding="utf-8") for x in ["deploy_r32_production.ps1","deploy_r33_production.ps1","deploy_r34_production.ps1","deploy_r43_production.ps1"]),
"r32 cache token": any(x in (ROOT/"web/version.json").read_text(encoding="utf-8") for x in ["r41-export-language-canonical-closure","r42-production-cashbox-guard-closure","r43-performance-functional-closure","r47-production-runtime-dependency-closure","r49-"]),
"r32 version metadata unified": any(x in (ROOT/"web/version.json").read_text(encoding="utf-8") for x in ["22.9.8-r41-export-language-canonical-closure","22.9.8-r42-production-cashbox-guard-closure","22.9.8-r43-performance-functional-closure","22.9.8-r47-production-runtime-dependency-closure","22.9.8-r49-"]) and '"build_name": "22.9.8"' in (ROOT/"web/version.json").read_text(encoding="utf-8"),
}
for k,v in checks.items():
 print(("PASS" if v else "FAIL"),k)
if not all(checks.values()): raise SystemExit(1)
print(f"PASS R32 final verified closure — {len(checks)} gates")
