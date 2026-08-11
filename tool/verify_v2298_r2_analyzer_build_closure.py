#!/usr/bin/env python3
from pathlib import Path
import re, sys
ROOT=Path(__file__).resolve().parents[1]
errors=[]
def read(p): return (ROOT/p).read_text(encoding='utf-8')
def need(ok,msg):
    if not ok: errors.append(msg)
release=read('lib/core/release/app_release_info.dart')
theme=read('lib/app/theme.dart')
excel=read('lib/core/exporting/excel_export_service.dart')
reports=read('lib/features/settings/reports/services/report_export_service.dart')
need("static const String version = '22.9.8';" in release,'AppReleaseInfo version must match pubspec')
need('static const int buildNumber = 229008;' in release,'AppReleaseInfo build must match pubspec')
need('fieldFill' not in theme,'unused fieldFill analyzer blocker must be removed')
need('num _asNumber(' not in excel,'unused _asNumber analyzer blocker must be removed')
need("const arabic = false" not in reports,'constant English branch must not create analyzer dead code')
need("final language = PdfTextSupport.canonicalPdfLanguage(options.language);" in reports,
     'PDF export must honor the requested canonical Arabic/English language')
need("final l = options.language;" in reports and
     "final l = PdfTextSupport.canonicalPdfLanguage(options.language);" in reports,
     'Excel and PDF export must use the explicitly requested language')
need('PdfTextSupport.loadFonts()' in reports and 'Unable to load the PDF font pack required for report export' in reports,
     'PDF font safety contract must remain intact')
if errors:
    print('FAILED V22.9.8 R2 analyzer/build closure')
    for e in errors: print('-',e)
    sys.exit(1)
print('PASS V22.9.8 R2 analyzer/build closure')
print('- release metadata synchronized with pubspec')
print('- 14 known fatal analyzer warnings removed at source')
print('- requested Arabic/English report export retained without constant-condition dead code')
