import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'excel_download_service.dart';

import 'excel_relation_index.dart';
import 'excel_workbook_presentation.dart';
import 'export_document.dart';
import 'report_template_engine.dart';

class ExcelExportService {
  ExcelExportService({ReportTemplateEngine? templateEngine})
    : _template = templateEngine ?? const ReportTemplateEngine();

  final ReportTemplateEngine _template;

  Future<Uint8List> build(ExportDocument document) async {
    document.validate();
    final exportDocument = ExportDocument(
      title: document.title,
      subtitle: document.subtitle,
      columns: document.columns,
      rows: document.rows,
      metadata: document.metadata,
      language: 'en',
      currency: document.currency,
      generatedAt: document.generatedAt,
    );
    document = exportDocument;
    final workbook = Excel.createExcel();
    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null) workbook.delete(defaultSheet);

    final profileName = document.isArabic ? 'تعريف الملف' : 'Workbook profile';
    final profile = workbook[profileName];
    ExcelWorkbookPresentation.prepareSheet(profile, arabic: document.isArabic);
    profile.appendRow([TextCellValue(document.title)]);
    ExcelWorkbookPresentation.styleTitle(profile, row: 0, columnCount: 2);
    final generatedAt = document.generatedAt ?? DateTime.now();
    final profileRows = <(String, Object?)>[
      (
        document.isArabic ? 'لغة الملف' : 'Workbook language',
        document.isArabic ? 'العربية' : 'English',
      ),
      (document.isArabic ? 'العملة' : 'Currency', document.currency ?? ''),
      (document.isArabic ? 'التاريخ والوقت' : 'Date and time', generatedAt),
      (
        document.isArabic ? 'إصدار بنية الملف' : 'Workbook schema version',
        '18.9.12',
      ),
      ...document.metadata.entries.map((entry) => (entry.key, entry.value)),
    ];
    for (var index = 0; index < profileRows.length; index++) {
      final entry = profileRows[index];
      profile.appendRow([
        TextCellValue(entry.$1),
        ExcelWorkbookPresentation.typedValue(entry.$2, columnLabel: entry.$1),
      ]);
      profile
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: index + 1))
          .cellStyle = ExcelWorkbookPresentation
          .metadataLabelStyle;
      ExcelWorkbookPresentation.styleCell(
        profile.cell(
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: index + 1),
        ),
        ExcelWorkbookPresentation.metadataValueStyle,
      );
    }
    profile.setColumnWidth(0, 27);
    profile.setColumnWidth(1, 36);

    final sheet = workbook[_sheetName(document.title)];
    ExcelWorkbookPresentation.prepareSheet(sheet, arabic: document.isArabic);

    sheet.appendRow([TextCellValue(document.title)]);
    ExcelWorkbookPresentation.styleTitle(
      sheet,
      row: 0,
      columnCount: document.columns.length,
    );

    var rowIndex = 1;
    if (document.subtitle?.trim().isNotEmpty == true) {
      sheet.appendRow([TextCellValue(document.subtitle!.trim())]);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
          .cellStyle = ExcelWorkbookPresentation
          .sectionStyle;
      rowIndex++;
    }

    final exportTimestamp = document.generatedAt ?? DateTime.now();
    final metadata = <String, Object?>{
      (document.isArabic ? 'لغة الملف' : 'Workbook language'): document.isArabic
          ? 'العربية'
          : 'English',
      (document.isArabic ? 'العملة' : 'Currency'): document.currency ?? '',
      (document.isArabic ? 'تاريخ التصدير' : 'Export date'): DateTime(
        exportTimestamp.year,
        exportTimestamp.month,
        exportTimestamp.day,
      ),
      (document.isArabic ? 'وقت التصدير' : 'Export time'): exportTimestamp,
      ...document.metadata,
    };

    for (final entry in metadata.entries) {
      sheet.appendRow([
        TextCellValue(entry.key),
        ExcelWorkbookPresentation.typedValue(
          entry.value,
          columnLabel: entry.key,
        ),
      ]);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
          .cellStyle = ExcelWorkbookPresentation
          .metadataLabelStyle;
      ExcelWorkbookPresentation.styleCell(
        sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex),
        ),
        ExcelWorkbookPresentation.metadataValueStyle,
      );
      rowIndex++;
    }

    sheet.appendRow([]);
    rowIndex++;
    final headerRow = rowIndex;
    sheet.appendRow(
      document.columns.map((column) => TextCellValue(column.label)).toList(),
    );
    ExcelWorkbookPresentation.styleHeader(
      sheet,
      headerRow,
      document.columns.length,
    );
    rowIndex++;

    for (final row in document.rows) {
      sheet.appendRow(
        List<CellValue>.generate(document.columns.length, (index) {
          final value = row[index];
          final column = document.columns[index];
          return ExcelWorkbookPresentation.typedValue(
            value,
            columnLabel: column.label,
            type: column.type,
          );
        }),
      );
    }

    ExcelWorkbookPresentation.styleDataRows(
      sheet,
      startRow: headerRow + 1,
      rowCount: document.rows.length,
      columnCount: document.columns.length,
      arabic: document.isArabic,
    );

    final relationRows = ExcelRelationIndex.build(document);
    final relationName = document.isArabic ? 'دليل الربط' : 'Relation index';
    final relationSheet = workbook[relationName];
    ExcelWorkbookPresentation.prepareSheet(
      relationSheet,
      arabic: document.isArabic,
    );
    final relationTitle = document.isArabic
        ? 'الربط بين الوحدات والمستندات'
        : 'Cross-module document relations';
    relationSheet.appendRow([TextCellValue(relationTitle)]);
    ExcelWorkbookPresentation.styleTitle(relationSheet, row: 0, columnCount: 5);
    final relationHeaders = document.isArabic
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
          ];
    relationSheet.appendRow(relationHeaders.map(TextCellValue.new).toList());
    ExcelWorkbookPresentation.styleHeader(
      relationSheet,
      1,
      relationHeaders.length,
    );
    for (final relation in relationRows) {
      relationSheet.appendRow(
        relation
            .map((value) => ExcelWorkbookPresentation.typedValue(value))
            .toList(),
      );
    }
    ExcelWorkbookPresentation.styleDataRows(
      relationSheet,
      startRow: 2,
      rowCount: relationRows.length,
      columnCount: relationHeaders.length,
      arabic: document.isArabic,
    );
    if (relationRows.isEmpty) {
      relationSheet.appendRow([
        TextCellValue(
          document.isArabic
              ? 'لا توجد روابط ظاهرة في هذا التصدير'
              : 'No visible relations in this export',
        ),
      ]);
    }

    workbook.setDefaultSheet(profileName);
    final encoded = workbook.encode();
    if (encoded == null) throw StateError('Unable to encode Excel workbook.');
    return Uint8List.fromList(encoded);
  }

  Future<void> save(ExportDocument document) async {
    final bytes = await build(document);
    final name = _template.fileName(document, 'xlsx');
    await ExcelDownloadService.save(fileName: name, bytes: bytes);
  }

  String _sheetName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/?*\[\]:]'), ' ').trim();
    if (cleaned.isEmpty) return 'Report';
    return cleaned.length <= 31 ? cleaned : cleaned.substring(0, 31);
  }
}
