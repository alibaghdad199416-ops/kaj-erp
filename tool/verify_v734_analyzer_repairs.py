#!/usr/bin/env python3
"""Regression gate for the analyzer failures found during the 18.9.4 deploy."""
from pathlib import Path
from verification_text import contains_code
import re

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []


def read(relative: str) -> str:
    path = ROOT / relative
    if not path.exists():
        errors.append(f"missing {relative}")
        return ""
    return path.read_text(encoding="utf-8-sig")


excel = read("lib/core/exporting/excel_export_service.dart")
excel_style = read("lib/core/exporting/excel_workbook_presentation.dart")
pdf = read("lib/core/exporting/pdf_export_service.dart")
dashboard = read("lib/features/dashboard/pages/dashboard_page.dart")
reports = read("lib/features/settings/reports/pages/reports_page.dart")

# A conditional expression used as a map key must be wrapped as one expression.
for bad in (
    "if (document.isArabic) 'لغة الملف' else 'Workbook language':",
    "if (document.isArabic) 'العملة' else 'Currency':",
    "if (document.isArabic) 'تاريخ التصدير' else 'Export date':",
    "if (document.isArabic) 'وقت التصدير' else 'Export time':",
):
    if bad in excel:
        errors.append(f"invalid conditional map entry remains: {bad}")

for good in (
    "(document.isArabic ? 'لغة الملف' : 'Workbook language'):",
    "(document.isArabic ? 'العملة' : 'Currency'):",
    "(document.isArabic ? 'تاريخ التصدير' : 'Export date'):",
    "(document.isArabic ? 'وقت التصدير' : 'Export time'):",
):
    if good not in excel:
        errors.append(f"fixed conditional map key missing: {good}")

if re.search(r"const\s+(TextCellValue|BoolCellValue)\(", excel_style):
    errors.append("non-const Excel cell constructors are still invoked with const")

if "premium_document_theme.dart" not in pdf:
    errors.append("PDF exporter does not import PremiumDocumentTheme")
if "PremiumDocumentTheme.ink" not in pdf:
    errors.append("PDF exporter does not use PremiumDocumentTheme")

if "AccessController" not in dashboard:
    errors.append("dashboard does not resolve the signed-in user via AccessController")
if not contains_code(dashboard, "context.select<AccessController, String>"):
    errors.append("dashboard user name is not reactively selected")
if re.search(r"\buser\?\.fullName", dashboard):
    errors.append("undefined dashboard user reference remains")

if "'${_selectedModule} ${section.key}'" in reports:
    errors.append("unnecessary interpolation braces remain in reports page")

if errors:
    print("FAILED V7.3.4 analyzer regression repair")
    for error in errors:
        print("  -", error)
    raise SystemExit(1)

print("PASS V7.3.4 analyzer regression repair")
print("  - Excel conditional map keys are valid Dart entries")
print("  - Excel cell values no longer use unsupported const constructors")
print("  - premium PDF theme is imported by the generic exporter")
print("  - dashboard user name is sourced from AccessController")
print("  - the strict analyzer interpolation info is removed")
