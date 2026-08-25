import 'package:quality_line_erp/core/exporting/adaptive_pdf_table.dart';
import 'package:quality_line_erp/core/exporting/binary_download_service.dart';
import 'package:quality_line_erp/core/exporting/pdf_print_service.dart';
import 'package:quality_line_erp/core/exporting/excel_download_service.dart';
import 'package:quality_line_erp/core/exporting/excel_workbook_presentation.dart';
import 'package:quality_line_erp/core/printing/pdf_text_support.dart';
import 'package:quality_line_erp/core/printing/premium_document_theme.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';

import 'report_field_localizer.dart';
import 'package:quality_line_erp/features/settings/reports/models/contextual_report_section.dart';
import 'package:quality_line_erp/features/settings/reports/models/execution_audit_row.dart';
import 'package:quality_line_erp/features/settings/reports/models/report_export_options.dart';
import 'package:quality_line_erp/features/settings/reports/models/report_model.dart';
import 'contextual_report_customizer.dart';

class ReportExportService {
  static Future<pw.MemoryImage?>? _bundledLogoFuture;

  static Future<pw.MemoryImage?> _loadBundledLogo() =>
      _bundledLogoFuture ??= (() async {
        if (kIsWeb) return null;
        try {
          final data = await rootBundle.load(
            'assets/images/khat_al_jawda_logo.jpg',
          );
          return pw.MemoryImage(data.buffer.asUint8List());
        } catch (error, stackTrace) {
          AppLogger.debug(
            'Report logo could not be loaded: $error\n$stackTrace',
          );
          return null;
        }
      })();

  // Report artifacts are intentionally English-only. Keep the language behind
  // a runtime getter so the analyzer does not fold English-only branches into
  // dead code while the shared renderer remains structurally bilingual.
  String get _exportLanguage => 'en';

  bool _isArabicExportLanguage(String language) => language == 'ar';

  Future<void> exportExcel(
    ReportModel report, {
    String module = 'overview',
    List<ExecutionAuditRow> executionRows = const [],
    ReportExportOptions options = const ReportExportOptions(),
    String period = 'جميع الفترات',
    List<ContextualReportSection> sections = const [],
  }) async {
    sections = const ContextualReportCustomizer().apply(sections, options);
    final book = Excel.createExcel();
    final defaultSheet = book.getDefaultSheet();
    if (defaultSheet != null) book.delete(defaultSheet);
    final language = _exportLanguage;
    final arabic = _isArabicExportLanguage(language);
    final generatedAt = DateTime.now();
    final usedSheetNames = <String>{};

    final metadataName = _uniqueSheetTitle(
      arabic ? 'تعريف الملف' : 'Workbook profile',
      'Profile',
      usedSheetNames,
    );
    usedSheetNames.add(metadataName);
    final metadata = book[metadataName];
    ExcelWorkbookPresentation.prepareSheet(metadata, arabic: arabic);
    metadata.appendRow([_excelText(_localize(options.title, language))]);
    ExcelWorkbookPresentation.styleTitle(metadata, row: 0, columnCount: 2);
    final metadataRows = <(String, Object?)>[
      (_tr('module', language), _moduleName(module, language)),
      (_tr('period', language), period),
      (
        arabic ? 'لغة الملف' : 'Workbook language',
        arabic ? 'العربية' : 'English',
      ),
      (arabic ? 'سياق العملة' : 'Currency context', 'IQD / USD'),
      (arabic ? 'تاريخ التصدير' : 'Export date', generatedAt),
      (arabic ? 'وقت التصدير' : 'Export time', generatedAt),
      (arabic ? 'إصدار بنية الملف' : 'Workbook schema version', '18.9.12'),
    ];
    for (var index = 0; index < metadataRows.length; index++) {
      final row = metadataRows[index];
      metadata.appendRow([
        _excelText(row.$1),
        _excelText(_excelExportValue(row.$2)),
      ]);
      metadata
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: index + 1))
          .cellStyle = ExcelWorkbookPresentation
          .metadataLabelStyle;
      metadata
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: index + 1))
          .cellStyle = ExcelWorkbookPresentation
          .metadataValueStyle;
    }
    metadata.setColumnWidth(0, 25);
    metadata.setColumnWidth(1, 34);

    final overviewName = _uniqueSheetTitle(
      _sheetName('summary', language),
      'Summary',
      usedSheetNames,
    );
    usedSheetNames.add(overviewName);
    final overview = book[overviewName];
    _appendExcelTable(
      overview,
      title: options.title,
      headers: [_tr('indicator', language), _tr('value', language)],
      rows: _moduleRows(report, module, language)
          .map<List<Object?>>((row) => <Object?>[row.$1, row.$2])
          .toList(growable: false),
      language: language,
    );

    if (options.includeOperational) {
      final name = _uniqueSheetTitle(
        _sheetName('operations', language),
        'Operations',
        usedSheetNames,
      );
      usedSheetNames.add(name);
      _appendExcelTable(
        book[name],
        title: _tr('operationalIndicators', language),
        headers: [
          _tr('operationalIndicator', language),
          _tr('value', language),
        ],
        rows: _operationalRows(report, language)
            .map<List<Object?>>((row) => <Object?>[row.$1, row.$2])
            .toList(growable: false),
        language: language,
      );
    }

    if (options.includeMonthly) {
      final name = _uniqueSheetTitle(
        _sheetName('monthly', language),
        'Monthly',
        usedSheetNames,
      );
      usedSheetNames.add(name);
      _appendExcelTable(
        book[name],
        title: _tr('monthlyPerformance', language),
        headers: [
          _tr('month', language),
          _tr('sales', language),
          _tr('purchases', language),
          _tr('expenses', language),
        ],
        rows: report.monthlyPoints
            .map<List<Object?>>(
              (point) => <Object?>[
                point.label,
                point.sales,
                point.purchases,
                point.expenses,
              ],
            )
            .toList(growable: false),
        language: language,
      );
    }

    if (options.includeExecutors) {
      final name = _uniqueSheetTitle(
        _sheetName('executors', language),
        'Executors',
        usedSheetNames,
      );
      usedSheetNames.add(name);
      _appendExcelTable(
        book[name],
        title: _tr('dataExecutors', language),
        headers: [
          _tr('user', language),
          _tr('action', language),
          _tr('entity', language),
          _tr('date', language),
        ],
        rows: executionRows
            .map<List<Object?>>(
              (row) => <Object?>[
                row.userName,
                row.action,
                row.entityType,
                row.createdAt,
              ],
            )
            .toList(growable: false),
        language: language,
      );
    }

    for (final section in sections) {
      final sheetName = _uniqueSheetTitle(
        _localize(section.title, language),
        section.key,
        usedSheetNames,
      );
      usedSheetNames.add(sheetName);
      _appendExcelTable(
        book[sheetName],
        title: _localize(section.title, language),
        headers: section.columns
            .map((value) => _localize(value, language))
            .toList(growable: false),
        rows: section.rows
            .map<List<Object?>>(
              (row) => List<Object?>.generate(
                section.columns.length,
                (index) => index < row.length ? row[index] : '',
              ),
            )
            .toList(growable: false),
        language: language,
      );
    }

    final relationRows = _relationIndexRows(sections, language);
    final relationName = _uniqueSheetTitle(
      arabic ? 'دليل الربط' : 'Relation index',
      'Relations',
      usedSheetNames,
    );
    usedSheetNames.add(relationName);
    _appendExcelTable(
      book[relationName],
      title: arabic
          ? 'الربط بين الوحدات والمستندات'
          : 'Cross-module document relations',
      headers: arabic
          ? const <String>[
              'الوحدة المصدرية',
              'السجل المصدر',
              'نوع الارتباط',
              'رقم السجل المرتبط',
              'الوحدة المرتبطة',
            ]
          : const <String>[
              'Source module',
              'Source record',
              'Relation type',
              'Linked record number',
              'Linked module',
            ],
      rows: relationRows,
      language: language,
    );

    book.setDefaultSheet(metadataName);
    final bytes = book.encode();
    if (bytes == null) throw StateError(_tr('excelError', language));
    await ExcelDownloadService.save(
      fileName: '${_fileName(module, language)}.xlsx',
      bytes: Uint8List.fromList(bytes),
    );
  }

  Future<void> exportCsv(
    ReportModel report, {
    String module = 'overview',
    List<ExecutionAuditRow> executionRows = const [],
    ReportExportOptions options = const ReportExportOptions(),
    String period = 'جميع الفترات',
    List<ContextualReportSection> sections = const [],
  }) async {
    sections = const ContextualReportCustomizer().apply(sections, options);
    final l = options.language;
    final rows = <List<Object?>>[
      [options.title],
      [_tr('module', l), _moduleName(module, l)],
      [_tr('period', l), period],
    ];
    if (options.includeGeneratedAt)
      rows.add([_tr('generatedAt', l), _dateTime(DateTime.now(), l)]);
    rows.add([]);
    rows.add([_tr('indicator', l), _tr('value', l)]);
    rows.addAll(_moduleRows(report, module, l).map((e) => [e.$1, e.$2]));
    if (options.includeOperational) {
      rows.add([]);
      rows.add([_tr('operationalIndicator', l), _tr('value', l)]);
      rows.addAll(_operationalRows(report, l).map((e) => [e.$1, e.$2]));
    }
    if (options.includeMonthly) {
      rows.add([]);
      rows.add([
        _tr('month', l),
        _tr('sales', l),
        _tr('purchases', l),
        _tr('expenses', l),
      ]);
      rows.addAll(
        report.monthlyPoints.map(
          (p) => [p.label, p.sales, p.purchases, p.expenses],
        ),
      );
    }
    if (options.includeExecutors) {
      rows.add([]);
      rows.add([
        _tr('user', l),
        _tr('action', l),
        _tr('entity', l),
        _tr('date', l),
      ]);
      rows.addAll(
        executionRows.map(
          (e) => [
            e.userName,
            e.action,
            e.entityType,
            _dateTime(e.createdAt, l),
          ],
        ),
      );
    }
    for (final section in sections) {
      rows.add([]);
      rows.add([_localize(section.title, l)]);
      rows.add(section.columns.map((value) => _localize(value, l)).toList());
      rows.addAll(
        section.rows.map(
          (row) => List<String>.generate(
            section.columns.length,
            (index) => _localize(index < row.length ? row[index] : '', l),
          ),
        ),
      );
    }
    final csv = rows.map((r) => r.map(_escapeCsv).join(',')).join('\r\n');
    await BinaryDownloadService.save(
      fileName: '${_fileName(module, l)}.csv',
      bytes: Uint8List.fromList(utf8.encode('\uFEFF$csv')),
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  Future<void> previewPdf(
    ReportModel report, {
    String module = 'overview',
    List<ExecutionAuditRow> executionRows = const [],
    ReportExportOptions options = const ReportExportOptions(),
    String period = 'جميع الفترات',
    List<ContextualReportSection> sections = const [],
  }) async {
    final bytes = await buildPdf(
      report,
      module: module,
      executionRows: executionRows,
      options: options,
      period: period,
      sections: sections,
    );
    await PdfPrintService.print(
      fileName: '${_fileName(module, 'en')}.pdf',
      bytes: bytes,
    );
  }

  Future<void> downloadPdf(
    ReportModel report, {
    String module = 'overview',
    List<ExecutionAuditRow> executionRows = const [],
    ReportExportOptions options = const ReportExportOptions(),
    String period = 'جميع الفترات',
    List<ContextualReportSection> sections = const [],
  }) async {
    final bytes = await buildPdf(
      report,
      module: module,
      executionRows: executionRows,
      options: options,
      period: period,
      sections: sections,
    );
    await BinaryDownloadService.save(
      fileName: '${_fileName(module, 'en')}.pdf',
      bytes: bytes,
      mimeType: 'application/pdf',
    );
  }

  Future<Uint8List> buildPdf(
    ReportModel report, {
    String module = 'overview',
    List<ExecutionAuditRow> executionRows = const [],
    ReportExportOptions options = const ReportExportOptions(),
    String period = 'جميع الفترات',
    List<ContextualReportSection> sections = const [],
  }) async {
    sections = const ContextualReportCustomizer().apply(sections, options);
    final l = _exportLanguage;
    final arabic = _isArabicExportLanguage(l);
    // PdfGoogleFonts.notoNaskhArabicRegular is cached by PdfTextSupport.
    late final PdfFontPack fonts;
    try {
      fonts = await PdfTextSupport.loadFonts();
    } catch (error) {
      throw StateError(
        'Unable to load the PDF font pack required for report export: $error',
      );
    }
    final regular = fonts.regular;
    final bold = fonts.bold;
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final branding = await _loadBranding(l);
    final document = pw.Document(
      title: _localize(options.title, l),
      author: 'KAJ ERP',
      subject: _moduleName(module, l),
      theme: theme,
    );
    final direction = arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    document.addPage(
      pw.MultiPage(
        pageFormat:
            options.landscape ||
                sections.any((section) => section.columns.length > 5)
            ? PdfPageFormat.a4.landscape
            : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        textDirection: direction,
        header: (_) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  if (branding.logo != null)
                    pw.Container(
                      width: 30,
                      height: 30,
                      margin: const pw.EdgeInsets.only(right: 8),
                      child: pw.Image(branding.logo!),
                    ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        branding.companyName,
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 15,
                          color: PdfColor.fromHex('#111827'),
                        ),
                      ),
                      if (branding.details.isNotEmpty)
                        pw.Text(
                          branding.details,
                          style: const pw.TextStyle(
                            fontSize: 7.5,
                            color: PdfColors.grey700,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              pw.Text(
                _localize(period, l),
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
        footer: (c) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: const pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                arabic
                    ? 'تم إنشاء التقرير إلكترونيًا بواسطة نظام خط الجودة'
                    : 'Generated electronically by Quality Line ERP',
                style: const pw.TextStyle(fontSize: 7.5),
              ),
              pw.Text(
                '${c.pageNumber} / ${c.pagesCount}',
                style: pw.TextStyle(font: bold, fontSize: 8),
              ),
            ],
          ),
        ),
        build: (_) => [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PremiumDocumentTheme.ink,
              borderRadius: pw.BorderRadius.circular(9),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _localize(options.title, l),
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                  textDirection: direction,
                ),
                pw.SizedBox(height: 6),
                pw.Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    pw.Text(
                      '${_tr('module', l)}: ${_moduleName(module, l)}',
                      style: pw.TextStyle(
                        fontSize: 8,
                        color: PremiumDocumentTheme.accentSoft,
                      ),
                    ),
                    pw.Text(
                      '${_tr('period', l)}: ${_localize(period, l)}',
                      style: pw.TextStyle(
                        fontSize: 8,
                        color: PremiumDocumentTheme.accentSoft,
                      ),
                    ),
                    if (options.includeGeneratedAt)
                      pw.Text(
                        '${_tr('generatedAt', l)}: ${_dateTime(DateTime.now(), l)}',
                        style: pw.TextStyle(
                          fontSize: 8,
                          color: PremiumDocumentTheme.accentSoft,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          if (options.includeModuleDetails || options.includeSummary) ...[
            _section(_tr('moduleSummary', l), bold),
            _table(
              [_tr('indicator', l), _tr('value', l)],
              _moduleRows(
                report,
                module,
                l,
              ).map((e) => [e.$1, _exportValue(e.$2)]).toList(),
              direction,
            ),
            pw.SizedBox(height: 16),
          ],
          if (options.includeOperational) ...[
            _section(_tr('operationalIndicators', l), bold),
            _table(
              [_tr('indicator', l), _tr('value', l)],
              _operationalRows(
                report,
                l,
              ).map((e) => [e.$1, _exportValue(e.$2)]).toList(),
              direction,
            ),
            pw.SizedBox(height: 16),
          ],
          if (options.includeMonthly) ...[
            _section(_tr('monthlyPerformance', l), bold),
            _table(
              [
                _tr('month', l),
                _tr('sales', l),
                _tr('purchases', l),
                _tr('expenses', l),
              ],
              report.monthlyPoints
                  .map(
                    (p) => [
                      p.label,
                      _number(p.sales),
                      _number(p.purchases),
                      _number(p.expenses),
                    ],
                  )
                  .toList(),
              direction,
            ),
            pw.SizedBox(height: 16),
          ],
          if (options.includeExecutors) ...[
            _section(_tr('dataExecutors', l), bold),
            if (executionRows.isEmpty)
              pw.Text(_tr('noExecutors', l))
            else
              _table(
                [
                  _tr('user', l),
                  _tr('action', l),
                  _tr('entity', l),
                  _tr('date', l),
                ],
                executionRows
                    .map(
                      (e) => [
                        e.userName,
                        e.action,
                        e.entityType,
                        _dateTime(e.createdAt, l),
                      ],
                    )
                    .toList(),
                direction,
              ),
          ],
          for (final section in sections) ...[
            pw.SizedBox(height: 16),
            _section(_localize(section.title, l), bold),
            if (section.rows.isEmpty)
              pw.Text(_tr('noData', l))
            else
              ..._pdfSectionTables(
                _localizedSection(section, l),
                regular,
                bold,
                arabic,
              ),
          ],
        ],
      ),
    );
    return document.save();
  }

  ContextualReportSection _localizedSection(
    ContextualReportSection section,
    String language,
  ) => ContextualReportSection(
    key: section.key,
    title: _localize(section.title, language),
    columns: section.columns
        .map((value) => _localize(value, language))
        .toList(),
    rows: section.rows
        .map((row) => row.map((value) => _localize(value, language)).toList())
        .toList(),
  );

  String _localize(String value, String language) {
    final bilingual = value.split(' / ');
    final selected = bilingual.length == 2
        ? (language == 'ar' ? bilingual.last : bilingual.first)
        : value;
    return ReportFieldLocalizer.localize(
      _translateLegacy(selected.trim(), language),
      language,
    );
  }

  List<pw.Widget> _pdfSectionTables(
    ContextualReportSection section,
    pw.Font regular,
    pw.Font bold,
    bool arabic,
  ) => AdaptivePdfTable.build(
    headers: section.columns
        .map((value) => PdfTextSupport.sanitize(value))
        .toList(growable: false),
    rows: section.rows
        .map(
          (row) => row
              .map((value) => PdfTextSupport.sanitize(value))
              .toList(growable: false),
        )
        .toList(growable: false),
    regular: regular,
    bold: bold,
    arabic: arabic,
    headerColor: PremiumDocumentTheme.ink,
    alternateColor: PremiumDocumentTheme.accentSoft,
    maxColumnsPerGroup: 5,
    maxRowsPerChunk: 12,
  );

  pw.Widget _section(String text, pw.Font bold) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 7),
    padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 7),
    decoration: pw.BoxDecoration(
      color: PremiumDocumentTheme.accentSoft,
      border: pw.Border(
        left: pw.BorderSide(color: PremiumDocumentTheme.accent, width: 3),
      ),
      borderRadius: pw.BorderRadius.circular(5),
    ),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        font: bold,
        fontSize: 12,
        color: PremiumDocumentTheme.ink,
      ),
    ),
  );
  pw.Widget _table(
    List<String> headers,
    List<List<String>> data,
    pw.TextDirection direction,
  ) => pw.Directionality(
    textDirection: direction,
    child: pw.TableHelper.fromTextArray(
      headers: headers
          .map((value) => PdfTextSupport.sanitize(value, singleLine: true))
          .toList(growable: false),
      data: data
          .map(
            (row) => row
                .map(
                  (value) => PdfTextSupport.sanitize(value, singleLine: true),
                )
                .toList(growable: false),
          )
          .toList(growable: false),
      headerDecoration: pw.BoxDecoration(color: PremiumDocumentTheme.ink),
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
        fontSize: 8,
      ),
      cellStyle: const pw.TextStyle(fontSize: 7.2),
      oddRowDecoration: pw.BoxDecoration(color: PdfColor.fromHex('#F5F7F8')),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      border: pw.TableBorder.all(color: PdfColor.fromHex('#D6DEE3'), width: .4),
      cellAlignment: direction == pw.TextDirection.rtl
          ? pw.Alignment.centerRight
          : pw.Alignment.centerLeft,
    ),
  );

  TextCellValue _excelText(Object? value) =>
      TextCellValue(PdfTextSupport.sanitize(value, singleLine: true));

  Object? _excelExportValue(Object? value) {
    if (value is DateTime || value is num || value is bool || value == null) {
      return value;
    }
    return PdfTextSupport.sanitize(value, singleLine: true);
  }

  void _appendExcelTable(
    Sheet sheet, {
    required String title,
    required List<String> headers,
    required List<List<Object?>> rows,
    required String language,
  }) {
    final arabic = language == 'ar';
    ExcelWorkbookPresentation.prepareSheet(sheet, arabic: arabic);
    sheet.appendRow([_excelText(title)]);
    ExcelWorkbookPresentation.styleTitle(
      sheet,
      row: 0,
      columnCount: headers.isEmpty ? 1 : headers.length,
    );
    sheet.appendRow(headers.map(_excelText).toList(growable: false));
    ExcelWorkbookPresentation.styleHeader(sheet, 1, headers.length);
    for (final row in rows) {
      sheet.appendRow(
        List<CellValue>.generate(
          headers.length,
          (index) => ExcelWorkbookPresentation.typedValue(
            _excelExportValue(index < row.length ? row[index] : null),
            columnLabel: headers[index],
          ),
        ),
      );
    }
    ExcelWorkbookPresentation.styleDataRows(
      sheet,
      startRow: 2,
      rowCount: rows.length,
      columnCount: headers.length,
      arabic: arabic,
    );
    for (var index = 0; index < headers.length; index++) {
      final label = headers[index].toLowerCase();
      final wide =
          label.contains('description') ||
          label.contains('notes') ||
          label.contains('الوصف') ||
          label.contains('الملاحظات') ||
          label.contains('linked') ||
          label.contains('مرتبط');
      sheet.setColumnWidth(index, wide ? 30 : 19);
    }
  }

  List<List<Object?>> _relationIndexRows(
    List<ContextualReportSection> sections,
    String language,
  ) {
    final result = <List<Object?>>[];
    for (final section in sections) {
      if (section.columns.isEmpty || section.rows.isEmpty) continue;
      final localizedColumns = section.columns
          .map((value) => _localize(value, language))
          .toList(growable: false);
      final relationIndexes = <int>[];
      for (var index = 0; index < section.columns.length; index++) {
        final raw = section.columns[index]
            .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
            .toLowerCase();
        final localized = localizedColumns[index].toLowerCase();
        if (raw.contains('number') ||
            raw.contains('reference') ||
            raw.contains('code') ||
            raw.contains('opportunity') ||
            raw.contains('order') ||
            raw.contains('invoice') ||
            raw.contains('movement') ||
            raw.contains('payment') ||
            raw.contains('entry') ||
            raw.contains('vehicle') ||
            localized.contains('رقم') ||
            localized.contains('مرجع') ||
            localized.contains('رمز')) {
          relationIndexes.add(index);
        }
      }
      if (relationIndexes.length < 2) continue;
      final sourceIndex = relationIndexes.first;
      for (final row in section.rows) {
        if (sourceIndex >= row.length) continue;
        final sourceValue = row[sourceIndex].trim();
        if (sourceValue.isEmpty) continue;
        for (final relationIndex in relationIndexes.skip(1)) {
          if (relationIndex >= row.length) continue;
          final linkedValue = row[relationIndex].trim();
          if (linkedValue.isEmpty || linkedValue == sourceValue) continue;
          result.add(<Object?>[
            _localize(section.title, language),
            sourceValue,
            localizedColumns[relationIndex],
            linkedValue,
            _linkedModuleForColumn(section.columns[relationIndex], language),
          ]);
        }
      }
    }
    if (result.isEmpty) {
      result.add(<Object?>[
        language == 'ar' ? 'لا توجد روابط في الفترة' : 'No relations in period',
        '',
        '',
        '',
        '',
      ]);
    }
    return result;
  }

  String _linkedModuleForColumn(String column, String language) {
    final normalized = column
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .toLowerCase();
    String key;
    if (normalized.contains('opportunity')) {
      key = 'module_opportunities';
    } else if (normalized.contains('purchase')) {
      key = 'module_purchases';
    } else if (normalized.contains('sales') || normalized.contains('order')) {
      key = 'module_sales';
    } else if (normalized.contains('invoice')) {
      key = 'module_finance';
    } else if (normalized.contains('movement') ||
        normalized.contains('warehouse') ||
        normalized.contains('transfer')) {
      key = 'module_inventory';
    } else if (normalized.contains('payment') ||
        normalized.contains('entry') ||
        normalized.contains('voucher')) {
      key = 'module_accounting';
    } else if (normalized.contains('vehicle')) {
      key = 'module_cars';
    } else {
      key = 'module_operations';
    }
    return _tr(key, language);
  }

  List<(String, Object)> _moduleRows(ReportModel r, String m, String l) =>
      switch (m) {
        'cars' => [
          (_tr('totalCars', l), r.totalCars.toDouble()),
          (_tr('availableCars', l), r.availableCars.toDouble()),
          (_tr('reservedCars', l), r.reservedCars.toDouble()),
          (_tr('soldCars', l), r.soldCars.toDouble()),
        ],
        'products' => [
          (_tr('inventoryItems', l), r.totalInventoryItems.toDouble()),
          (_tr('inventoryValue', l), _currencyMap(r.inventoryValueByCurrency)),
        ],
        'warehouses' => [
          (_tr('inventoryItems', l), r.totalInventoryItems.toDouble()),
          (_tr('inventoryValue', l), _currencyMap(r.inventoryValueByCurrency)),
        ],
        'customers' => [
          (_tr('customers', l), r.totalCustomers.toDouble()),
          (_tr('receivables', l), _currencyMap(r.totalReceivablesByCurrency)),
        ],
        'suppliers' => [
          (_tr('suppliers', l), r.totalSuppliers.toDouble()),
          (_tr('payables', l), _currencyMap(r.totalPurchaseDebtByCurrency)),
        ],
        'payments' => [
          (_tr('paidSales', l), _currencyMap(r.totalPaidSalesByCurrency)),
          (_tr('receivables', l), _currencyMap(r.totalReceivablesByCurrency)),
          (_tr('payables', l), _currencyMap(r.totalPurchaseDebtByCurrency)),
        ],
        'accounting' => [
          (_tr('totalSales', l), _currencyMap(r.totalSalesByCurrency)),
          (_tr('totalPurchases', l), _currencyMap(r.totalPurchasesByCurrency)),
          (_tr('expenses', l), _currencyMap(r.totalExpensesByCurrency)),
          (_tr('netProfit', l), _currencyMap(r.netProfitByCurrency)),
        ],
        'sales' => [
          (_tr('totalSales', l), _currencyMap(r.totalSalesByCurrency)),
          (_tr('paidSales', l), _currencyMap(r.totalPaidSalesByCurrency)),
          (_tr('receivables', l), _currencyMap(r.totalReceivablesByCurrency)),
          (_tr('netProfit', l), _currencyMap(r.netProfitByCurrency)),
        ],
        'purchases' => [
          (_tr('totalPurchases', l), _currencyMap(r.totalPurchasesByCurrency)),
          (_tr('purchaseDebt', l), _currencyMap(r.totalPurchaseDebtByCurrency)),
          (_tr('inventoryValue', l), _currencyMap(r.inventoryValueByCurrency)),
          (_tr('expenses', l), _currencyMap(r.totalExpensesByCurrency)),
        ],
        'inventory' => [
          (_tr('inventoryItems', l), r.totalInventoryItems.toDouble()),
          (_tr('inventoryValue', l), _currencyMap(r.inventoryValueByCurrency)),
          (_tr('totalPurchases', l), _currencyMap(r.totalPurchasesByCurrency)),
          (_tr('totalSales', l), _currencyMap(r.totalSalesByCurrency)),
        ],
        'finance' => [
          (_tr('cashUsd', l), r.cashBalanceUsd),
          (_tr('cashIqd', l), r.cashBalanceIqd),
          (_tr('receivables', l), _currencyMap(r.totalReceivablesByCurrency)),
          (_tr('payables', l), _currencyMap(r.totalPurchaseDebtByCurrency)),
          (_tr('netProfit', l), _currencyMap(r.netProfitByCurrency)),
        ],
        'partners' => [
          (_tr('customers', l), r.totalCustomers.toDouble()),
          (_tr('suppliers', l), r.totalSuppliers.toDouble()),
          (_tr('activeReservations', l), r.activeReservations.toDouble()),
          (_tr('overdueInstallments', l), r.overdueInstallments.toDouble()),
        ],
        'operations' => _operationalRows(r, l),
        _ => [
          (_tr('totalSales', l), _currencyMap(r.totalSalesByCurrency)),
          (_tr('totalPurchases', l), _currencyMap(r.totalPurchasesByCurrency)),
          (_tr('expenses', l), _currencyMap(r.totalExpensesByCurrency)),
          (_tr('inventoryValue', l), _currencyMap(r.inventoryValueByCurrency)),
          (_tr('cashUsd', l), r.cashBalanceUsd),
          (_tr('cashIqd', l), r.cashBalanceIqd),
          (_tr('netProfit', l), _currencyMap(r.netProfitByCurrency)),
        ],
      };
  List<(String, double)> _operationalRows(ReportModel r, String l) => [
    (_tr('totalCars', l), r.totalCars.toDouble()),
    (_tr('availableCars', l), r.availableCars.toDouble()),
    (_tr('reservedCars', l), r.reservedCars.toDouble()),
    (_tr('soldCars', l), r.soldCars.toDouble()),
    (_tr('customers', l), r.totalCustomers.toDouble()),
    (_tr('suppliers', l), r.totalSuppliers.toDouble()),
    (_tr('inventoryItems', l), r.totalInventoryItems.toDouble()),
    (_tr('activeReservations', l), r.activeReservations.toDouble()),
    (_tr('overdueInstallments', l), r.overdueInstallments.toDouble()),
  ];

  String _moduleName(String m, String l) => _tr('module_$m', l);
  String _safeSheetTitle(String title, String fallback) {
    final cleaned = title.replaceAll(RegExp(r'[\\/*?:\[\]]'), ' ').trim();
    final value = cleaned.isEmpty ? fallback : cleaned;
    return value.length > 31 ? value.substring(0, 31) : value;
  }

  String _uniqueSheetTitle(String title, String fallback, Set<String> used) {
    final base = _safeSheetTitle(title, fallback);
    if (!used.contains(base)) return base;
    var index = 2;
    while (true) {
      final suffix = ' ($index)';
      final maxBase = 31 - suffix.length;
      final candidate =
          '${base.substring(0, math.min(base.length, maxBase))}$suffix';
      if (!used.contains(candidate)) return candidate;
      index++;
    }
  }

  String _sheetName(String key, String l) {
    final n = _tr(key, l);
    return n.length > 31 ? n.substring(0, 31) : n;
  }

  Future<_ReportBranding> _loadBranding(String language) async {
    final companyId = CloudTenantContext.instance.companyUuid;
    if (companyId == null || companyId.isEmpty) {
      throw StateError('لم يتم تحديد شركة سحابية.');
    }
    Map<String, String> values = const <String, String>{};
    try {
      final result = await Supabase.instance.client
          .rpc('erp_get_cloud_company_settings')
          .timeout(const Duration(seconds: 12));
      values = Map<String, Object?>.from(
        result as Map,
      ).map((key, value) => MapEntry(key, value?.toString() ?? ''));
    } catch (error, stackTrace) {
      // Branding must never block operational printing or exporting. The
      // document falls back to the built-in company identity when the optional
      // settings RPC is unavailable or the connection is temporarily slow.
      AppLogger.debug(
        'Report branding fallback activated: $error\n$stackTrace',
      );
    }
    final logo = await _loadBundledLogo();
    final arabic = language == 'ar';
    return _ReportBranding(
      companyName: arabic
          ? (values['company_name']?.trim().isNotEmpty == true
                ? values['company_name']!
                : 'شركة خط الجودة')
          : (values['company_name_en']?.trim().isNotEmpty == true
                ? values['company_name_en']!
                : 'Quality Line'),
      logo: logo,
      details: [
        values['address'],
        values['phone'],
        values['tax_number'],
      ].where((value) => value?.trim().isNotEmpty == true).join(' • '),
    );
  }

  String _dateTime(DateTime value, String language) {
    final local = value.toLocal();
    final date =
        '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return language == 'ar' ? '$date، $time' : '$date $time';
  }

  String _fileName(String module, String l) =>
      'quality_line_${module}_${DateTime.now().millisecondsSinceEpoch}_$l';
  String _exportValue(Object value) =>
      value is num ? _number(value.toDouble()) : value.toString();

  String _currencyMap(Map<String, double> values) {
    if (values.isEmpty) return '—';
    final keys = values.keys.toList()..sort();
    return keys.map((key) => '${_number(values[key] ?? 0)} $key').join(' • ');
  }

  String _number(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  String _escapeCsv(Object? value) {
    var text = PdfTextSupport.sanitize(value, singleLine: true);
    if (text.isNotEmpty && '=+-@\t\r'.contains(text[0])) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }

  String _translateLegacy(String value, String language) {
    const pairs = <String, String>{
      'تقرير خط الجودة': 'Quality Line Report',
      'جميع الفترات': 'All periods',
      'رقم الأمر': 'Order number',
      'رقم الفاتورة': 'Invoice number',
      'الحالة': 'Status',
      'العملة': 'Currency',
      'سعر الصرف': 'Exchange rate',
      'الإجمالي': 'Total',
      'المبلغ': 'Amount',
      'الوصف': 'Description',
      'الكمية': 'Quantity',
      'سعر الوحدة': 'Unit price',
      'التاريخ': 'Date',
      'المخزن': 'Warehouse',
      'العميل': 'Customer',
      'المورد': 'Supplier',
      'السيارة': 'Vehicle',
      'المنتج': 'Product',
      'نوع التسوية': 'Settlement mode',
      'فرق الصرف': 'Exchange difference',
      'البيانات الخام': 'Raw data',
      'rawData': 'Raw data',
      'itemDetails': 'Item details',
      'payload': 'Payload',
      'createdAt': 'Created at',
      'updatedAt': 'Updated at',
      'fromWarehouse': 'From warehouse',
      'toWarehouse': 'To warehouse',
      'availableQuantity': 'Available quantity',
      'reservedQuantity': 'Reserved quantity',
      'stockValue': 'Stock value',
    };
    if (language == 'en') return pairs[value] ?? value;
    for (final entry in pairs.entries) {
      if (entry.value == value) return entry.key;
    }
    return value;
  }

  String _tr(String key, String l) {
    const ar = <String, String>{
      'summary': 'الملخص',
      'operations': 'المؤشرات التشغيلية',
      'monthly': 'الأداء الشهري',
      'executors': 'منفذو الإدخال',
      'module': 'المودل',
      'period': 'الفترة',
      'generatedAt': 'تاريخ إنشاء التقرير',
      'indicator': 'المؤشر',
      'value': 'القيمة',
      'operationalIndicator': 'المؤشر التشغيلي',
      'month': 'الشهر',
      'sales': 'المبيعات',
      'purchases': 'المشتريات',
      'expenses': 'المصاريف',
      'user': 'المستخدم',
      'action': 'الإجراء',
      'entity': 'الكيان',
      'date': 'التاريخ',
      'moduleSummary': 'ملخص المودل',
      'operationalIndicators': 'المؤشرات التشغيلية',
      'monthlyPerformance': 'الأداء الشهري',
      'dataExecutors': 'منفذو إدخال البيانات',
      'noExecutors': 'لا توجد عمليات مسجلة ضمن هذا المودل.',
      'noData': 'لا توجد بيانات في هذا القسم.',
      'excelError': 'تعذر إنشاء ملف Excel.',
      'totalCars': 'إجمالي السيارات',
      'availableCars': 'السيارات المتاحة',
      'reservedCars': 'السيارات قيد البيع',
      'soldCars': 'السيارات المباعة',
      'totalSales': 'إجمالي المبيعات',
      'paidSales': 'المبيعات المحصلة',
      'receivables': 'الذمم المدينة',
      'netProfit': 'صافي الربح',
      'totalPurchases': 'إجمالي المشتريات',
      'purchaseDebt': 'ذمم الموردين',
      'inventoryValue': 'قيمة المخزون',
      'inventoryItems': 'عدد مواد المخزون',
      'cashUsd': 'رصيد الصناديق بالدولار',
      'cashIqd': 'رصيد الصناديق بالدينار',
      'payables': 'الذمم الدائنة',
      'customers': 'العملاء',
      'suppliers': 'الموردون',
      'activeReservations': 'الحجوزات النشطة',
      'overdueInstallments': 'الأقساط المتأخرة',
      'module_overview': 'نظرة عامة',
      'module_cars': 'السيارات',
      'module_products': 'المنتجات',
      'module_warehouses': 'المخازن',
      'module_customers': 'العملاء',
      'module_customer_service': 'خدمة العملاء',
      'module_opportunities': 'الفرص التجارية',
      'module_suppliers': 'الموردون',
      'module_payments': 'الدفعات',
      'module_accounting': 'المحاسبة',
      'module_sales': 'المبيعات',
      'module_purchases': 'المشتريات',
      'module_inventory': 'المخزون',
      'module_finance': 'المالية',
      'module_partners': 'الشركاء التجاريون',
      'module_operations': 'التشغيل',
    };
    const en = <String, String>{
      'summary': 'Summary',
      'operations': 'Operational indicators',
      'monthly': 'Monthly performance',
      'executors': 'Data entry users',
      'module': 'Module',
      'period': 'Period',
      'generatedAt': 'Generated at',
      'indicator': 'Indicator',
      'value': 'Value',
      'operationalIndicator': 'Operational indicator',
      'month': 'Month',
      'sales': 'Sales',
      'purchases': 'Purchases',
      'expenses': 'Expenses',
      'user': 'User',
      'action': 'Action',
      'entity': 'Entity',
      'date': 'Date',
      'moduleSummary': 'Module summary',
      'operationalIndicators': 'Operational indicators',
      'monthlyPerformance': 'Monthly performance',
      'dataExecutors': 'Data entry users',
      'noExecutors': 'No recorded operations for this module.',
      'noData': 'No data in this section.',
      'excelError': 'Unable to create Excel file.',
      'totalCars': 'Total vehicles',
      'availableCars': 'Available vehicles',
      'reservedCars': 'Reserved vehicles',
      'soldCars': 'Sold vehicles',
      'totalSales': 'Total sales',
      'paidSales': 'Collected sales',
      'receivables': 'Accounts receivable',
      'netProfit': 'Net profit',
      'totalPurchases': 'Total purchases',
      'purchaseDebt': 'Supplier payables',
      'inventoryValue': 'Inventory value',
      'inventoryItems': 'Inventory items',
      'cashUsd': 'Cash balance USD',
      'cashIqd': 'Cash balance IQD',
      'payables': 'Accounts payable',
      'customers': 'Customers',
      'suppliers': 'Suppliers',
      'activeReservations': 'Active reservations',
      'overdueInstallments': 'Overdue installments',
      'module_overview': 'Overview',
      'module_cars': 'Vehicles',
      'module_products': 'Products',
      'module_warehouses': 'Warehouses',
      'module_customers': 'Customers',
      'module_customer_service': 'Customer Service',
      'module_opportunities': 'Opportunities',
      'module_suppliers': 'Suppliers',
      'module_payments': 'Payments',
      'module_accounting': 'Accounting',
      'module_sales': 'Sales',
      'module_purchases': 'Purchases',
      'module_inventory': 'Inventory',
      'module_finance': 'Finance',
      'module_partners': 'Business partners',
      'module_operations': 'Operations',
    };
    return (l == 'en' ? en : ar)[key] ?? key;
  }
}

class _ReportBranding {
  const _ReportBranding({
    required this.companyName,
    required this.logo,
    required this.details,
  });
  final String companyName;
  final pw.MemoryImage? logo;
  final String details;
}
