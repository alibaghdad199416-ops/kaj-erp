from pathlib import Path
import json,re,sys
ROOT=Path(__file__).resolve().parents[1]
def read(path): return (ROOT/path).read_text(encoding='utf-8')
checks={}
inv=read('lib/features/inventory/pages/inventory_page.dart')
inv_card=read('lib/features/inventory/widgets/inventory_card.dart')
cars=read('lib/features/inventory/cars/pages/cars_page.dart')
car_card=read('lib/features/inventory/cars/widgets/car_card.dart')
wh=read('lib/features/inventory/pages/warehouse_management_page.dart')
cust=read('lib/features/business_partners/customers/pages/customers_page.dart')
supp=read('lib/features/business_partners/suppliers/pages/suppliers_page.dart')
cust_card=read('lib/features/business_partners/customers/widgets/customer_card.dart')
supp_card=read('lib/features/business_partners/suppliers/widgets/supplier_card.dart')
hist=read('lib/features/inventory/asset_history/pages/asset_history_page.dart')
mov=read('lib/features/inventory/pages/inventory_movements_page.dart')
recycle=read('lib/features/settings/recycle_bin/pages/recycle_bin_page.dart')
opp=read('lib/features/customer_service/pages/customer_service_page.dart')
maint=read('lib/features/maintenance/data/maintenance_repository.dart')
maint_migration=read('supabase/migrations/20260809125507_r37_maintenance_labor_only_closure.sql')
cloud=read('lib/core/cloud/cloud_feature_command.dart')
sales=read('lib/features/sales/workflow/pages/sales_workflow_page.dart')
purchases=read('lib/features/purchases/pages/purchase_workflow_page.dart')
filterbar=read('lib/core/widgets/commercial_workflow_filter_bar.dart')
details=read('lib/features/sales/workflow/pages/order_details_dialog.dart')
migration=read('supabase/migrations/20260809124736_r37_full_functional_presentation_closure.sql')
pdfweb=read('lib/core/exporting/pdf_print_service_web.dart')
inv_compact=re.sub(r'\s+',' ',inv)
checks['product cards compact']=(('? 184 : ' in inv_compact and '? 192 : ' in inv_compact and ': 204' in inv_compact) or ('? 172 : ' in inv_compact and '? 180 : ' in inv_compact and ': 192' in inv_compact) or ('? 158 : ' in inv_compact and '? 166 : ' in inv_compact and ': 178' in inv_compact)) and 'width: 60' in inv_card
checks['car cards compact']=((('? 198' in cars and '? 206' in cars and ': 218' in cars) or ('? 186' in cars and '? 194' in cars and ': 206' in cars) or ('? 168' in cars and '? 176' in cars and ': 188' in cars)) and 'width: 64' in car_card)
checks['warehouse cards compact']=any(token in wh for token in ('mainAxisExtent: 150','mainAxisExtent: 142','mainAxisExtent: 138','mainAxisExtent: 124')) and 'const Spacer()' not in wh[wh.find('class _WarehouseCard'):wh.find('class WarehouseEditor') if 'class WarehouseEditor' in wh else len(wh)]
checks['partner cards compact']=(('mainAxisExtent: 164' in cust and 'mainAxisExtent: 172' in supp) or ('mainAxisExtent: 150' in cust and 'mainAxisExtent: 150' in supp) or ('mainAxisExtent: 142' in cust and 'mainAxisExtent: 142' in supp) or ('mainAxisExtent: 126' in cust and 'mainAxisExtent: 126' in supp))
checks['partner cards localized']="t('عميل تجاري', 'Customer')" in cust_card and "t('مورد نشط', 'Active supplier')" in supp_card
checks['product details/edit direct']='onView: () => _showProductDetails' in inv and 'onEdit: () => _editProduct' in inv and "label: AppText(context.l10n.isArabic ? 'تعديل' : 'Edit')" in inv
checks['product history English structured']="language: 'en'" in hist and 'Performed by' in hist and 'Unit cost' in hist and 'Total cost' in hist and 'Reference' in hist
checks['movement export English structured']="title: 'Inventory Movement Log'" in mov and "label: 'Performed by'" in mov and "language: 'en'" in mov
checks['recycle bin direct xlsx']='ExcelExportService().build(_report())' in recycle and 'BinaryDownloadService.save' in recycle and re.search(r"mimeType:\s*'application/vnd\.openxmlformats-officedocument\.spreadsheetml\.sheet'", recycle) is not None
checks['opportunity xlsx/pdf']='ExcelExportService().build(_opportunityExport(rows))' in opp and 'PdfExportService().save(_opportunityExport(rows))' in opp
checks['opportunity bidirectional reconciliation']='erp_r37_reconcile_opportunity_sales_links' in migration and "payload->>'saleId'" in migration and 'opportunity_id=r.record_id' in migration
checks['maintenance explicit advance']='erp_r37_advance_maintenance_workflow' in maint and 'erp_r37_advance_maintenance_workflow' in migration
checks['maintenance labor-only create']=any(x in maint for x in ('erp_r37_create_cloud_maintenance_order','erp_r39_create_cloud_maintenance_order','erp_r49_create_cloud_maintenance_order')) and 'maintenance_parts_required' not in maint_migration and "jsonb_array_length(v_parts)>0" in maint_migration
checks['cloud command R37']='erp_r37_cloud_command' in cloud and 'erp_r28_cloud_command' not in cloud and 'erp_r37_cloud_command' in migration
checks['sales/purchase localized actions']=re.search(r"_bi\(\s*'تصديق أمر البيع',\s*'Approve sales order',?\s*\)", sales) is not None and re.search(r"_bi\(\s*'تصديق أمر الشراء',\s*'Approve purchase order',?\s*\)", purchases) is not None
checks['filter chips localized']="context.l10n.isArabic ? 'مفوتر' : 'Invoiced'" in filterbar and "context.l10n.isArabic ? 'مسدد' : 'Paid'" in filterbar
checks['technical payload suppressed']='invoiceRawData' in details and 'recordMeta' in details and 'raw_data' in details
checks['web pdf direct browser download']='html.Blob' in pdfweb and 'AnchorElement' in pdfweb and '..download = safeFileName' in pdfweb and 'html.window.open(' not in pdfweb
checks['R37 migration schema reload']="notify pgrst,'reload schema'" in migration
pkg=json.loads(read('package.json'))
checks['default deploy R37']=('deploy_r37_production.ps1' in pkg['scripts'].get('deploy:production','') or re.search(r'deploy_r(?:3[89]|[4-9][0-9])_production\.ps1',pkg['scripts'].get('deploy:production',''))) and 'verify:r37' in pkg['scripts'].get('verify:workspace','')
for name,ok in checks.items(): print(('PASS' if ok else 'FAIL'),name)
if not all(checks.values()): sys.exit(1)
print(f'PASS R37 full functional/presentation closure — {len(checks)} gates')
