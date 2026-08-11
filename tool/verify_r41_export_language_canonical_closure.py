from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[1]
def t(p): return (ROOT/p).read_text(encoding='utf-8',errors='ignore')
checks={}
def need(name, ok): checks[name]=bool(ok)
need('R40 retained', 'verify:r40' in t('package.json'))
pdf=t('lib/core/printing/pdf_text_support.dart')
need('browser PDF honors canonical Arabic/English', "canonicalPdfLanguage" in pdf and "startsWith('ar') ? 'ar' : 'en'" in pdf and 'canonicalPdfArabic' in pdf)
need('Arabic uses bundled fonts without Latin-only fallback', 'assets/fonts/NotoNaskhArabic-Regular.ttf' in pdf and 'assets/fonts/NotoNaskhArabic-Bold.ttf' in pdf and 'pw.Font.helvetica()' not in pdf)
need('enterprise PDF canonical language', 'PdfTextSupport.canonicalPdfLanguage(language)' in t('lib/core/printing/enterprise_document_pdf_service.dart'))
need('maintenance PDF canonical browser language', 'PdfTextSupport.canonicalPdfArabic(arabic)' in t('lib/core/printing/maintenance_document_pdf_service.dart'))
need('warehouse PDF canonical language', 'PdfTextSupport.canonicalPdfLanguage(language)' in t('lib/core/printing/warehouse_transfer_pdf_service.dart'))
need('cash voucher PDF canonical browser language', 'PdfTextSupport.canonicalPdfArabic(arabic)' in t('lib/features/accounting/cashbox/services/cash_voucher_pdf_service.dart'))
report=t('lib/features/settings/reports/services/report_export_service.dart')
need('report PDF error is not mixed-language', 'Unable to load the PDF font pack required for report export:' in report and 'تم إيقاف التصدير لمنع ظهور رموز بدل الأحرف العربية' not in report)
acct=t('lib/core/printing/accounting_report_export_service.dart')
need('accounting Excel canonical English metadata', 'exportReportName = _englishText(reportName)' in acct and 'exportPeriod = _englishText(period)' in acct and 'exportCurrency = _englishText(currency)' in acct)
need('accounting columns and values canonical English', '_englishText(label(key))' in acct and '_englishText(format(value))' in acct and '_englishText(format(row[key]))' in acct)
cat=t('lib/core/localization/module_translation_catalog.dart')+t('lib/core/localization/app_localizations.dart')
legacy=['بحث برقم Order أو اسم الشريك','Search برقم Order أو اسم الشريك','دفعات invoice','عارض warehouse','تدفق العمليات record','Sales Order Fulfillment والتحصيل والطباعة ضمن مسار تجاري موحد.','Purchase Order Received and Invoice والدفع والطباعة ضمن مسار تجاري موحد.','Finance موحد للحسابات والقيود والسيولة والأصول والتقارير.','Dashboard التنفيذية','صور السيارة / Car photos','Landed Cost للوحدة','Landed Cost — تكاليف الوصول']
need('mixed legacy localization aliases removed', all(x not in cat for x in legacy))
need('canonical Arabic localization retained', all(x in cat for x in ['أوامر البيع والتجهيز والفوترة والتحصيل والطباعة ضمن مسار تجاري موحد.','ابحث برقم الأمر أو اسم الشريك','دفعات الفواتير','عارض المخازن','تدفق العمليات','تكلفة الوصول للوحدة','لوحة المعلومات التنفيذية']))
need('R39 canonical maintenance retained', ('erp_r39_create_cloud_maintenance_order' in t('lib/features/maintenance/data/maintenance_repository.dart') or 'erp_r49_create_cloud_maintenance_order' in t('lib/features/maintenance/data/maintenance_repository.dart')) and ('erp_r39_update_cloud_maintenance_draft' in t('lib/features/maintenance/data/maintenance_repository.dart') or 'erp_r49_update_cloud_maintenance_draft' in t('lib/features/maintenance/data/maintenance_repository.dart')))
pdfweb=t('lib/core/exporting/pdf_print_service_web.dart')
need('reliable browser PDF download retained', 'html.Blob' in pdfweb and 'html.AnchorElement' in pdfweb and '..download = safeFileName' in pdfweb and 'html.window.open(' not in pdfweb)
ver=json.loads(t('web/version.json'))
pkg=json.loads(t('package.json'))['scripts']
need('R41 metadata unified or superseded', (ver.get('releaseToken')=='r41-export-language-canonical-closure-20260809' and ver.get('syncEngine')=='22.9.8-r41-export-language-canonical-closure' and 'r41-export-language-canonical-closure-20260809' in t('web/index.html')) or ('verify:r42' in pkg and ver.get('releaseToken')=='r42-production-cashbox-guard-closure-20260809' and 'r42-production-cashbox-guard-closure-20260809' in t('web/index.html')) or ('verify:r43' in pkg and ver.get('releaseToken')=='r43-performance-functional-closure-20260809' and 'r43-performance-functional-closure-20260809' in t('web/index.html')) or (str(ver.get('releaseToken','')).startswith('r49-') and str(ver.get('syncEngine','')).startswith('22.9.8-r49-') and 'r49-' in t('web/index.html')))
need('R41 workspace gate', 'npm run verify:r41' in pkg.get('verify:workspace',''))
need('R41 default deploy or superseded', ('deploy_r41_production.ps1' in pkg.get('deploy:production','') and 'validate_r41_workspace.ps1' in t('tool/deploy_r41_production.ps1')) or ('deploy_r42_production.ps1' in pkg.get('deploy:production','') and 'validate_r42_workspace.ps1' in t('tool/deploy_r42_production.ps1')) or ('deploy_r43_production.ps1' in pkg.get('deploy:production','') and 'validate_r43_workspace.ps1' in t('tool/deploy_r43_production.ps1')) or ('deploy_r49_production.ps1' in pkg.get('deploy:production','') and 'validate_r49_workspace.ps1' in t('tool/deploy_r49_production.ps1')))
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(('PASS' if v else 'FAIL'),k)
if failed: raise SystemExit('R41 verification failed: '+', '.join(failed))
print(f'PASS R41 export/language canonical closure — {len(checks)} gates')
