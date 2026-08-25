from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[1]
def text(rel): return (ROOT/rel).read_text(encoding='utf-8')
def need(name,ok,checks): checks[name]=bool(ok)
checks={}
# Preserve R29 acceptance baseline by importing textual outcomes independently.
need('r29 gate exists', (ROOT/'tool/verify_r29_final_acceptance_closure.py').exists(), checks)
need('r30-or-later cache token', any(x in text('web/index.html') and x in text('web/version.json') for x in ('r41-export-language-canonical-closure-20260809','r42-production-cashbox-guard-closure-20260809','r43-performance-functional-closure-20260809','r47-production-runtime-dependency-closure-20260810','r49-')), checks)
# No false 1970 dates in the accounting/export paths reported by production testing.
need('account statement has no unix epoch fallback', 'fromMillisecondsSinceEpoch(0' not in text('lib/features/accounting/models/account_statement_line_model.dart'), checks)
need('report export has no unix epoch fallback', 'fromMillisecondsSinceEpoch(0' not in text('lib/core/exporting/report_template_engine.dart'), checks)
need(
    'report export invalid dates render blank',
    re.search(
        r"parsed\s*==\s*null\s*\?\s*''",
        text('lib/core/exporting/report_template_engine.dart'),
    ) is not None,
    checks,
)
# Deployment must validate the current release, never an older R24 release.
pkg=json.loads(text('package.json'))['scripts']
need('production deploy points to r30-or-later', any(x in pkg.get('deploy:production','') for x in ('deploy_r41_production.ps1','deploy_r42_production.ps1','deploy_r43_production.ps1','deploy_r44_production.ps1','deploy_r49_production.ps1')), checks)
need('r30 deploy command exists', 'deploy_r30_production.ps1' in pkg.get('deploy:r30:production',''), checks)
need('r30 workspace validation exists', 'validate_r30_workspace.ps1' in pkg.get('validate:r30:workspace',''), checks)
need('workspace includes r30 gate', 'verify:r30' in pkg.get('verify:workspace',''), checks)
deploy=text('tool/deploy_r30_production.ps1')
need('deployment hardcodes correct supabase', "havlqebmnjdcwmpaaqew" in deploy, checks)
need('deployment hardcodes correct firebase', "kaj-erp" in deploy, checks)
need('deployment verifies authoritative remote migrations', 'RequiredRemoteMigrations' in deploy and 'migration list --linked' in deploy, checks)
need('deployment does not replay production migrations', 'supabase db push' not in deploy, checks)
need('deployment uses fresh validated web build', 'validate_r30_workspace.ps1' in deploy, checks)
# Critical user-requested paths remain present after hardening.
need('canonical EBL cashbox endpoints retained', (all(x in text('lib/features/accounting/cashbox/repositories/cashbox_repository.dart') for x in ['erp_r28_list_cash_accounts','erp_r28_save_cash_account']) or all(x in text('lib/features/accounting/cashbox/repositories/cashbox_repository.dart') for x in ['erp_r42_list_cash_accounts','erp_r42_save_cash_account'])), checks)
need('commercial drilldown retained', 'erp_r28_get_commercial_order_complete_details' in text('lib/features/sales/workflow/repositories/commercial_order_details_repository.dart'), checks)
need('movement server rpc retained', 'erp_r28_inventory_movement_log' in text('lib/features/inventory/data/inventory_repository.dart'), checks)
need('product movement pdf excel retained', all(x in text('lib/features/inventory/pages/inventory_movements_page.dart') for x in ['PdfExportService','ExcelExportService']), checks)
need('recycle bin excel retained', 'ExcelExportService().build(_report())' in text('lib/features/settings/recycle_bin/pages/recycle_bin_page.dart') and 'BinaryDownloadService.save' in text('lib/features/settings/recycle_bin/pages/recycle_bin_page.dart'), checks)
# Major PDF surfaces all remain behind the web-safe facade.
pdf_paths=['lib/features/accounting/cashbox/services/cash_voucher_pdf_service.dart','lib/core/printing/warehouse_transfer_pdf_service.dart','lib/core/printing/maintenance_document_pdf_service.dart','lib/core/printing/legacy_commercial_document_pdf_service.dart','lib/core/printing/enterprise_document_pdf_service.dart','lib/core/printing/accounting_report_export_service.dart','lib/features/settings/reports/services/report_export_service.dart']
need('all major pdf paths remain web-safe', all('PdfPrintService' in text(p) and 'Printing.layoutPdf' not in text(p) for p in pdf_paths), checks)
# No old deployment target should be the default.
need('default deploy no longer points to r24', 'deploy_r24_production.ps1' not in pkg.get('deploy:production',''), checks)
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(('PASS' if v else 'FAIL'),k)
if failed: raise SystemExit('R30 completion audit failed: '+', '.join(failed))
print(f'PASS R30 completion audit — {len(checks)} gates')
