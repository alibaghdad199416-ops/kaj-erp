from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def text(rel): return (ROOT/rel).read_text(encoding='utf-8')
checks={}
def need(name, ok): checks[name]=bool(ok)
pdf_paths=['lib/features/accounting/cashbox/services/cash_voucher_pdf_service.dart','lib/core/printing/warehouse_transfer_pdf_service.dart','lib/core/printing/maintenance_document_pdf_service.dart','lib/core/printing/legacy_commercial_document_pdf_service.dart','lib/core/printing/enterprise_document_pdf_service.dart','lib/core/printing/accounting_report_export_service.dart','lib/features/settings/reports/services/report_export_service.dart']
need('all major pdf paths use browser-safe facade', all('PdfPrintService' in text(p) for p in pdf_paths))
need('no direct Printing.layoutPdf in major pdf paths', all('Printing.layoutPdf' not in text(p) for p in pdf_paths))
need('cash voucher bundled logo optional on web', 'if (!kIsWeb)' in text(pdf_paths[0]))
need('maintenance bundled logo optional on web', 'if (!kIsWeb)' in text(pdf_paths[2]))
need('warehouse bundled logo optional on web', 'if (!kIsWeb)' in text(pdf_paths[1]))
pdf_web=text('lib/core/exporting/pdf_print_service_web.dart')
need('web pdf blob print path', 'html.Blob' in pdf_web and ('frameWindow.print()' in pdf_web or "html.window.open(url, '_blank')" in pdf_web))
need('excel blob lifetime safe', 'Future<void>.delayed' in text('lib/core/exporting/excel_download_service_web.dart'))
need('binary blob lifetime safe', 'Future<void>.delayed' in text('lib/core/exporting/binary_download_service_web.dart'))
need('recycle bin excel enabled', 'ExcelExportService().build(_report())' in text('lib/features/settings/recycle_bin/pages/recycle_bin_page.dart') and 'BinaryDownloadService.save' in text('lib/features/settings/recycle_bin/pages/recycle_bin_page.dart'))
need('product edit and detail callbacks active', 'onView: () => _showProductDetails' in text('lib/features/inventory/pages/inventory_page.dart') and 'onEdit: () => _editProduct' in text('lib/features/inventory/pages/inventory_page.dart'))
need('product movement rpc plus pdf excel', 'erp_r28_inventory_movement_log' in text('lib/features/inventory/data/inventory_repository.dart') and 'ExcelExportService' in text('lib/features/inventory/pages/inventory_movements_page.dart') and 'PdfExportService' in text('lib/features/inventory/pages/inventory_movements_page.dart'))
need('commercial details full drilldown endpoint', 'erp_r28_get_commercial_order_complete_details' in text('lib/features/sales/workflow/repositories/commercial_order_details_repository.dart'))
need('cashbox canonical read save endpoints', all(x in text('lib/features/accounting/cashbox/repositories/cashbox_repository.dart') for x in ['erp_r28_list_cash_accounts','erp_r28_save_cash_account']) or all(x in text('lib/features/accounting/cashbox/repositories/cashbox_repository.dart') for x in ['erp_r42_list_cash_accounts','erp_r42_save_cash_account']))
need('cash model has no unix epoch fallback', 'DateTime.fromMillisecondsSinceEpoch(0)' not in text('lib/features/accounting/cashbox/models/cash_transaction_model.dart'))
account_model=text('lib/features/accounting/models/account_model.dart')
need('account code identifier semantics', 'database text identifiers' in account_model and 'return raw;' in account_model)
acct=text('lib/features/accounting/pages/accounting_center_page.dart')
need('accounting filters wired to repository', all(v in acct for v in ['_currency','_branchId','_costCenterId','_fromDate','_toDate','ProfessionalAccountingRepository().loadReport']))
need('r29-or-later cache token', any(x in text('web/index.html') and x in text('web/version.json') for x in ('r41-export-language-canonical-closure-20260809','r42-production-cashbox-guard-closure-20260809','r43-performance-functional-closure-20260809','r47-production-runtime-dependency-closure-20260810','r49-')))
cat=text('lib/core/localization/module_translation_catalog.dart')+text('lib/core/localization/app_localizations.dart')
required=['سيارات بلا مخزن','سيارات غير مرتبطة بمخزن حالي','إجمالي العملاء','مركز المبيعات','أوامر البيع والتجهيز والفوترة والتحصيل والطباعة ضمن مسار تجاري موحد.','ابحث برقم الأمر أو اسم الشريك','مفوتر','مسدد','النتائج','مركز المشتريات','المركز المالي والمحاسبي','عرض موحد للحسابات والقيود والسيولة والأصول والتقارير المالية.','قيد كلفة فاتورة البيع حسب عملة المخزون','أوامر المبيعات','بنود أوامر المبيعات','أوامر الشراء','بنود أوامر المشتريات','مستندات الدورة التجارية','دفعات الفواتير','عارض المخازن','حركات الصندوق','تدفق العمليات','لا توجد تنبيهات تشغيلية']
need('explicit requested English terminology covered', all(v in cat for v in required))
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(('PASS' if v else 'FAIL'),k)
if failed: raise SystemExit('R29 verification failed: '+', '.join(failed))
print(f'PASS R29 final acceptance closure — {len(checks)} gates')
