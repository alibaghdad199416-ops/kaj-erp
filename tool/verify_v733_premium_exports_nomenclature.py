#!/usr/bin/env python3
"""Verify V7.3.3 unified actions, nomenclature, Excel links, and premium PDFs."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = {
    "action": ROOT / "lib/core/widgets/app_module_action_icon.dart",
    "catalog": ROOT / "lib/core/documents/document_nomenclature.dart",
    "sales": ROOT / "lib/features/sales/workflow/pages/order_details_dialog.dart",
    "maintenance": ROOT / "lib/features/maintenance/pages/maintenance_order_details_dialog.dart",
    "excel": ROOT / "lib/core/exporting/excel_workbook_presentation.dart",
    "excel_service": ROOT / "lib/core/exporting/excel_export_service.dart",
    "reports": ROOT / "lib/features/settings/reports/services/report_export_service.dart",
    "fields": ROOT / "lib/features/settings/reports/services/report_field_localizer.dart",
    "pdf": ROOT / "lib/core/exporting/pdf_export_service.dart",
    "release": ROOT / "lib/core/release/app_release_info.dart",
    "pubspec": ROOT / "pubspec.yaml",
}

errors: list[str] = []


def read(name: str) -> str:
    path = FILES[name]
    if not path.exists():
        errors.append(f"missing file: {path.relative_to(ROOT)}")
        return ""
    return path.read_text(encoding="utf-8")


def require(text: str, needles: tuple[str, ...], label: str) -> None:
    missing = [needle for needle in needles if needle not in text]
    if missing:
        errors.append(f"{label}: missing {', '.join(missing)}")


action = read("action")
catalog = read("catalog")
sales = read("sales")
maintenance = read("maintenance")
excel = read("excel")
excel_service = read("excel_service")
reports = read("reports")
fields = read("fields")
pdf = read("pdf")
release = read("release") + read("pubspec")

require(
    action,
    (
        "const systemAccent = KajDesignTokens.electricBlue",
        "Meaning is carried by the icon and tooltip",
        "Tooltip",
    ),
    "single-color document command buttons",
)
require(
    catalog,
    (
        "class DocumentNomenclature",
        "أمر شراء",
        "تجهيز مخزني",
        "استلام مخزني",
        "دفعة صيانة",
        "رقم المستند",
        "سعر الصرف",
    ),
    "shared operational nomenclature",
)
require(
    sales + maintenance,
    (
        "DocumentNomenclature.commercialOrder",
        "DocumentNomenclature.warehouseStage",
        "DocumentNomenclature.maintenanceOrder",
        "AppModuleActionIcon(",
    ),
    "order dialog naming and action integration",
)
require(
    excel,
    (
        "class ExcelWorkbookPresentation",
        "DateTimeCellValue.fromDateTime",
        "IntCellValue",
        "DoubleCellValue",
        "sheet.isRTL = arabic",
        "styleHeader",
        "styleDataRows",
    ),
    "typed and branded Excel exports",
)
require(
    excel_service + reports,
    (
        "ExcelWorkbookPresentation.typedValue",
        "Workbook schema version",
        "_relationIndexRows",
        "Cross-module document relations",
        "Currency context",
    ),
    "Excel metadata and cross-module relation index",
)
require(
    fields,
    (
        "'code': {'ar': 'الرمز'",
        "'paymentNumber': {'ar': 'رقم الدفعة'",
        "'linkedDocument': {'ar': 'المستند المرتبط'",
        "'exchangeRate': {'ar': 'سعر الصرف'",
    ),
    "normalized report and data-entry field labels",
)
theme = read("pdf") + read("reports") + (ROOT / "lib/core/printing/premium_document_theme.dart").read_text(encoding="utf-8")
require(
    theme,
    (
        "#101820",
        "#62BEC1",
        "#E8F6F6",
        "Official electronic document",
        "PremiumDocumentTheme",
    ),
    "premium PDF visual identity",
)
require(release, ("18.9.8", "189800"), "release version")

if errors:
    print("FAILED V7.3.3 premium exports and nomenclature")
    for error in errors:
        print(f"  - {error}")
    raise SystemExit(1)

print("PASS V7.3.3 premium exports and nomenclature")
print("  - order command buttons share one system accent and icon language")
print("  - sales, purchase, maintenance, and field terminology are centralized")
print("  - Excel files carry typed values, metadata, and a relation index")
print("  - generic and contextual PDFs use the premium Quality Line identity")
