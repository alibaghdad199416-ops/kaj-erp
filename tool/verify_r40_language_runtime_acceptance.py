from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def t(p): return (ROOT/p).read_text(encoding="utf-8",errors="ignore")
checks={}
checks["R39 retained"]="verify:r39" in t("package.json")
checks["movement log English runtime title"]="Inventory movement log" in t("lib/features/inventory/pages/inventory_movements_page.dart")
checks["movement details bilingual"]="Movement details" in t("lib/features/inventory/pages/inventory_movements_page.dart") and "Reference and notes" in t("lib/features/inventory/pages/inventory_movements_page.dart")
checks["movement export English structured"]="language: 'en'" in t("lib/features/inventory/pages/inventory_movements_page.dart") and "Performed by" in t("lib/features/inventory/pages/inventory_movements_page.dart")
checks["product delete dialog bilingual"]="Delete product" in t("lib/features/inventory/pages/inventory_page.dart") and "Current balance" in t("lib/features/inventory/pages/inventory_page.dart")
checks["R39 maintenance create/edit canonical"]=("erp_r39_create_cloud_maintenance_order" in t("lib/features/maintenance/data/maintenance_repository.dart") or "erp_r49_create_cloud_maintenance_order" in t("lib/features/maintenance/data/maintenance_repository.dart")) and ("erp_r39_update_cloud_maintenance_draft" in t("lib/features/maintenance/data/maintenance_repository.dart") or "erp_r49_update_cloud_maintenance_draft" in t("lib/features/maintenance/data/maintenance_repository.dart"))
checks["maintenance labor-only client allowed"]="parts.isEmpty" not in t("lib/features/maintenance/data/maintenance_repository.dart")
pdfweb=t("lib/core/exporting/pdf_print_service_web.dart")
checks["web PDF print service"]="frameWindow.print()" in pdfweb or ("html.Blob" in pdfweb and "html.window.open(url, '_blank')" in pdfweb)
checks["no legacy cloud command"]="erp_r28_cloud_command" not in t("lib/core/cloud/cloud_feature_command.dart")
checks["R40 metadata"]=any(x in t("web/version.json") for x in ("r40-language-runtime-acceptance","r41-export-language-canonical-closure","r42-production-cashbox-guard-closure","r43-performance-functional-closure","r47-production-runtime-dependency-closure","r49-"))
checks["R40 deploy"]=any(x in t("package.json") for x in ("deploy_r40_production.ps1","deploy_r41_production.ps1","deploy_r42_production.ps1","deploy_r43_production.ps1"))
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(("PASS" if v else "FAIL"),k)
if failed: raise SystemExit("R40 verification failed: "+", ".join(failed))
print(f"PASS R40 language/runtime acceptance — {len(checks)} gates")
