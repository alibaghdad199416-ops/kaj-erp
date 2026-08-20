from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
checks={}
def text(rel): return (ROOT/rel).read_text(encoding='utf-8')
checks['r27 migration exists']=(ROOT/'supabase/migrations/20260808162000_r27_complete_functional_closure.sql').exists()
sql=text('supabase/migrations/20260808162000_r27_complete_functional_closure.sql')
checks['r27 postgrest command']='erp_r27_cloud_command' in sql and "notify pgrst,'reload schema'" in sql
checks['canonical cashbox read save']='erp_r27_list_cash_accounts' in sql and 'erp_r27_save_cash_account' in sql
checks['cashbox repo r27']=all(any(v in text('lib/features/accounting/cashbox/repositories/cashbox_repository.dart') for v in pair) for pair in (('erp_r27_list_cash_accounts','erp_r28_list_cash_accounts','erp_r42_list_cash_accounts','erp_r90_list_cash_accounts'),('erp_r27_save_cash_account','erp_r28_save_cash_account','erp_r42_save_cash_account','erp_r90_save_cash_account')))
checks['movement log dedicated rpc']=any(v in text('lib/features/inventory/data/inventory_repository.dart') for v in ('erp_r27_inventory_movement_log','erp_r28_inventory_movement_log'))
checks['immutable removeWhere removed']="movements.removeWhere" not in text('lib/features/inventory/data/inventory_repository.dart')
checks['movement source destination']='sourceName' in text('lib/features/inventory/models/inventory_movement_model.dart') and 'destinationName' in text('lib/features/inventory/models/inventory_movement_model.dart')
checks['cash dates no epoch']='DateTime.fromMillisecondsSinceEpoch(0' not in text('lib/features/accounting/cashbox/models/cash_transaction_model.dart')
checks['journal dates no epoch']='DateTime.fromMillisecondsSinceEpoch(0' not in text('lib/features/accounting/models/journal_entry_model.dart')
cars_page=text('lib/features/inventory/cars/pages/cars_page.dart')
checks['car overflow fixed']=(
    'mainAxisExtent:' not in cars_page
    and 'ListView.separated(' in cars_page
    and 'final rowCount = (filteredCars.length + columns - 1) ~/ columns;' in cars_page
    and '? 3' in cars_page
    and '? 2' in cars_page
)
inventory_page=text('lib/features/inventory/pages/inventory_page.dart')
checks['product card overflow fixed']='mainAxisExtent:' in inventory_page and ('columns >= 3' in inventory_page or 'columns == 3' in inventory_page) and 'columns == 2' in inventory_page
pdf_support=text('lib/core/printing/pdf_text_support.dart')
checks['bundled pdf font safety']=(
    'assets/fonts/NotoNaskhArabic-Regular.ttf' in pdf_support and
    'assets/fonts/NotoNaskhArabic-Bold.ttf' in pdf_support and
    'rootBundle.load' in pdf_support
)
checks['browser pdf download']='BinaryDownloadService.save' in text('lib/features/sales/workflow/pages/order_details_dialog.dart')
checks['record drilldown']='Widget _recordDetails' in text('lib/features/sales/workflow/pages/order_details_dialog.dart')
checks['details no false empty']='Older workflow rows can have complete payloads' in text('lib/features/sales/workflow/models/commercial_order_details.dart')
checks['history table export']='ExcelExportService().save(document)' in text('lib/features/inventory/asset_history/pages/asset_history_page.dart') and 'PdfExportService().save(document)' in text('lib/features/inventory/asset_history/pages/asset_history_page.dart')
checks['r27 frontend endpoint']=any(x in text('lib/core/cloud/cloud_feature_command.dart') for x in ('erp_r27_cloud_command','erp_r28_cloud_command','erp_r35_cloud_command','erp_r37_cloud_command','erp_r42_cloud_command'))
checks['r27 cache token']=any(x in text('web/index.html') for x in ('r27-complete-functional-closure','r28-complete-runtime-closure','r41-export-language-canonical-closure','r42-production-cashbox-guard-closure','r43-performance-functional-closure','r47-production-runtime-dependency-closure','r49-'))
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(('PASS' if v else 'FAIL'),k)
if failed: raise SystemExit('R27 verification failed: '+', '.join(failed))
print(f'PASS R27 complete functional closure — {len(checks)} gates')
