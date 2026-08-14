from pathlib import Path
import json,re,sys
ROOT=Path(__file__).resolve().parents[1]
checks={}
def read(p): return (ROOT/p).read_text(encoding='utf-8')
inv=read('lib/features/inventory/pages/inventory_page.dart')
car=read('lib/features/inventory/cars/pages/cars_page.dart')
wh=read('lib/features/inventory/pages/warehouse_management_page.dart')
cust=read('lib/features/business_partners/customers/pages/customers_page.dart')
supp=read('lib/features/business_partners/suppliers/pages/suppliers_page.dart')
hist=read('lib/features/inventory/asset_history/pages/asset_history_page.dart')
mov=read('lib/features/inventory/pages/inventory_movements_page.dart')
recycle=read('lib/features/settings/recycle_bin/pages/recycle_bin_page.dart')
opp=read('lib/features/customer_service/pages/customer_service_page.dart')
maint=read('lib/features/maintenance/data/maintenance_repository.dart')
cloud=read('lib/core/cloud/cloud_feature_command.dart')
pdfweb=read('lib/core/exporting/pdf_print_service_web.dart')
binaryweb=read('lib/core/exporting/binary_download_service_web.dart')
checks['product cards compact']=re.search(r'\?\s*(?:216|184|172|158)\s*:', inv) is not None
checks['car cards compact']='mainAxisExtent:' not in car and 'ListView.separated(' in car and 'final rowCount = (filteredCars.length + columns - 1) ~/ columns;' in car
checks['warehouse cards compact']=any(token in wh for token in ('mainAxisExtent: 176','mainAxisExtent: 150','mainAxisExtent: 142','mainAxisExtent: 138','mainAxisExtent: 124'))
checks['customer cards compact']=any(token in cust for token in ('mainAxisExtent: 176','mainAxisExtent: 164','mainAxisExtent: 150','mainAxisExtent: 142','mainAxisExtent: 126'))
checks['supplier cards compact']=any(token in supp for token in ('mainAxisExtent: 176','mainAxisExtent: 172','mainAxisExtent: 150','mainAxisExtent: 142','mainAxisExtent: 126'))
checks['product detail/edit bound']='onView: () => _showProductDetails' in inv and 'onEdit: () => _editProduct' in inv
checks['history English xlsx/pdf']='language: \'en\'' in hist and 'ExcelExportService().save(document)' in hist and 'PdfExportService().save(document)' in hist and 'Performed by' in hist and 'Unit cost' in hist
checks['movement xlsx/pdf']='ExcelExportService().save(exportDocument)' in mov and 'PdfExportService().save(exportDocument)' in mov and ('Performed by' in mov or "label: arabic ? 'المستخدم' : 'User'" in mov)
checks['recycle bin localized xlsx']="language: exportArabic ? 'ar' : 'en'" in recycle and ('ExcelExportService().save(_report())' in recycle or 'ExcelExportService().build(_report())' in recycle)
checks['opportunity xlsx/pdf']=('ExcelExportService().save(_opportunityExport(rows))' in opp or 'ExcelExportService().build(_opportunityExport(rows))' in opp) and 'PdfExportService().save(_opportunityExport(rows))' in opp
checks['maintenance R35 create or newer']=any(x in maint for x in ('erp_r35_create_cloud_maintenance_order','erp_r37_create_cloud_maintenance_order','erp_r39_create_cloud_maintenance_order','erp_r49_create_cloud_maintenance_order','erp_r56_create_cloud_maintenance_order'))
checks['cloud command R35']=('erp_r35_cloud_command' in cloud or 'erp_r37_cloud_command' in cloud) and 'erp_r28_cloud_command' not in cloud
checks['web pdf direct download']='browser_download.saveBinary' in pdfweb and 'html.Blob' in binaryweb and 'AnchorElement' in binaryweb and '..download = fileName' in binaryweb and 'html.window.open(' not in pdfweb
for k,v in checks.items(): print(('PASS' if v else 'FAIL'),k)
if not all(checks.values()): sys.exit(1)
print(f'PASS R36 UI/export acceptance — {len(checks)} gates')
