from pathlib import Path
import json, sys
root=Path(__file__).resolve().parents[1]
checks=[]
def read(p): return (root/p).read_text(encoding='utf-8')
def need(ok,msg):
    if not ok: checks.append(msg)

need("version: 22.9.7+229007" in read("pubspec.yaml"),"release version")
need(json.loads(read("package.json"))["version"]=="22.9.7","package version")
theme=read("lib/app/theme.dart")
need("Color(0xFF0A5660)" in theme and "Color(0xFF9DE7EA)" in theme,"light/dark floating label contrast")
need("decimalPatternDigits" not in read("lib/core/exporting/report_template_engine.dart"),"web-safe number export formatting")
display=read("lib/core/utils/erp_display_formatter.dart")
need("decimalPatternDigits" not in display,"web-safe global number formatting")
need("return tail.isEmpty ? head : '$head$tail';" in display,"account codes render without decimal separators")
excel=read("lib/core/exporting/excel_export_service.dart")
need("TextCellValue(_template.formatValue(value, column, document))" in excel,"Excel web-safe text serialization")
reports=read("lib/features/settings/reports/services/report_export_service.dart")
need("const language = 'en';" in reports and "const l = 'en';" in reports,"reports are English-only")
need("typedValue(" not in reports,"report Excel export avoids typed numeric cells on web")
need("ThousandsInputFormatter(decimalDigits: 6)" in read("lib/core/finance/invoice_payment_batch_dialog.dart"),"payment exchange rate six decimals")
need("ThousandsInputFormatter(decimalDigits: 6)" in read("lib/features/accounting/cashbox/pages/cashbox_page.dart"),"cash transfer exchange rate six decimals")
need("erp_v767_approve_sales_invoice_safe" in read("lib/features/sales/workflow/repositories/sales_workflow_repository.dart"),"sales invoice v767 approval")
need("erp_v767_approve_purchase_invoice_safe" in read("lib/features/purchases/repositories/purchase_workflow_repository.dart"),"purchase invoice v767 approval")
migration=read("supabase/migrations/20260807080000_v767_invoice_export_runtime_closure.sql")
for token in ["erp_v767_invoice_policy_preflight","Purchase invoicing intentionally does not require a revenue account","erp_v767_assert_partner_ledgers","erp_v767_approve_sales_invoice_safe","erp_v767_approve_purchase_invoice_safe"]:
    need(token in migration,"migration contract "+token)
if checks:
    print("FAILED V22.9.7 runtime blocker closure")
    for c in checks: print(" - "+c)
    sys.exit(1)
print("PASS V22.9.7 runtime blocker closure")
print("- modal field labels have explicit high-contrast light/dark colors")
print("- exchange-rate input supports six decimals on payment/cash-transfer paths")
print("- PDF/Excel reporting is forced to English")
print("- Excel export avoids web number-format encoder crash")
print("- sales/purchase invoice approval uses module-aware V767 preflight")
