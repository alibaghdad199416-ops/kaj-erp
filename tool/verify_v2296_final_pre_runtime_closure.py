from pathlib import Path
import json,re,sys
root=Path(__file__).resolve().parents[1]
def read(p): return (root/p).read_text(encoding="utf-8")
checks=[]
def need(ok,msg):
    if not ok: checks.append(msg)
need("version: 22.9.6+229006" in read("pubspec.yaml"),"release version")
need(json.loads(read("package.json"))["version"]=="22.9.6","package version")
top=read("lib/core/widgets/app_workspace_top_bar.dart")
need("foregroundColor: Colors.white70" not in top and "color: Colors.white38" not in top,"light top-bar contrast")
theme=read("lib/app/theme.dart")
need("0xFF17262D" in theme and "0xFFE8F2F5" in theme,"field label contrast")
for f in ["lib/features/inventory/cars/pages/add_car_page.dart","lib/features/inventory/cars/pages/edit_car_page.dart"]:
    x=read(f); need("FilteringTextInputFormatter.digitsOnly" in x,"vehicle year digits "+f); need("inputFormatters: keyboardType == TextInputType.number" in x,"vehicle text fields unrestricted "+f)
for f in ["lib/features/sales/workflow/pages/sales_order_draft_page.dart","lib/features/purchases/pages/purchase_order_draft_page.dart","lib/features/settings/pages/settings_page.dart"]:
    need("ThousandsInputFormatter(decimalDigits: 6)" in read(f),"six-decimal exchange rate "+f)
need("_accountCode(map['code'])" in read("lib/features/accounting/models/account_model.dart"),"account code normalization")
excel=read("lib/core/exporting/excel_export_service.dart"); recycle=read("lib/features/settings/recycle_bin/pages/recycle_bin_page.dart")
need("language: 'en'" in excel and "language: 'en'" in recycle,"English-only Excel")
need("ExcelExportService().save(_report())" in recycle,"Recycle Bin Excel export")
mig=read("supabase/migrations/20260807070000_v765_final_runtime_contract_closure.sql")
for token in ["erp_v765_invoice_policy_preflight","erp_v765_approve_sales_invoice_safe","erp_v765_approve_purchase_invoice_safe","erp_v764_assert_partner_dual_ledgers","erp_v764_definition_currency"]: need(token in mig,"invoice contract "+token)
need("erp_v765_approve_sales_invoice_safe" in read("lib/features/sales/workflow/repositories/sales_workflow_repository.dart"),"sales safe invoice approval")
need("erp_v765_approve_purchase_invoice_safe" in read("lib/features/purchases/repositories/purchase_workflow_repository.dart"),"purchase safe invoice approval")
if checks:
 print("FAILED V22.9.6 final pre-runtime closure"); [print(" - "+x) for x in checks]; sys.exit(1)
print("PASS V22.9.6 final pre-runtime closure")
print(" - top-bar and modal-field contrast contracts")
print(" - vehicle text/year input contracts")
print(" - six-decimal exchange-rate contract")
print(" - integer-style account-code presentation contract")
print(" - English-only export and Recycle Bin Excel contract")
print(" - sales/purchase invoice approval policy preflight contract")
