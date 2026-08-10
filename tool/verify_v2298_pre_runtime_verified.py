from pathlib import Path
import json,re,sys
root=Path(__file__).resolve().parents[1]
fail=[]
def read(p): return (root/p).read_text(encoding='utf-8')
def need(ok,msg):
    if not ok: fail.append(msg)
need('version: 22.9.8+229008' in read('pubspec.yaml'),'pubspec version')
need(json.loads(read('package.json'))['version']=='22.9.8','package version')
theme=read('lib/app/theme.dart')
need('floatingLabelStyle' in theme and 'Color(0xFF0A5660)' in theme and 'Color(0xFF9DE7EA)' in theme,'modal label contrast')
center=read('lib/features/accounting/pages/accounting_center_page.dart')
for token in ['Detailed Trial Balance','General Ledger','Cash Flow Statement','Financial Position','Profit and Loss Statement','label: _exportLabel','arabic: false']:
    need(token in center,'English accounting export '+token)
acc=read('lib/core/printing/accounting_report_export_service.dart')
for bad in ['IntCellValue(', 'DoubleCellValue(', "TextCellValue('الفترة')", "TextCellValue('العملة')", "TextCellValue('عدد السجلات')"]:
    need(bad not in acc,'accounting export unsafe/non-English '+bad)
excel=read('lib/core/exporting/excel_export_service.dart')
need("language: 'en'" in excel,'Excel English only')
need('TextCellValue(_template.formatValue(value, column, document))' in excel,'Excel text serialization')
pres=read('lib/core/exporting/excel_workbook_presentation.dart')
need('IntCellValue(' not in pres and 'DoubleCellValue(' not in pres and 'DateTimeCellValue' not in pres,'presentation text-only cells')
recycle=read('lib/features/settings/recycle_bin/pages/recycle_bin_page.dart')
need('ExcelExportService().save(_report())' in recycle and "title: 'Recycle Bin Report'" in recycle,'Recycle Bin Excel path')
pay=read('lib/core/finance/invoice_payment_batch_dialog.dart')
cash=read('lib/features/accounting/cashbox/pages/cashbox_page.dart')
need('ThousandsInputFormatter(decimalDigits: 15)' in pay,'payment FX 15 decimals')
need('ThousandsInputFormatter(decimalDigits: 15)' in cash,'cashbox FX 15 decimals')
need('erp_v767_approve_sales_invoice_safe' in read('lib/features/sales/workflow/repositories/sales_workflow_repository.dart'),'sales approval RPC')
need('erp_v767_approve_purchase_invoice_safe' in read('lib/features/purchases/repositories/purchase_workflow_repository.dart'),'purchase approval RPC')
m=read('supabase/migrations/20260807080000_v767_invoice_export_runtime_closure.sql')
need('Purchase invoicing intentionally does not require a revenue account' in m,'purchase preflight revenue exception')
need("erp_workflow_partner_account" in m,'partner account real binding')
# Target the workflow surfaces that previously threw the minified runtime null error.
for rel in [
    'lib/features/sales/workflow/repositories/sales_workflow_repository.dart',
    'lib/features/purchases/repositories/purchase_workflow_repository.dart',
    'lib/core/finance/invoice_payment_batch_dialog.dart',
    'lib/features/settings/recycle_bin/pages/recycle_bin_page.dart',
]:
    text=read(rel)
    need('currentState!.validate()' not in text, 'unsafe form-state assertion '+rel)
    need('file.bytes!' not in text, 'unsafe file bytes assertion '+rel)
if fail:
    print('FAILED V22.9.8 pre-runtime verified closure')
    for x in fail: print(' - '+x)
    sys.exit(1)
print('PASS V22.9.8 pre-runtime verified closure')
print('- light/dark modal label contrast contract verified')
print('- fifteen-decimal FX input verified')
print('- accounting PDF/Excel export forced to English at call surface')
print('- accounting/recycle-bin Excel uses web-safe text cell serialization')
print('- sales/purchase invoice approval uses V767 module-aware preflight')
print('- previously failing workflow surfaces avoid known unsafe form/file assertions')
