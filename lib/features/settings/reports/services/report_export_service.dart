import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'package:quality_line_erp/core/exporting/binary_download_service.dart';
import 'package:quality_line_erp/core/exporting/excel_download_service.dart';
import 'package:quality_line_erp/core/exporting/excel_workbook_presentation.dart';
import 'package:quality_line_erp/core/exporting/export_document.dart';
import 'package:quality_line_erp/core/exporting/pdf_export_service.dart';
import 'package:quality_line_erp/core/exporting/pdf_print_service.dart';
import 'package:quality_line_erp/core/exporting/xlsx_integrity.dart';
import 'package:quality_line_erp/core/printing/pdf_text_support.dart';
import 'package:quality_line_erp/features/settings/reports/models/contextual_report_section.dart';
import 'package:quality_line_erp/features/settings/reports/models/execution_audit_row.dart';
import 'package:quality_line_erp/features/settings/reports/models/report_export_options.dart';
import 'package:quality_line_erp/features/settings/reports/models/report_model.dart';

import 'contextual_report_customizer.dart';
import 'report_field_localizer.dart';

/// Authoritative bilingual export pipeline for the Reports module.
/// PDF, Excel and CSV use the selected report language, the same filtered rows,
/// and the shared Quality Line document identity.
class ReportExportService {
  const ReportExportService();

  String _language(ReportExportOptions options) =>
      PdfTextSupport.canonicalPdfLanguage(options.language);

  Future<void> exportExcel(
    ReportModel report, {
    String module = 'overview',
    List<ExecutionAuditRow> executionRows = const [],
    ReportExportOptions options = const ReportExportOptions(),
    String period = 'جميع الفترات',
    List<ContextualReportSection> sections = const [],
  }) async {
    final language = _language(options);
    final arabic = language == 'ar';
    final customized = const ContextualReportCustomizer().apply(
      sections,
      options,
    );
    final book = Excel.createExcel();
    final initialSheet = book.getDefaultSheet();
    final usedNames = <String>{};

    final profileName = _uniqueSheetName(
      arabic ? 'تعريف الملف' : 'Workbook profile',
      usedNames,
    );
    usedNames.add(profileName);
    final profile = book[profileName];
    if (initialSheet != null && initialSheet != profileName)
      book.delete(initialSheet);
    ExcelWorkbookPresentation.prepareSheet(profile, arabic: arabic);
    profile.appendRow([TextCellValue(_localized(options.title, language))]);
    ExcelWorkbookPresentation.styleTitle(profile, row: 0, columnCount: 2);
    final metadata = <(String, Object?)>[
      (_t('module', language), _moduleName(module, language)),
      (_t('period', language), _localized(period, language)),
      (
        arabic ? 'لغة الملف' : 'Workbook language',
        arabic ? 'العربية' : 'English',
      ),
      (arabic ? 'سياق العملة' : 'Currency context', 'USD / IQD'),
      (arabic ? 'إصدار بنية الملف' : 'Workbook schema version', '18.9.12'),
      if (options.includeGeneratedAt)
        (_t('generatedAt', language), DateTime.now()),
    ];
    for (var index = 0; index < metadata.length; index++) {
      final row = metadata[index];
      profile.appendRow([
        TextCellValue(row.$1),
        ExcelWorkbookPresentation.typedValue(row.$2, columnLabel: row.$1),
      ]);
      profile
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: index + 1))
          .cellStyle = ExcelWorkbookPresentation
          .metadataLabelStyle;
      profile
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: index + 1))
          .cellStyle = ExcelWorkbookPresentation
          .metadataValueStyle;
    }
    profile.setColumnWidth(0, 26);
    profile.setColumnWidth(1, 36);

    if (options.includeSummary || options.includeModuleDetails) {
      _appendSheet(
        book,
        usedNames: usedNames,
        preferredName: _t('summary', language),
        title: _t('moduleSummary', language),
        headers: [_t('indicator', language), _t('value', language)],
        rows: _moduleRows(
          report,
          module,
          language,
        ).map((entry) => <Object?>[entry.$1, entry.$2]).toList(growable: false),
        arabic: arabic,
      );
    }
    if (options.includeOperational) {
      _appendSheet(
        book,
        usedNames: usedNames,
        preferredName: _t('operations', language),
        title: _t('operationalIndicators', language),
        headers: [_t('indicator', language), _t('value', language)],
        rows: _operationalRows(
          report,
          language,
        ).map((entry) => <Object?>[entry.$1, entry.$2]).toList(growable: false),
        arabic: arabic,
      );
    }
    if (options.includeMonthly) {
      _appendSheet(
        book,
        usedNames: usedNames,
        preferredName: _t('monthly', language),
        title: _t('monthlyPerformance', language),
        headers: [
          _t('month', language),
          _t('sales', language),
          _t('purchases', language),
          _t('expenses', language),
        ],
        rows: report.monthlyPoints
            .map(
              (point) => <Object?>[
                _localized(point.label, language),
                point.sales,
                point.purchases,
                point.expenses,
              ],
            )
            .toList(growable: false),
        arabic: arabic,
      );
    }
    if (options.includeExecutors) {
      _appendSheet(
        book,
        usedNames: usedNames,
        preferredName: _t('executors', language),
        title: _t('dataExecutors', language),
        headers: [
          _t('user', language),
          _t('action', language),
          _t('entity', language),
          _t('date', language),
        ],
        rows: executionRows
            .map(
              (row) => <Object?>[
                row.userName,
                _localized(row.action, language),
                _localized(row.entityType, language),
                row.createdAt,
              ],
            )
            .toList(growable: false),
        arabic: arabic,
      );
    }
    for (final section in customized) {
      _appendSheet(
        book,
        usedNames: usedNames,
        preferredName: _localized(section.title, language),
        title: _localized(section.title, language),
        headers: section.columns
            .map((column) => ReportFieldLocalizer.localize(column, language))
            .toList(growable: false),
        rows: section.rows
            .map((row) => <Object?>[...row])
            .toList(growable: false),
        arabic: arabic,
      );
    }

    final relationRows = _relationIndexRows(customized, language);
    _appendSheet(
      book,
      usedNames: usedNames,
      preferredName: arabic ? 'دليل الربط' : 'Relation index',
      title: arabic
          ? 'الربط بين الوحدات والمستندات'
          : 'Cross-module document relations',
      headers: arabic
          ? const [
              'الوحدة المصدرية',
              'السجل المصدر',
              'نوع الارتباط',
              'رقم السجل المرتبط',
              'الوحدة المرتبطة',
            ]
          : const [
              'Source module',
              'Source record',
              'Relation type',
              'Linked record number',
              'Linked module',
            ],
      rows: relationRows,
      arabic: arabic,
    );

    if (!book.setDefaultSheet(profileName))
      throw StateError(_t('excelError', language));
    final encoded = book.encode();
    if (encoded == null) throw StateError(_t('excelError', language));
    await ExcelDownloadService.save(
      fileName: '${fileNameFor(module, language)}.xlsx',
      bytes: XlsxIntegrity.finalize(encoded),
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
    final language = _language(options);
    final customized = const ContextualReportCustomizer().apply(
      sections,
      options,
    );
    final dataRows = _flatRows(
      report,
      module: module,
      executionRows: executionRows,
      options: options,
      sections: customized,
      language: language,
    );
    final rows = <List<Object?>>[
      [
        _t('section', language),
        _t('field', language),
        _t('value', language),
        _t('details', language),
      ],
      ...dataRows,
    ];
    final csv = rows.map((row) => row.map(_escapeCsv).join(',')).join('\r\n');
    await BinaryDownloadService.save(
      fileName: '${fileNameFor(module, language)}.csv',
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
    final language = _language(options);
    final bytes = await buildPdf(
      report,
      module: module,
      executionRows: executionRows,
      options: options,
      period: period,
      sections: sections,
    );
    await PdfPrintService.print(
      fileName: '${fileNameFor(module, language)}.pdf',
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
    final language = _language(options);
    final bytes = await buildPdf(
      report,
      module: module,
      executionRows: executionRows,
      options: options,
      period: period,
      sections: sections,
    );
    await BinaryDownloadService.save(
      fileName: '${fileNameFor(module, language)}.pdf',
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
    final language = _language(options);
    final customized = const ContextualReportCustomizer().apply(
      sections,
      options,
    );
    final rows = _flatRows(
      report,
      module: module,
      executionRows: executionRows,
      options: options,
      sections: customized,
      language: language,
    );
    final document = ExportDocument(
      title: _localized(options.title, language),
      subtitle:
          '${_moduleName(module, language)} — ${_localized(period, language)}',
      language: language,
      currency: 'USD / IQD',
      generatedAt: DateTime.now(),
      metadata: {
        _t('module', language): _moduleName(module, language),
        _t('period', language): _localized(period, language),
        _t('rows', language): rows.length,
      },
      columns: [
        ExportColumn(key: 'section', label: _t('section', language)),
        ExportColumn(key: 'field', label: _t('field', language)),
        ExportColumn(key: 'value', label: _t('value', language)),
        ExportColumn(key: 'details', label: _t('details', language)),
      ],
      rows: rows,
    );
    return PdfExportService().build(
      document,
      pageFormat: options.landscape
          ? ExportPageFormat.a4Landscape
          : ExportPageFormat.a4Portrait,
    );
  }

  List<List<Object?>> _flatRows(
    ReportModel report, {
    required String module,
    required List<ExecutionAuditRow> executionRows,
    required ReportExportOptions options,
    required List<ContextualReportSection> sections,
    required String language,
  }) {
    final rows = <List<Object?>>[];
    void add(
      String section,
      Object? field,
      Object? value, [
      Object? details = '',
    ]) {
      rows.add([section, field, value, details]);
    }

    if (options.includeSummary || options.includeModuleDetails) {
      for (final item in _moduleRows(report, module, language)) {
        add(_t('moduleSummary', language), item.$1, item.$2);
      }
    }
    if (options.includeOperational) {
      for (final item in _operationalRows(report, language)) {
        add(_t('operationalIndicators', language), item.$1, item.$2);
      }
    }
    if (options.includeMonthly) {
      for (final point in report.monthlyPoints) {
        add(
          _t('monthlyPerformance', language),
          _localized(point.label, language),
          '${_t('sales', language)}: ${_number(point.sales)}',
          '${_t('purchases', language)}: ${_number(point.purchases)} • ${_t('expenses', language)}: ${_number(point.expenses)}',
        );
      }
    }
    if (options.includeExecutors) {
      for (final execution in executionRows) {
        add(
          _t('dataExecutors', language),
          execution.userName,
          _localized(execution.action, language),
          '${_localized(execution.entityType, language)} • ${_dateTime(execution.createdAt)}',
        );
      }
    }
    for (final section in sections) {
      final title = _localized(section.title, language);
      final headers = section.columns
          .map((column) => ReportFieldLocalizer.localize(column, language))
          .toList(growable: false);
      if (section.rows.isEmpty) {
        add(title, _t('noData', language), '', '');
        continue;
      }
      for (final rawRow in section.rows) {
        final values = List<String>.generate(
          headers.length,
          (index) => index < rawRow.length ? rawRow[index] : '',
          growable: false,
        );
        final field = headers.isEmpty ? '' : '${headers[0]}: ${values[0]}';
        final value = headers.length < 2 ? '' : '${headers[1]}: ${values[1]}';
        final details = <String>[
          for (var index = 2; index < headers.length; index++)
            if (values[index].trim().isNotEmpty)
              '${headers[index]}: ${values[index]}',
        ].join(' • ');
        add(title, field, value, details);
      }
    }
    if (rows.isEmpty)
      add(_t('report', language), _t('noData', language), '', '');
    return rows;
  }

  void _appendSheet(
    Excel book, {
    required Set<String> usedNames,
    required String preferredName,
    required String title,
    required List<String> headers,
    required List<List<Object?>> rows,
    required bool arabic,
  }) {
    final name = _uniqueSheetName(preferredName, usedNames);
    usedNames.add(name);
    final sheet = book[name];
    ExcelWorkbookPresentation.prepareSheet(sheet, arabic: arabic);
    sheet.appendRow([TextCellValue(title)]);
    ExcelWorkbookPresentation.styleTitle(
      sheet,
      row: 0,
      columnCount: headers.isEmpty ? 1 : headers.length,
    );
    sheet.appendRow(headers.map(TextCellValue.new).toList(growable: false));
    ExcelWorkbookPresentation.styleHeader(sheet, 1, headers.length);
    for (final row in rows) {
      sheet.appendRow(
        List<CellValue>.generate(
          headers.length,
          (index) => ExcelWorkbookPresentation.typedValue(
            index < row.length ? row[index] : null,
            columnLabel: headers[index],
          ),
          growable: false,
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
      sheet.setColumnWidth(index, index == 0 ? 24 : 20);
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
          .map((value) => ReportFieldLocalizer.localize(value, language))
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
          result.add([
            _localized(section.title, language),
            sourceValue,
            localizedColumns[relationIndex],
            linkedValue,
            _linkedModuleForColumn(section.columns[relationIndex], language),
          ]);
        }
      }
    }
    if (result.isEmpty) {
      result.add([
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
    final key = normalized.contains('opportunity')
        ? 'module_opportunities'
        : normalized.contains('purchase')
        ? 'module_purchases'
        : normalized.contains('sales') || normalized.contains('order')
        ? 'module_sales'
        : normalized.contains('invoice')
        ? 'module_finance'
        : normalized.contains('movement') ||
              normalized.contains('warehouse') ||
              normalized.contains('transfer')
        ? 'module_inventory'
        : normalized.contains('payment') ||
              normalized.contains('entry') ||
              normalized.contains('voucher')
        ? 'module_accounting'
        : normalized.contains('vehicle')
        ? 'module_cars'
        : 'module_operations';
    return _t(key, language);
  }

  List<(String, Object)> _moduleRows(
    ReportModel r,
    String module,
    String language,
  ) => switch (module) {
    'cars' => [
      (_t('totalCars', language), r.totalCars),
      (_t('availableCars', language), r.availableCars),
      (_t('reservedCars', language), r.reservedCars),
      (_t('soldCars', language), r.soldCars),
    ],
    'products' || 'warehouses' || 'inventory' => [
      (_t('inventoryItems', language), r.totalInventoryItems),
      (
        _t('inventoryValue', language),
        _currencyMap(r.inventoryValueByCurrency),
      ),
      (
        _t('totalPurchases', language),
        _currencyMap(r.totalPurchasesByCurrency),
      ),
      (_t('totalSales', language), _currencyMap(r.totalSalesByCurrency)),
    ],
    'customers' => [
      (_t('customers', language), r.totalCustomers),
      (_t('receivables', language), _currencyMap(r.totalReceivablesByCurrency)),
    ],
    'suppliers' => [
      (_t('suppliers', language), r.totalSuppliers),
      (_t('payables', language), _currencyMap(r.totalPurchaseDebtByCurrency)),
    ],
    'payments' => [
      (_t('paidSales', language), _currencyMap(r.totalPaidSalesByCurrency)),
      (_t('receivables', language), _currencyMap(r.totalReceivablesByCurrency)),
      (_t('payables', language), _currencyMap(r.totalPurchaseDebtByCurrency)),
    ],
    'sales' => [
      (_t('totalSales', language), _currencyMap(r.totalSalesByCurrency)),
      (_t('paidSales', language), _currencyMap(r.totalPaidSalesByCurrency)),
      (_t('receivables', language), _currencyMap(r.totalReceivablesByCurrency)),
      (_t('netProfit', language), _currencyMap(r.netProfitByCurrency)),
    ],
    'purchases' => [
      (
        _t('totalPurchases', language),
        _currencyMap(r.totalPurchasesByCurrency),
      ),
      (_t('payables', language), _currencyMap(r.totalPurchaseDebtByCurrency)),
      (
        _t('inventoryValue', language),
        _currencyMap(r.inventoryValueByCurrency),
      ),
      (_t('expenses', language), _currencyMap(r.totalExpensesByCurrency)),
    ],
    'finance' || 'accounting' => [
      (_t('cashUsd', language), r.cashBalanceUsd),
      (_t('cashIqd', language), r.cashBalanceIqd),
      (_t('receivables', language), _currencyMap(r.totalReceivablesByCurrency)),
      (_t('payables', language), _currencyMap(r.totalPurchaseDebtByCurrency)),
      (_t('netProfit', language), _currencyMap(r.netProfitByCurrency)),
    ],
    'partners' => [
      (_t('customers', language), r.totalCustomers),
      (_t('suppliers', language), r.totalSuppliers),
      (_t('activeReservations', language), r.activeReservations),
      (_t('overdueInstallments', language), r.overdueInstallments),
    ],
    'operations' => _operationalRows(r, language),
    _ => [
      (_t('totalSales', language), _currencyMap(r.totalSalesByCurrency)),
      (
        _t('totalPurchases', language),
        _currencyMap(r.totalPurchasesByCurrency),
      ),
      (_t('expenses', language), _currencyMap(r.totalExpensesByCurrency)),
      (
        _t('inventoryValue', language),
        _currencyMap(r.inventoryValueByCurrency),
      ),
      (_t('cashUsd', language), r.cashBalanceUsd),
      (_t('cashIqd', language), r.cashBalanceIqd),
      (_t('netProfit', language), _currencyMap(r.netProfitByCurrency)),
    ],
  };

  List<(String, Object)> _operationalRows(ReportModel r, String language) => [
    (_t('totalCars', language), r.totalCars),
    (_t('availableCars', language), r.availableCars),
    (_t('reservedCars', language), r.reservedCars),
    (_t('soldCars', language), r.soldCars),
    (_t('customers', language), r.totalCustomers),
    (_t('suppliers', language), r.totalSuppliers),
    (_t('inventoryItems', language), r.totalInventoryItems),
    (_t('activeReservations', language), r.activeReservations),
    (_t('overdueInstallments', language), r.overdueInstallments),
  ];

  String fileNameFor(String module, String language) {
    final canonical = PdfTextSupport.canonicalPdfLanguage(language);
    final safeModule = module.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return 'quality_line_${safeModule}_${DateTime.now().millisecondsSinceEpoch}_$canonical';
  }

  String _moduleName(String module, String language) =>
      _t('module_$module', language);

  String _localized(Object? value, String language) {
    final raw = '${value ?? ''}'.trim();
    if (raw == 'تقرير خط الجودة')
      return language == 'ar' ? raw : 'Quality Line Report';
    if (raw == 'Quality Line Report')
      return language == 'ar' ? 'تقرير خط الجودة' : raw;
    if (raw == 'جميع الفترات') return language == 'ar' ? raw : 'All periods';
    return ReportFieldLocalizer.localize(raw, language);
  }

  String _currencyMap(Map<String, double> values) {
    if (values.isEmpty) return '—';
    final keys = values.keys.toList()..sort();
    return keys.map((key) => '${_number(values[key] ?? 0)} $key').join(' • ');
  }

  String _number(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);

  String _dateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _uniqueSheetName(String raw, Set<String> used) {
    var base = PdfTextSupport.sanitize(
      raw,
      singleLine: true,
    ).replaceAll(RegExp(r'[\\/*?:\[\]]'), ' ').trim();
    if (base.isEmpty) base = 'Report';
    if (base.length > 31) base = base.substring(0, 31);
    if (!used.contains(base)) return base;
    var index = 2;
    while (true) {
      final suffix = ' ($index)';
      final maxHead = (31 - suffix.length).clamp(1, base.length).toInt();
      final candidate = '${base.substring(0, maxHead)}$suffix';
      if (!used.contains(candidate)) return candidate;
      index++;
    }
  }

  String _escapeCsv(Object? value) {
    var text = PdfTextSupport.sanitize(value, singleLine: true);
    if (text.isNotEmpty && '=+-@\t\r'.contains(text[0])) text = "'$text";
    return '"${text.replaceAll('"', '""')}"';
  }

  String _t(String key, String language) {
    const ar = <String, String>{
      'summary': 'الملخص',
      'operations': 'التشغيل',
      'monthly': 'الأداء الشهري',
      'executors': 'منفذو الإدخال',
      'module': 'الوحدة',
      'period': 'الفترة',
      'generatedAt': 'تاريخ الإنشاء',
      'indicator': 'المؤشر',
      'value': 'القيمة',
      'moduleSummary': 'ملخص الوحدة',
      'operationalIndicators': 'المؤشرات التشغيلية',
      'monthlyPerformance': 'الأداء الشهري',
      'dataExecutors': 'منفذو إدخال البيانات',
      'month': 'الشهر',
      'sales': 'المبيعات',
      'purchases': 'المشتريات',
      'expenses': 'المصاريف',
      'user': 'المستخدم',
      'action': 'الإجراء',
      'entity': 'نوع السجل',
      'date': 'التاريخ',
      'section': 'القسم',
      'field': 'الحقل',
      'details': 'التفاصيل',
      'rows': 'عدد السجلات',
      'report': 'التقرير',
      'noData': 'لا توجد بيانات',
      'excelError': 'تعذر إنشاء ملف Excel.',
      'totalCars': 'إجمالي السيارات',
      'availableCars': 'السيارات المتاحة',
      'reservedCars': 'السيارات قيد البيع',
      'soldCars': 'السيارات المباعة',
      'inventoryItems': 'عدد مواد المخزون',
      'inventoryValue': 'قيمة المخزون',
      'totalSales': 'إجمالي المبيعات',
      'paidSales': 'المبيعات المحصلة',
      'receivables': 'الذمم المدينة',
      'totalPurchases': 'إجمالي المشتريات',
      'payables': 'الذمم الدائنة',
      'netProfit': 'صافي الربح',
      'cashUsd': 'رصيد الصناديق USD',
      'cashIqd': 'رصيد الصناديق IQD',
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
      'module_sales': 'المبيعات',
      'module_purchases': 'المشتريات',
      'module_payments': 'الدفعات',
      'module_accounting': 'المحاسبة',
      'module_inventory': 'المخزون',
      'module_finance': 'المالية',
      'module_partners': 'الشركاء التجاريون',
      'module_operations': 'التشغيل',
    };
    const en = <String, String>{
      'summary': 'Summary',
      'operations': 'Operations',
      'monthly': 'Monthly',
      'executors': 'Executors',
      'module': 'Module',
      'period': 'Period',
      'generatedAt': 'Generated at',
      'indicator': 'Indicator',
      'value': 'Value',
      'moduleSummary': 'Module summary',
      'operationalIndicators': 'Operational indicators',
      'monthlyPerformance': 'Monthly performance',
      'dataExecutors': 'Data entry users',
      'month': 'Month',
      'sales': 'Sales',
      'purchases': 'Purchases',
      'expenses': 'Expenses',
      'user': 'User',
      'action': 'Action',
      'entity': 'Entity',
      'date': 'Date',
      'section': 'Section',
      'field': 'Field',
      'details': 'Details',
      'rows': 'Rows',
      'report': 'Report',
      'noData': 'No data',
      'excelError': 'Unable to create Excel file.',
      'totalCars': 'Total vehicles',
      'availableCars': 'Available vehicles',
      'reservedCars': 'Reserved vehicles',
      'soldCars': 'Sold vehicles',
      'inventoryItems': 'Inventory items',
      'inventoryValue': 'Inventory value',
      'totalSales': 'Total sales',
      'paidSales': 'Collected sales',
      'receivables': 'Accounts receivable',
      'totalPurchases': 'Total purchases',
      'payables': 'Accounts payable',
      'netProfit': 'Net profit',
      'cashUsd': 'Cash balance USD',
      'cashIqd': 'Cash balance IQD',
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
      'module_sales': 'Sales',
      'module_purchases': 'Purchases',
      'module_payments': 'Payments',
      'module_accounting': 'Accounting',
      'module_inventory': 'Inventory',
      'module_finance': 'Finance',
      'module_partners': 'Business partners',
      'module_operations': 'Operations',
    };
    return (language == 'ar' ? ar : en)[key] ?? key;
  }
}
