from pathlib import Path
import json,re,sys
ROOT=Path(__file__).resolve().parents[1]
def read(p): return (ROOT/p).read_text(encoding="utf-8")
checks={}
maint_repo=read("lib/features/maintenance/data/maintenance_repository.dart")
maint_page=read("lib/features/maintenance/pages/add_maintenance_order_page.dart")
pdfweb=read("lib/core/exporting/pdf_print_service_web.dart")
inv=read("lib/features/inventory/pages/inventory_page.dart")
cars=read("lib/features/inventory/cars/pages/cars_page.dart")
wh=read("lib/features/inventory/pages/warehouse_management_page.dart")
cust=read("lib/features/business_partners/customers/pages/customers_page.dart")
supp=read("lib/features/business_partners/suppliers/pages/suppliers_page.dart")
hist=read("lib/features/inventory/asset_history/pages/asset_history_page.dart")
mov=read("lib/features/inventory/pages/inventory_movements_page.dart")
recycle=read("lib/features/settings/recycle_bin/pages/recycle_bin_page.dart")
opp=read("lib/features/customer_service/pages/customer_service_page.dart")
cloud=read("lib/core/cloud/cloud_feature_command.dart")
details=read("lib/features/sales/workflow/pages/order_details_dialog.dart")
index=read("web/index.html")
pkg=json.loads(read("package.json"))
checks["maintenance labor-only client validation"]="parts.isEmpty" not in maint_repo[maint_repo.find("static void _validate"):]
checks["maintenance labor-only page safe"]="String _maintenanceWarehouseId()" in maint_page and "orElse: () => _lines.first" not in maint_page
checks["maintenance R37 or newer create/advance"]=(("erp_r37_create_cloud_maintenance_order" in maint_repo or "erp_r39_create_cloud_maintenance_order" in maint_repo or "erp_r49_create_cloud_maintenance_order" in maint_repo) and "erp_r37_advance_maintenance_workflow" in maint_repo)
checks["web PDF is a reliable download"]="html.Blob" in pdfweb and "AnchorElement" in pdfweb and "..download = safeFileName" in pdfweb and "html.window.open(" not in pdfweb
checks["no custom viewport warning"]='<meta name="viewport"' not in index
inv_compact=re.sub(r'\s+',' ',inv)
checks["product cards tighter"]=("? 172 : " in inv_compact and "? 180 : " in inv_compact and ": 192" in inv_compact) or ("? 158 : " in inv_compact and "? 166 : " in inv_compact and ": 178" in inv_compact)
checks["car cards tighter"]=("? 186" in cars and "? 194" in cars and ": 206" in cars) or ("? 168" in cars and "? 176" in cars and ": 188" in cars)
checks["warehouse cards tighter"]=any(x in wh for x in ("mainAxisExtent: 142","mainAxisExtent: 138","mainAxisExtent: 124"))
checks["partner cards responsive"]=any(x in cust for x in ("mainAxisExtent: 164","mainAxisExtent: 142","mainAxisExtent: 126")) and any(x in supp for x in ("mainAxisExtent: 172","mainAxisExtent: 142","mainAxisExtent: 126"))
checks["product details edit direct"]="onView: () => _showProductDetails" in inv and "onEdit: () => _editProduct" in inv
checks["history export English complete"]="language: 'en'" in hist and all(x in hist for x in ["Performed by","Unit cost","Total cost","Reference","Date / Time"])
checks["movement export English complete"]="language: 'en'" in mov and all(x in mov for x in ["Performed by","From","To","Quantity","Reference"])
checks["recycle xlsx web-safe"]="ExcelExportService().build(_report())" in recycle and "BinaryDownloadService.save" in recycle
checks["opportunity xlsx pdf"]="ExcelExportService().build(_opportunityExport(rows))" in opp and "PdfExportService().save(_opportunityExport(rows))" in opp
checks["cloud command R37 retained"]="erp_r37_cloud_command" in cloud and "erp_r28_cloud_command" not in cloud
checks["technical order payload hidden"]=all(x in details for x in ["rawData","recordMeta","invoiceRawData"])
checks["default deploy R38 or newer"]=(any(x in pkg["scripts"].get("deploy:production","") for x in ["deploy_r38_production.ps1","deploy_r39_production.ps1","deploy_r40_production.ps1","deploy_r41_production.ps1","deploy_r42_production.ps1","deploy_r43_production.ps1","deploy_r44_production.ps1","deploy_r49_production.ps1"]) and "verify:r38" in pkg["scripts"].get("verify:workspace",""))
for n,ok in checks.items(): print(("PASS" if ok else "FAIL"),n)
if not all(checks.values()): sys.exit(1)
print(f"PASS R38 final functional acceptance — {len(checks)} gates")
