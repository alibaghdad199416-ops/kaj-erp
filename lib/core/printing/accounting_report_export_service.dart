import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'package:quality_line_erp/core/exporting/binary_download_service.dart';
import 'package:quality_line_erp/core/exporting/excel_download_service.dart';
import 'package:quality_line_erp/core/exporting/excel_workbook_presentation.dart';
import 'package:quality_line_erp/core/exporting/export_document.dart';
import 'package:quality_line_erp/core/exporting/pdf_export_service.dart';
import 'package:quality_line_erp/core/exporting/pdf_print_service.dart';
import 'package:quality_line_erp/core/exporting/xlsx_integrity.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/localization/domain_translation_catalog.dart';
import 'package:quality_line_erp/core/printing/pdf_text_support.dart';

/// Bilingual accounting-report exporter backed by the shared Quality Line
/// document identity. PostgreSQL rows remain authoritative in every format.
class AccountingReportExportService {
  const AccountingReportExportService();

  /// Some legacy accounting callers predate bilingual exports and still pass
  /// `arabic: false`. The active application locale is authoritative in that
  /// case, while an explicit Arabic request continues to win.
  bool _useArabic(bool requestedArabic) =>
      requestedArabic || AppTranslation.isArabic;

  Future<void> exportExcel({
    required String reportName,
    required String period,
    required String currency,
    required List<Map<String, Object?>> rows,
    required String Function(String key) label,
    required String Function(Object? value) format,
    required bool arabic,
    bool forceCashFlow = false,
  }) async {
    final useArabic = _useArabic(arabic);
    final language = useArabic ? 'ar' : 'en';
    final book = Excel.createExcel();
    final initial = book.getDefaultSheet();
    final sheetName = _safeSheet(_text(reportName, language));
    final sheet = book[sheetName];
    if (initial != null && initial != sheetName) book.delete(initial);
    ExcelWorkbookPresentation.prepareSheet(sheet, arabic: useArabic);

    final columns = _columns(rows, forceCashFlow: forceCashFlow);
    sheet.appendRow([TextCellValue(_text(reportName, language))]);
    ExcelWorkbookPresentation.styleTitle(
      sheet,
      row: 0,
      columnCount: columns.isEmpty ? 2 : columns.length,
    );
    sheet.appendRow([
      TextCellValue(useArabic ? 'الفترة' : 'Period'),
      TextCellValue(_text(period, language)),
    ]);
    sheet.appendRow([
      TextCellValue(useArabic ? 'العملة' : 'Currency'),
      TextCellValue(_text(currency, language)),
    ]);
    sheet.appendRow([
      TextCellValue(useArabic ? 'عدد السجلات' : 'Row count'),
      IntCellValue(rows.length),
    ]);
    sheet.appendRow(<CellValue>[]);

    if (columns.isNotEmpty) {
      const headerRow = 5;
      final headers = columns
          .map((key) => _label(label(key), language))
          .toList(growable: false);
      sheet.appendRow(headers.map(TextCellValue.new).toList(growable: false));
      ExcelWorkbookPresentation.styleHeader(sheet, headerRow, headers.length);
      for (final row in rows) {
        sheet.appendRow(
          List<CellValue>.generate(
            columns.length,
            (index) {
              final key = columns[index];
              final value = row[key];
              if (value is num || value is bool || value is DateTime) {
                return ExcelWorkbookPresentation.typedValue(
                  value,
                  columnLabel: headers[index],
                );
              }
              return ExcelWorkbookPresentation.typedValue(
                _value(format(value), language),
                columnLabel: headers[index],
              );
            },
            growable: false,
          ),
        );
      }
      ExcelWorkbookPresentation.styleDataRows(
        sheet,
        startRow: headerRow + 1,
        rowCount: rows.length,
        columnCount: headers.length,
        arabic: useArabic,
      );
      for (var index = 0; index < headers.length; index++) {
        final header = headers[index].toLowerCase();
        final wide = header.contains('description') ||
            header.contains('بيان') ||
            header.contains('الوصف') ||
            header.contains('reference') ||
            header.contains('مرجع') ||
            header.contains('account') ||
            header.contains('حساب');
        sheet.setColumnWidth(index, wide ? 28 : 18);
      }
    }

    final encoded = book.encode();
    if (encoded == null) {
      throw StateError(
        useArabic ? 'تعذر إنشاء ملف Excel.' : 'Unable to create Excel file.',
      );
    }
    await ExcelDownloadService.save(
      fileName:
          '${PdfTextSupport.filePart(_text(reportName, language))}-${DateTime.now().millisecondsSinceEpoch}.xlsx',
      bytes: XlsxIntegrity.finalize(encoded),
    );
  }

  Future<void> printPdf({
    required String reportName,
    required String period,
    required String currency,
    required List<Map<String, Object?>> rows,
    required String Function(String key) label,
    required String Function(Object? value) format,
    required bool arabic,
  }) async {
    final useArabic = _useArabic(arabic);
    final bytes = await buildPdf(
      reportName: reportName,
      period: period,
      currency: currency,
      rows: rows,
      label: label,
      format: format,
      arabic: useArabic,
    );
    await PdfPrintService.print(
      fileName:
          '${PdfTextSupport.filePart(_text(reportName, useArabic ? 'ar' : 'en'))}.pdf',
      bytes: bytes,
    );
  }

  Future<void> downloadPdf({
    required String reportName,
    required String period,
    required String currency,
    required List<Map<String, Object?>> rows,
    required String Function(String key) label,
    required String Function(Object? value) format,
    required bool arabic,
  }) async {
    final useArabic = _useArabic(arabic);
    final bytes = await buildPdf(
      reportName: reportName,
      period: period,
      currency: currency,
      rows: rows,
      label: label,
      format: format,
      arabic: useArabic,
    );
    await BinaryDownloadService.save(
      fileName:
          '${PdfTextSupport.filePart(_text(reportName, useArabic ? 'ar' : 'en'))}-${DateTime.now().millisecondsSinceEpoch}.pdf',
      bytes: bytes,
      mimeType: 'application/pdf',
    );
  }

  Future<Uint8List> buildPdf({
    required String reportName,
    required String period,
    required String currency,
    required List<Map<String, Object?>> rows,
    required String Function(String key) label,
    required String Function(Object? value) format,
    required bool arabic,
  }) async {
    final useArabic = _useArabic(arabic);
    final language = useArabic ? 'ar' : 'en';
    final columns = _columns(rows);
    final documentRows = rows
        .map(
          (row) => List<Object?>.generate(
            columns.length,
            (index) => _value(format(row[columns[index]]), language),
            growable: false,
          ),
        )
        .toList(growable: false);

    final document = ExportDocument(
      title: _text(reportName, language),
      subtitle:
          '${useArabic ? 'الفترة' : 'Period'}: ${_text(period, language)}',
      language: language,
      currency: _text(currency, language),
      generatedAt: DateTime.now(),
      metadata: <String, Object?>{
        useArabic ? 'الفترة' : 'Period': _text(period, language),
        useArabic ? 'العملة' : 'Currency': _text(currency, language),
        useArabic ? 'عدد السجلات' : 'Row count': rows.length,
      },
      columns: <ExportColumn>[
        for (final key in columns)
          ExportColumn(key: key, label: _label(label(key), language)),
      ],
      rows: documentRows,
    );
    return PdfExportService().build(
      document,
      pageFormat: columns.length > 6
          ? ExportPageFormat.a4Landscape
          : ExportPageFormat.a4Portrait,
    );
  }

  List<String> _columns(
    List<Map<String, Object?>> rows, {
    bool forceCashFlow = false,
  }) {
    const preferred = <String>[
      'entryDate',
      'entryNumber',
      'flowSection',
      'rootAccountCode',
      'rootAccountName',
      'hierarchyPath',
      'accountCode',
      'accountName',
      'description',
      'partyName',
      'paymentMethod',
      'referenceType',
      'referenceId',
      'currency',
      'openingBalance',
      'openingDebit',
      'openingCredit',
      'periodDebit',
      'periodCredit',
      'debit',
      'credit',
      'cashIn',
      'cashOut',
      'netCashFlow',
      'runningBalance',
      'closingDebit',
      'closingCredit',
      'balance',
      'costCenterName',
      'branchName',
    ];
    final all = <String>{for (final row in rows) ...row.keys};
    final extras = all.where((key) => !preferred.contains(key)).toList()
      ..sort();
    final result = <String>[
      ...preferred.where(all.contains),
      ...extras,
    ];
    if (forceCashFlow) {
      const first = <String>[
        'flowSection',
        'accountCode',
        'accountName',
        'entryDate',
        'entryNumber',
        'cashIn',
        'cashOut',
        'netCashFlow',
      ];
      final order = <String, int>{
        for (var index = 0; index < first.length; index++) first[index]: index,
      };
      result.sort((left, right) {
        final li = order[left] ?? 1000;
        final ri = order[right] ?? 1000;
        if (li != ri) return li.compareTo(ri);
        return left.compareTo(right);
      });
    }
    return result;
  }

  String _label(String value, String language) {
    final clean = PdfTextSupport.sanitize(value, singleLine: true);
    return DomainTranslationCatalog.translate(clean, language);
  }

  String _value(String value, String language) {
    final clean = PdfTextSupport.sanitize(value, singleLine: true);
    return DomainTranslationCatalog.translate(clean, language);
  }

  String _text(String value, String language) {
    final clean = PdfTextSupport.sanitize(value, singleLine: true);
    if (clean == 'تقرير خط الجودة') {
      return language == 'ar' ? clean : 'Quality Line Report';
    }
    if (clean == 'جميع الفترات' || clean == 'All periods') {
      return language == 'ar' ? 'جميع الفترات' : 'All periods';
    }
    if (clean == 'All currencies') {
      return language == 'ar' ? 'كل العملات' : clean;
    }
    return DomainTranslationCatalog.translate(clean, language);
  }

  String _safeSheet(String value) {
    final clean = PdfTextSupport.sanitize(value, singleLine: true)
        .replaceAll(RegExp(r'[\\/*?:\[\]]'), ' ')
        .trim();
    if (clean.isEmpty) return 'Report';
    return clean.length > 31 ? clean.substring(0, 31) : clean;
  }
}
