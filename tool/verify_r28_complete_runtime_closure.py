from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
checks={}
def text(rel): return (ROOT/rel).read_text(encoding='utf-8')

def need(name, condition): checks[name]=bool(condition)

main_sql=text('supabase/migrations/20260808170000_r28_complete_runtime_closure.sql')
cmd_sql=text('supabase/migrations/20260808173000_r28_cloud_command_contract.sql')
repo=text('lib/features/accounting/cashbox/repositories/cashbox_repository.dart')
account_model=text('lib/features/accounting/models/account_model.dart')
cash_model=text('lib/features/accounting/cashbox/models/cash_account_model.dart')
movement_repo=text('lib/features/inventory/data/inventory_repository.dart')
movement_page=text('lib/features/inventory/pages/inventory_movements_page.dart')
details_repo=text('lib/features/sales/workflow/repositories/commercial_order_details_repository.dart')
cloud=text('lib/core/cloud/cloud_feature_command.dart')

need('r28 migrations exist', (ROOT/'supabase/migrations/20260808170000_r28_complete_runtime_closure.sql').exists() and (ROOT/'supabase/migrations/20260808173000_r28_cloud_command_contract.sql').exists())
need('canonical cashbox list/save', 'erp_r28_list_cash_accounts' in main_sql and 'erp_r28_save_cash_account' in main_sql)
need('cashbox asset currency validation', "v_ledger_type<>'asset'" in main_sql and "v_ledger_currency not in (v_currency,'MULTI')" in main_sql)
need('cashbox duplicate ledger rejected', 'cashbox_ledger_account_already_bound' in main_sql)
need('cashbox row timestamp authoritative', "'_cloudUpdatedAt', ca.updated_at" in main_sql and '_cloudUpdatedAt' in cash_model)
need('cashbox repo r28-or-later endpoints', (
    ('erp_r28_list_cash_accounts' in repo and 'erp_r28_save_cash_account' in repo) or
    ('erp_r42_list_cash_accounts' in repo and 'erp_r42_save_cash_account' in repo) or
    ('erp_r90_list_cash_accounts' in repo and 'erp_r90_save_cash_account' in repo)
) and 'erp_r28_list_cash_transactions' in repo)
need('cash transaction real row dates', 'erp_r28_list_cash_transactions' in main_sql and "'createdAt',ct.created_at" in main_sql and 'transactionDate' in main_sql)
display_formatter=text('lib/core/utils/erp_display_formatter.dart')
need('account codes are text identifiers',
     'ErpDisplayFormatter.accountCode(raw)' in account_model and
     'BigInt.parse' in display_formatter and
     'double.tryParse' not in display_formatter)
need('dedicated movement rpc', 'erp_r28_inventory_movement_log' in main_sql and 'erp_r28_inventory_movement_log' in movement_repo)
need('movement table export pdf excel', 'ExcelExportService' in movement_page and 'PdfExportService' in movement_page and 'sourceName' in movement_page and 'destinationName' in movement_page)
need('commercial details enriched rpc', 'erp_r28_get_commercial_order_complete_details' in main_sql and 'approvedBy' in main_sql and 'sourceName' in main_sql and 'destinationName' in main_sql)
need('frontend commercial details r28-or-later',
     'erp_r28_get_commercial_order_complete_details' in details_repo or
     'erp_r62_get_commercial_order_snapshot' in details_repo or
     'erp_r89_get_commercial_order_snapshot' in details_repo)
pdf_web=text('lib/core/exporting/pdf_print_service_web.dart')
binary_web=text('lib/core/exporting/binary_download_service_web.dart')
download_lifecycle=text('lib/core/exporting/browser_download_lifecycle.dart')
need('web pdf native blob download',
     'PdfPrintService' in text('lib/core/printing/enterprise_document_pdf_service.dart') and
     'browser_download.saveBinary' in pdf_web and
     'html.Blob' in binary_web and
     'html.AnchorElement' in binary_web and
     '..download = fileName' in binary_web and
     'html.window.open(' not in pdf_web)
need('web blob revoke delayed', 'Future<void>.delayed' in download_lifecycle and 'triggerBrowserDownload' in binary_web and 'Future<void>.delayed' in text('lib/core/exporting/excel_download_service_web.dart'))
cars_page = text('lib/features/inventory/cars/pages/cars_page.dart')
need(
    'car grid overflow headroom',
    'mainAxisExtent:' not in cars_page
    and 'ListView.separated(' in cars_page
    and 'final rowCount = (filteredCars.length + columns - 1) ~/ columns;' in cars_page
    and 'CarCard(' in cars_page,
)
need('product grid overflow headroom', 'mainAxisExtent:' in text('lib/features/inventory/pages/inventory_page.dart') and 'InventoryCard(' in text('lib/features/inventory/pages/inventory_page.dart'))
need('product action buttons wrap', 'Wrap(' in text('lib/features/inventory/widgets/inventory_card.dart'))
need('car action buttons wrap', 'Wrap(' in text('lib/features/inventory/cars/widgets/car_card.dart'))
need('r28 postgrest command exact wrapper', 'erp_r28_cloud_command' in cmd_sql and "notify pgrst,'reload schema'" in cmd_sql and any(x in cloud for x in ('erp_r35_cloud_command','erp_r37_cloud_command','erp_r39_cloud_command','erp_r41_cloud_command')))
need('r28-or-later cache token', any(x in text('web/index.html') and x in text('web/version.json') for x in ('r41-export-language-canonical-closure-20260809','r42-production-cashbox-guard-closure-20260809','r43-performance-functional-closure-20260809','r47-production-runtime-dependency-closure-20260810','r49-')))
need('localization workflow phrases canonical', 'أوامر البيع والتجهيز والفوترة والتحصيل والطباعة ضمن مسار تجاري موحد.' in text('lib/core/localization/module_translation_catalog.dart') and 'Vehicles without warehouse' in text('lib/core/localization/module_translation_catalog.dart') and 'Sales Order Fulfillment والتحصيل والطباعة ضمن مسار تجاري موحد.' not in text('lib/core/localization/module_translation_catalog.dart'))
need('no immutable movement removewhere', 'movements.removeWhere' not in movement_repo)

failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(('PASS' if v else 'FAIL'),k)
if failed: raise SystemExit('R28 verification failed: '+', '.join(failed))
print(f'PASS R28 complete runtime closure — {len(checks)} gates')
