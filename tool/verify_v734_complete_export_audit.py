#!/usr/bin/env python3
from pathlib import Path
from verification_text import contains_code
import re
ROOT=Path(__file__).resolve().parents[1]
errors=[]
def read(path):
 p=ROOT/path
 if not p.exists(): errors.append(f"missing {path}"); return ""
 return p.read_text(encoding="utf-8")
action=read("lib/core/widgets/app_module_action_icon.dart")
sales=read("lib/features/sales/workflow/pages/order_details_dialog.dart")
maint=read("lib/features/maintenance/pages/maintenance_order_details_dialog.dart")
excel=read("lib/core/exporting/excel_export_service.dart")
relations=read("lib/core/exporting/excel_relation_index.dart")
theme=read("lib/core/printing/premium_document_theme.dart")
localizer=read("lib/features/settings/reports/services/report_field_localizer.dart")
release=read("lib/core/release/app_release_info.dart")+read("pubspec.yaml")
if contains_code(action, "required this.color"): errors.append("action color remains required")
for name,text in (("sales",sales),("maintenance",maint)):
 if re.search(r"AppModuleActionIcon\([\s\S]{0,220}?color:\s*const Color",text): errors.append(f"{name} command bar still supplies semantic colors")
for needle in ("Workbook profile","ExcelRelationIndex.build","Relation index","Workbook schema version", "Date and time"):
 if needle not in excel: errors.append(f"generic Excel missing {needle}")
for needle in ("business references rather than", "internal UUIDs", "_linkedModule", "document.columns"):
 if needle not in relations: errors.append(f"relation index missing {needle}")
for needle in ("class PremiumDocumentTheme","headerDecoration","infoDecoration","footerStyle"):
 if needle not in theme: errors.append(f"PDF theme missing {needle}")
if "DocumentNomenclature.field" not in localizer or "DocumentNomenclature.documentType" not in localizer: errors.append("report nomenclature not delegated to shared catalog")
for needle in ("18.9.8","189800"):
 if needle not in release: errors.append(f"release missing {needle}")
services=[
 "lib/core/exporting/pdf_export_service.dart",
 "lib/core/printing/enterprise_document_pdf_service.dart",
 "lib/core/printing/maintenance_document_pdf_service.dart",
 "lib/core/printing/warehouse_transfer_pdf_service.dart",
 "lib/features/accounting/cashbox/services/cash_voucher_pdf_service.dart",
 "lib/features/settings/reports/services/report_export_service.dart",
]
for service in services:
 if "PremiumDocumentTheme" not in read(service): errors.append(f"{service} does not use shared premium theme")
if errors:
 print("FAILED V7.3.4 complete export audit")
 for e in errors: print("  -",e)
 raise SystemExit(1)
print("PASS V7.3.4 complete export audit")
print("  - command bars no longer carry per-action semantic colors")
print("  - generic Excel exports include profile and relation-index sheets")
print("  - field and document names share one bilingual catalog")
print("  - all principal PDF exporters use one premium visual theme")
