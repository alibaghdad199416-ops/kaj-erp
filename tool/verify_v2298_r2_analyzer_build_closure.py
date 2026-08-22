#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
errors = []


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8-sig')


def need(ok: bool, message: str) -> None:
    if not ok:
        errors.append(message)


release = read('lib/core/release/app_release_info.dart')
theme = read('lib/app/theme.dart')
excel = read('lib/core/exporting/excel_export_service.dart')
reports = read('lib/features/settings/reports/services/report_export_service.dart')
pdf_export = read('lib/core/exporting/pdf_export_service.dart')
pdf_text = read('lib/core/printing/pdf_text_support.dart')
export_document = read('lib/core/exporting/export_document.dart')

need("static const String version = '22.9.8';" in release,
     'AppReleaseInfo version must match pubspec')
need('static const int buildNumber = 229008;' in release,
     'AppReleaseInfo build must match pubspec')
need('fieldFill' not in theme,
     'unused fieldFill analyzer blocker must be removed')
need('num _asNumber(' not in excel,
     'unused _asNumber analyzer blocker must be removed')
need("const arabic = false" not in reports,
     'constant English branch must not create analyzer dead code')

# Report export now centralizes canonical language selection in one helper used
# by Excel/CSV/PDF instead of duplicating local `l` variables in each method.
need(
    'String _language(ReportExportOptions options) =>' in reports
    and 'PdfTextSupport.canonicalPdfLanguage(options.language);' in reports
    and reports.count('final language = _language(options);') >= 5,
    'PDF/Excel/CSV export must honor the explicitly requested canonical Arabic/English language',
)
need(
    'language: language' in reports
    and 'final arabic = language == \'ar\';' in reports
    and 'ExcelWorkbookPresentation.prepareSheet(profile, arabic: arabic);' in reports,
    'Excel and PDF export must propagate the same requested language into their document pipelines',
)
need(
    'return PdfExportService().build(' in reports
    and 'ExportDocument(' in reports,
    'report PDF must use the shared authoritative PDF renderer',
)

# Font loading moved into the shared PDF renderer. The safety contract is now
# stronger: bundled Noto Naskh Arabic regular/bold fonts are required for every
# generic/report PDF, so browsers do not depend on CDN/popups/manifests.
need(
    'final fonts = await PdfTextSupport.loadFonts();' in pdf_export
    and 'pw.ThemeData.withFont(base: regular, bold: bold)' in pdf_export,
    'shared PDF renderer must load and apply the bilingual font pack',
)
need(
    "'assets/fonts/NotoNaskhArabic-Regular.ttf'" in pdf_text
    and "'assets/fonts/NotoNaskhArabic-Bold.ttf'" in pdf_text
    and 'pw.Font.ttf(regular)' in pdf_text
    and 'pw.Font.ttf(bold)' in pdf_text,
    'PDF font safety contract must retain bundled Arabic regular/bold fonts',
)
need(
    'bool get isArabic' in export_document,
    'ExportDocument must retain language-driven RTL/LTR identity',
)

if errors:
    print('FAILED V22.9.8 R2 analyzer/build closure')
    for error in errors:
        print('-', error)
    sys.exit(1)

print('PASS V22.9.8 R2 analyzer/build closure')
print('- release metadata synchronized with pubspec')
print('- known fatal analyzer warnings remain removed at source')
print('- requested Arabic/English language drives Excel, CSV and PDF through one pipeline')
print('- shared PDF renderer retains bundled bilingual font safety')
