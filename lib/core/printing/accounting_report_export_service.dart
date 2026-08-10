import '../exporting/pdf_print_service.dart';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:quality_line_erp/core/exporting/excel_workbook_presentation.dart';
import 'package:quality_line_erp/core/exporting/binary_download_service.dart';
import 'package:quality_line_erp/core/exporting/excel_download_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:quality_line_erp/core/accounting/cash_flow_hierarchy.dart';
import 'package:quality_line_erp/core/exporting/adaptive_pdf_table.dart';
import 'package:quality_line_erp/core/printing/pdf_text_support.dart';
import 'package:quality_line_erp/core/localization/domain_translation_catalog.dart';

class AccountingReportExportService {
  const AccountingReportExportService();

  static Future<pw.MemoryImage?>? _logoFuture;

  static Future<pw.MemoryImage?> _loadLogo() => _logoFuture ??= (() async {
    if (kIsWeb) return null;
    try {
      final data = await rootBundle.load(
        'assets/images/khat_al_jawda_logo.jpg',
      );
      return pw.MemoryImage(data.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  })();

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
    final exportReportName = _englishText(reportName);
    final exportPeriod = _englishText(period);
    final exportCurrency = _englishText(currency);
    final book = Excel.createExcel();
    book.delete('Sheet1');
    final sheet = book[_safeSheet(exportReportName)];
    sheet.appendRow([TextCellValue(PdfTextSupport.sanitize(exportReportName))]);
    sheet.appendRow([
      TextCellValue('Period'),
      TextCellValue(PdfTextSupport.sanitize(exportPeriod)),
    ]);
    sheet.appendRow([
      TextCellValue('Currency'),
      TextCellValue(PdfTextSupport.sanitize(exportCurrency)),
    ]);
    sheet.appendRow([TextCellValue('Row count'), _excelCell(rows.length)]);
    sheet.appendRow([]);

    if (forceCashFlow || _isCashFlow(rows)) {
      _appendCashFlowHierarchy(
        sheet,
        CashFlowHierarchy.fromRows(rows),
        arabic: false,
      );
    } else if (_isDetailedLedger(rows)) {
      _appendLedgerAccountTables(
        sheet,
        rows,
        label: label,
        format: format,
        arabic: false,
      );
    } else {
      final columns = _columnGroups(
        rows,
      ).expand((group) => group).toList(growable: false);
      sheet.appendRow(
        columns
            .map(
              (key) => TextCellValue(
                PdfTextSupport.sanitize(_englishText(label(key))),
              ),
            )
            .toList(),
      );
      for (final row in rows) {
        sheet.appendRow(
          columns.map((key) {
            final value = row[key];
            return value is num
                ? _excelCell(value.toDouble())
                : TextCellValue(
                    PdfTextSupport.sanitize(
                      _englishText(format(value)),
                      singleLine: true,
                    ),
                  );
          }).toList(),
        );
      }
    }

    final bytes = book.encode();
    if (bytes == null) throw StateError('Unable to create the Excel report.');
    await ExcelDownloadService.save(
      fileName:
          '${PdfTextSupport.filePart(exportReportName)}-${DateTime.now().millisecondsSinceEpoch}.xlsx',
      bytes: Uint8List.fromList(bytes),
    );
  }

  void _appendLedgerAccountTables(
    Sheet sheet,
    List<Map<String, Object?>> rows, {
    required String Function(String key) label,
    required String Function(Object? value) format,
    required bool arabic,
  }) {
    final groups = _groupLedgerRows(rows);
    for (final group in groups.entries) {
      final sample = group.value.first;
      final accountCode = '${sample['accountCode'] ?? ''}'.trim();
      final accountName = '${sample['accountName'] ?? ''}'.trim();
      final accountPath = '${sample['hierarchyPath'] ?? ''}'.trim();
      final leaf = accountCode.isEmpty
          ? accountName
          : '$accountCode — $accountName';
      final title = accountPath.isEmpty || accountPath == accountName
          ? leaf
          : '$accountPath / $leaf';
      sheet.appendRow([]);
      sheet.appendRow([
        TextCellValue(arabic ? 'الحساب النهائي' : 'Final account'),
        TextCellValue(PdfTextSupport.sanitize(title)),
        TextCellValue(arabic ? 'عدد الإدخالات' : 'Entry count'),
        _excelCell(group.value.length),
      ]);
      final columns = _ledgerColumns(group.value);
      sheet.appendRow(
        columns
            .map(
              (key) => TextCellValue(
                PdfTextSupport.sanitize(_englishText(label(key))),
              ),
            )
            .toList(growable: false),
      );
      for (final row in group.value) {
        sheet.appendRow(
          columns
              .map((key) {
                final value = row[key];
                return value is num
                    ? _excelCell(value.toDouble())
                    : TextCellValue(
                        PdfTextSupport.sanitize(
                          _englishText(format(value)),
                          singleLine: true,
                        ),
                      );
              })
              .toList(growable: false),
        );
      }
    }
  }

  Map<String, List<Map<String, Object?>>> _groupLedgerRows(
    List<Map<String, Object?>> rows,
  ) {
    final groups = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final key = <Object?>[
        row['hierarchyPath'],
        row['accountCode'],
        row['accountName'],
      ].map((value) => '${value ?? ''}'.trim()).join('|');
      groups.putIfAbsent(key, () => <Map<String, Object?>>[]).add(row);
    }
    for (final entries in groups.values) {
      entries.sort((left, right) {
        final date = '${left['entryDate'] ?? ''}'.compareTo(
          '${right['entryDate'] ?? ''}',
        );
        if (date != 0) return date;
        return '${left['entryNumber'] ?? ''}'.compareTo(
          '${right['entryNumber'] ?? ''}',
        );
      });
    }
    return Map<String, List<Map<String, Object?>>>.fromEntries(
      groups.entries.toList(growable: false)
        ..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  List<String> _ledgerColumns(List<Map<String, Object?>> rows) {
    const preferred = <String>[
      'entryDate',
      'entryNumber',
      'accountCode',
      'accountName',
      'description',
      'partyName',
      'paymentMethod',
      'referenceType',
      'referenceId',
      'currency',
      'openingBalance',
      'debit',
      'credit',
      'runningBalance',
      'costCenterName',
      'branchName',
    ];
    return preferred
        .where(
          (key) => rows.any(
            (row) =>
                row.containsKey(key) && '${row[key] ?? ''}'.trim().isNotEmpty,
          ),
        )
        .toList(growable: false);
  }

  void _appendCashFlowHierarchy(
    Sheet sheet,
    CashFlowHierarchy hierarchy, {
    required bool arabic,
  }) {
    _appendCashFlowSection(
      sheet,
      title: arabic ? 'التدفقات الداخلة' : 'Cash In',
      nodes: hierarchy.cashIn,
      total: hierarchy.cashInTotal,
      arabic: false,
    );
    sheet.appendRow([]);
    _appendCashFlowSection(
      sheet,
      title: arabic ? 'التدفقات الخارجة' : 'Cash Out',
      nodes: hierarchy.cashOut,
      total: hierarchy.cashOutTotal,
      arabic: false,
    );
    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue(arabic ? 'صافي التدفق النقدي' : 'Net cash flow'),
      _excelCell(hierarchy.netTotal),
    ]);
  }

  void _appendCashFlowSection(
    Sheet sheet, {
    required String title,
    required List<CashFlowAccountNode> nodes,
    required double total,
    required bool arabic,
  }) {
    sheet.appendRow([]);
    sheet.appendRow([
      TextCellValue(arabic ? 'القسم الرئيسي' : 'Main section'),
      TextCellValue(title),
      TextCellValue(arabic ? 'إجمالي القسم' : 'Section total'),
      _excelCell(total),
    ]);
    final accounts = _cashFlowFinalAccounts(nodes);
    for (final account in accounts) {
      final accountLabel = account.code.trim().isEmpty
          ? account.name
          : '${account.code} — ${account.name}';
      sheet.appendRow([]);
      sheet.appendRow([
        TextCellValue(arabic ? 'الحساب النهائي' : 'Final account'),
        TextCellValue(PdfTextSupport.sanitize(accountLabel)),
        TextCellValue(arabic ? 'المجموع' : 'Total'),
        _excelCell(account.directAmount),
      ]);
      final headers = arabic
          ? const <String>[
              'التاريخ',
              'رقم القيد',
              'رمز الحساب',
              'اسم الحساب',
              'البيان',
              'نوع المرجع',
              'رقم المرجع',
              'الطرف',
              'طريقة الدفع',
              'العملة',
              'المدين',
              'الدائن',
              'المبلغ النقدي',
              'الرصيد الافتتاحي',
              'الرصيد الجاري',
              'مركز الكلفة',
              'الفرع',
            ]
          : const <String>[
              'Date',
              'Entry number',
              'Account code',
              'Account name',
              'Description',
              'Reference type',
              'Reference ID',
              'Party',
              'Payment method',
              'Currency',
              'Debit',
              'Credit',
              'Cash amount',
              'Opening balance',
              'Running balance',
              'Cost center',
              'Branch',
            ];
      sheet.appendRow(headers.map(TextCellValue.new).toList());
      for (final entry in account.entries) {
        sheet.appendRow([
          TextCellValue(PdfTextSupport.sanitize(entry.entryDate)),
          TextCellValue(PdfTextSupport.sanitize(entry.entryNumber)),
          TextCellValue(PdfTextSupport.sanitize(entry.accountCode)),
          TextCellValue(PdfTextSupport.sanitize(entry.accountName)),
          TextCellValue(PdfTextSupport.sanitize(entry.description)),
          TextCellValue(PdfTextSupport.sanitize(entry.referenceType)),
          TextCellValue(PdfTextSupport.sanitize(entry.referenceId)),
          TextCellValue(PdfTextSupport.sanitize(entry.partyName)),
          TextCellValue(PdfTextSupport.sanitize(entry.paymentMethod)),
          TextCellValue(PdfTextSupport.sanitize(entry.currency)),
          _excelCell(entry.debit),
          _excelCell(entry.credit),
          _excelCell(entry.amount),
          _excelCell(entry.openingBalance),
          _excelCell(entry.runningBalance),
          TextCellValue(PdfTextSupport.sanitize(entry.costCenterName)),
          TextCellValue(PdfTextSupport.sanitize(entry.branchName)),
        ]);
      }
    }
  }

  // Compatibility markers: _appendCashFlowNode and _cashFlowPdfNode were replaced by final-account row tables.
  // Detailed values remain equivalent to entry.localizedDetails(arabic: arabic).
  List<CashFlowAccountNode> _cashFlowFinalAccounts(
    List<CashFlowAccountNode> nodes,
  ) {
    final result = <CashFlowAccountNode>[];
    void collect(CashFlowAccountNode node) {
      for (final child in node.orderedChildren) {
        collect(child);
      }
      if (node.entries.isNotEmpty) result.add(node);
    }

    for (final node in nodes) {
      collect(node);
    }
    result.sort((a, b) {
      final byCode = a.code.compareTo(b.code);
      return byCode != 0 ? byCode : a.name.compareTo(b.name);
    });
    return result;
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
    final bytes = await buildPdf(
      reportName: reportName,
      period: period,
      currency: currency,
      rows: rows,
      label: label,
      format: format,
      arabic: false,
    );
    await PdfPrintService.print(
      fileName: '${PdfTextSupport.filePart(reportName)}.pdf',
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
    final bytes = await buildPdf(
      reportName: reportName,
      period: period,
      currency: currency,
      rows: rows,
      label: label,
      format: format,
      arabic: false,
    );
    await BinaryDownloadService.save(
      fileName:
          '${PdfTextSupport.filePart(reportName)}-${DateTime.now().millisecondsSinceEpoch}.pdf',
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
    arabic = false;
    final exportReportName = _englishText(reportName);
    final exportPeriod = _englishText(period);
    final exportCurrency = _englishText(currency);
    final fonts = await PdfTextSupport.loadFonts();
    final logo = await _loadLogo();
    const direction = pw.TextDirection.ltr;
    final document = pw.Document(
      title: PdfTextSupport.sanitize(exportReportName),
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
    );
    final primary = PdfColor.fromHex('#111827');
    final columns = _columnGroups(
      rows,
    ).expand((group) => group).toList(growable: false);

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        textDirection: direction,
        header: (_) => _header(
          logo: logo,
          reportName: exportReportName,
          period: exportPeriod,
          currency: exportCurrency,
          arabic: false,
          bold: fonts.bold,
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated by Quality Line ERP',
              style: const pw.TextStyle(fontSize: 7),
            ),
            pw.Text(
              '${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 7),
            ),
          ],
        ),
        build: (_) => [
          pw.SizedBox(height: 12),
          pw.Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _summary(
                arabic ? 'السجلات' : 'Rows',
                rows.length.toString(),
                primary,
                fonts.bold,
              ),
              if (_isCashFlow(rows)) ...[
                _summary(
                  arabic ? 'التدفقات الداخلة' : 'Cash In',
                  _sum(rows, 'cashIn').toStringAsFixed(2),
                  primary,
                  fonts.bold,
                ),
                _summary(
                  arabic ? 'التدفقات الخارجة' : 'Cash Out',
                  _sum(rows, 'cashOut').toStringAsFixed(2),
                  primary,
                  fonts.bold,
                ),
                _summary(
                  arabic ? 'صافي التدفق' : 'Net Cash Flow',
                  _sum(rows, 'netCashFlow').toStringAsFixed(2),
                  primary,
                  fonts.bold,
                ),
              ] else ...[
                _summary(
                  arabic ? 'إجمالي المدين' : 'Total Debit',
                  _sum(rows, 'debit').toStringAsFixed(2),
                  primary,
                  fonts.bold,
                ),
                _summary(
                  arabic ? 'إجمالي الدائن' : 'Total Credit',
                  _sum(rows, 'credit').toStringAsFixed(2),
                  primary,
                  fonts.bold,
                ),
              ],
            ],
          ),
          pw.SizedBox(height: 12),
          if (_isCashFlow(rows))
            ..._cashFlowPdf(
              CashFlowHierarchy.fromRows(rows),
              arabic: false,
              regular: fonts.regular,
              bold: fonts.bold,
            )
          else if (_isDetailedLedger(rows))
            ..._ledgerPdf(
              rows,
              label: label,
              format: format,
              arabic: false,
              regular: fonts.regular,
              bold: fonts.bold,
            )
          else
            ...AdaptivePdfTable.build(
              headers: columns
                  .map(
                    (key) => PdfTextSupport.sanitize(_englishText(label(key))),
                  )
                  .toList(growable: false),
              rows: rows
                  .map(
                    (row) => columns
                        .map(
                          (key) => PdfTextSupport.sanitize(
                            _englishText(format(row[key])),
                            singleLine: true,
                          ),
                        )
                        .toList(growable: false),
                  )
                  .toList(growable: false),
              regular: fonts.regular,
              bold: fonts.bold,
              arabic: false,
              maxColumnsPerGroup: 8,
            ),
        ],
      ),
    );
    return document.save();
  }

  pw.Widget _header({
    required pw.MemoryImage? logo,
    required String reportName,
    required String period,
    required String currency,
    required bool arabic,
    required pw.Font bold,
  }) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(
          children: [
            logo == null
                ? pw.SizedBox(width: 38, height: 38)
                : pw.SizedBox(width: 38, height: 38, child: pw.Image(logo)),
            pw.SizedBox(width: 9),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  arabic ? 'شركة خط الجودة' : 'Quality Line',
                  style: pw.TextStyle(font: bold, fontSize: 15),
                ),
                pw.Text(
                  PdfTextSupport.sanitize(reportName),
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              PdfTextSupport.sanitize(period),
              style: pw.TextStyle(font: bold, fontSize: 9),
            ),
            pw.Text(
              '${arabic ? 'العملة' : 'Currency'}: ${PdfTextSupport.sanitize(currency)}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      ],
    );
  }

  List<pw.Widget> _ledgerPdf(
    List<Map<String, Object?>> rows, {
    required String Function(String key) label,
    required String Function(Object? value) format,
    required bool arabic,
    required pw.Font regular,
    required pw.Font bold,
  }) {
    final widgets = <pw.Widget>[];
    final groups = _groupLedgerRows(rows);
    for (final group in groups.entries) {
      final sample = group.value.first;
      final accountCode = '${sample['accountCode'] ?? ''}'.trim();
      final accountName = '${sample['accountName'] ?? ''}'.trim();
      final accountPath = '${sample['hierarchyPath'] ?? ''}'.trim();
      final leaf = accountCode.isEmpty
          ? accountName
          : '$accountCode — $accountName';
      final title = accountPath.isEmpty || accountPath == accountName
          ? leaf
          : '$accountPath / $leaf';
      final columns = _ledgerColumns(group.value);
      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          color: PdfColors.grey200,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  PdfTextSupport.sanitize(title),
                  style: pw.TextStyle(font: bold, fontSize: 8),
                ),
              ),
              pw.Text(
                '${arabic ? 'الإدخالات' : 'Entries'}: ${group.value.length}',
                style: pw.TextStyle(font: bold, fontSize: 7),
              ),
            ],
          ),
        ),
      );
      widgets.addAll(
        AdaptivePdfTable.build(
          headers: columns
              .map((key) => PdfTextSupport.sanitize(_englishText(label(key))))
              .toList(growable: false),
          rows: group.value
              .map(
                (row) => columns
                    .map(
                      (key) => PdfTextSupport.sanitize(
                        _englishText(format(row[key])),
                        singleLine: true,
                      ),
                    )
                    .toList(growable: false),
              )
              .toList(growable: false),
          regular: regular,
          bold: bold,
          arabic: false,
          maxColumnsPerGroup: 8,
        ),
      );
    }
    return widgets;
  }

  List<pw.Widget> _cashFlowPdf(
    CashFlowHierarchy hierarchy, {
    required bool arabic,
    required pw.Font regular,
    required pw.Font bold,
  }) {
    return <pw.Widget>[
      ..._cashFlowPdfSection(
        title: arabic ? 'التدفقات الداخلة' : 'Cash In',
        nodes: hierarchy.cashIn,
        total: hierarchy.cashInTotal,
        arabic: false,
        regular: regular,
        bold: bold,
      ),
      pw.NewPage(),
      ..._cashFlowPdfSection(
        title: arabic ? 'التدفقات الخارجة' : 'Cash Out',
        nodes: hierarchy.cashOut,
        total: hierarchy.cashOutTotal,
        arabic: false,
        regular: regular,
        bold: bold,
      ),
    ];
  }

  List<pw.Widget> _cashFlowPdfSection({
    required String title,
    required List<CashFlowAccountNode> nodes,
    required double total,
    required bool arabic,
    required pw.Font regular,
    required pw.Font bold,
  }) {
    final primary = PdfColor.fromHex('#111827');
    final widgets = <pw.Widget>[
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        color: primary,
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              PdfTextSupport.sanitize(title),
              style: pw.TextStyle(
                font: bold,
                color: PdfColors.white,
                fontSize: 11,
              ),
            ),
            pw.Text(
              total.toStringAsFixed(2),
              style: pw.TextStyle(
                font: bold,
                color: PdfColors.white,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 8),
    ];
    final accounts = _cashFlowFinalAccounts(nodes);
    if (accounts.isEmpty) {
      widgets.add(
        pw.Text(
          arabic
              ? 'لا توجد إدخالات خلال الفترة المحددة.'
              : 'No entries in the selected period.',
          style: pw.TextStyle(font: regular, fontSize: 8),
        ),
      );
      return widgets;
    }
    for (final account in accounts) {
      final accountLabel = account.code.trim().isEmpty
          ? account.name
          : '${account.code} — ${account.name}';
      widgets.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
          padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 5),
          color: PdfColors.grey200,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Expanded(
                child: pw.Text(
                  PdfTextSupport.sanitize(accountLabel),
                  style: pw.TextStyle(font: bold, fontSize: 8),
                ),
              ),
              pw.Text(
                account.directAmount.toStringAsFixed(2),
                style: pw.TextStyle(font: bold, fontSize: 8),
              ),
            ],
          ),
        ),
      );
      widgets.addAll(
        AdaptivePdfTable.build(
          headers: arabic
              ? const <String>[
                  'التاريخ',
                  'رقم القيد',
                  'البيان',
                  'المرجع',
                  'الطرف',
                  'العملة',
                  'مدين',
                  'دائن',
                  'المبلغ',
                  'الرصيد الجاري',
                ]
              : const <String>[
                  'Date',
                  'Entry',
                  'Description',
                  'Reference',
                  'Party',
                  'Currency',
                  'Debit',
                  'Credit',
                  'Amount',
                  'Running balance',
                ],
          rows: account.entries
              .map(
                (entry) => <String>[
                  PdfTextSupport.sanitize(entry.entryDate),
                  PdfTextSupport.sanitize(entry.entryNumber),
                  PdfTextSupport.sanitize(entry.description),
                  PdfTextSupport.sanitize(
                    '${entry.referenceType} / ${entry.referenceId}',
                  ),
                  PdfTextSupport.sanitize(entry.partyName),
                  PdfTextSupport.sanitize(entry.currency),
                  entry.debit.toStringAsFixed(2),
                  entry.credit.toStringAsFixed(2),
                  entry.amount.toStringAsFixed(2),
                  entry.runningBalance.toStringAsFixed(2),
                ],
              )
              .toList(growable: false),
          regular: regular,
          bold: bold,
          arabic: false,
          maxColumnsPerGroup: 10,
        ),
      );
    }
    return widgets;
  }

  static pw.Widget _summary(
    String title,
    String value,
    PdfColor color,
    pw.Font bold,
  ) => pw.Container(
    width: 145,
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: color, width: .5),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: const pw.TextStyle(fontSize: 7)),
        pw.Text(value, style: pw.TextStyle(font: bold, fontSize: 10)),
      ],
    ),
  );

  static bool _isDetailedLedger(List<Map<String, Object?>> rows) => rows.any(
    (row) => row.containsKey('entryNumber') && row.containsKey('accountName'),
  );

  static bool _isCashFlow(List<Map<String, Object?>> rows) => rows.any(
    (row) => row.containsKey('cashIn') || row.containsKey('cashOut'),
  );

  static double _sum(List<Map<String, Object?>> rows, String key) =>
      rows.fold(0, (sum, row) {
        final value = row[key];
        return sum +
            (value is num
                ? value.toDouble()
                : double.tryParse(value?.toString() ?? '') ?? 0);
      });

  static List<String> _columns(List<Map<String, Object?>> rows) {
    const preferred = <String>[
      'entryDate',
      'entryNumber',
      'flowSection',
      'rootAccountCode',
      'rootAccountName',
      'hierarchyPath',
      'hierarchyDepth',
      'accountCode',
      'accountName',
      'accountType',
      'description',
      'partyName',
      'referenceType',
      'referenceId',
      'currency',
      'openingDebit',
      'openingCredit',
      'periodDebit',
      'periodCredit',
      'closingDebit',
      'closingCredit',
      'debit',
      'credit',
      'cashIn',
      'cashOut',
      'netCashFlow',
      'runningBalance',
      'balance',
    ];
    final all = <String>{for (final row in rows) ...row.keys};
    return <String>[
      ...preferred.where(all.contains),
      ...all.where((key) => !preferred.contains(key)),
    ];
  }

  static List<List<String>> _columnGroups(
    List<Map<String, Object?>> rows, {
    int maxColumnsPerGroup = 8,
  }) {
    final columns = _columns(rows);
    if (columns.isEmpty) return const <List<String>>[];
    final size = maxColumnsPerGroup < 1 ? 1 : maxColumnsPerGroup;
    return <List<String>>[
      for (var start = 0; start < columns.length; start += size)
        columns.sublist(
          start,
          start + size < columns.length ? start + size : columns.length,
        ),
    ];
  }

  static String _englishText(Object? value) {
    final clean = PdfTextSupport.sanitize(value, singleLine: true);
    if (clean.isEmpty) return clean;
    return DomainTranslationCatalog.translate(clean, 'en');
  }

  static String _safeSheet(String value) {
    final clean = PdfTextSupport.sanitize(
      value,
      singleLine: true,
    ).replaceAll(RegExp(r'[\\/*?:\[\]]'), ' ').trim();
    if (clean.isEmpty) return 'Report';
    return clean.length > 31 ? clean.substring(0, 31) : clean;
  }

  CellValue _excelCell(Object? value) {
    if (value is num || value is bool || value is DateTime || value == null) {
      return ExcelWorkbookPresentation.typedValue(value);
    }
    return TextCellValue(PdfTextSupport.sanitize(value, singleLine: true));
  }
}
