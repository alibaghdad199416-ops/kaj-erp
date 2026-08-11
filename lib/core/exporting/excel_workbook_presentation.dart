import 'package:excel/excel.dart';

import 'export_document.dart';

/// Applies the Quality Line visual identity and true Excel value types to
/// exported workbooks.
abstract final class ExcelWorkbookPresentation {
  static final ExcelColor _accent = ExcelColor.fromHexString('#62BEC1');
  static final ExcelColor _accentSoft = ExcelColor.fromHexString('#E8F6F6');
  static final ExcelColor _ink = ExcelColor.fromHexString('#101820');
  static final ExcelColor _muted = ExcelColor.fromHexString('#5F6B73');
  static final ExcelColor _border = ExcelColor.fromHexString('#D6DEE3');
  static final ExcelColor _surface = ExcelColor.fromHexString('#F5F7F8');

  static CellStyle get titleStyle => CellStyle(
    fontColorHex: ExcelColor.white,
    backgroundColorHex: _ink,
    fontSize: 16,
    bold: true,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
  );

  static CellStyle get sectionStyle => CellStyle(
    fontColorHex: _ink,
    backgroundColorHex: _accentSoft,
    fontSize: 12,
    bold: true,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
    bottomBorder: Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: _accent,
    ),
  );

  static CellStyle get headerStyle => CellStyle(
    fontColorHex: ExcelColor.white,
    backgroundColorHex: _accent,
    fontSize: 11,
    bold: true,
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
    leftBorder: Border(borderStyle: BorderStyle.Thin, borderColorHex: _border),
    rightBorder: Border(borderStyle: BorderStyle.Thin, borderColorHex: _border),
    topBorder: Border(borderStyle: BorderStyle.Thin, borderColorHex: _border),
    bottomBorder: Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: _border,
    ),
  );

  static CellStyle dataStyle({
    required bool arabic,
    bool alternate = false,
  }) => CellStyle(
    fontColorHex: _ink,
    backgroundColorHex: alternate ? _surface : ExcelColor.white,
    fontSize: 10,
    horizontalAlign: arabic ? HorizontalAlign.Right : HorizontalAlign.Left,
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
    leftBorder: Border(borderStyle: BorderStyle.Thin, borderColorHex: _border),
    rightBorder: Border(borderStyle: BorderStyle.Thin, borderColorHex: _border),
    topBorder: Border(borderStyle: BorderStyle.Thin, borderColorHex: _border),
    bottomBorder: Border(
      borderStyle: BorderStyle.Thin,
      borderColorHex: _border,
    ),
  );

  static CellStyle get metadataLabelStyle => CellStyle(
    fontColorHex: _muted,
    backgroundColorHex: _surface,
    fontSize: 10,
    bold: true,
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
  );

  static CellStyle get metadataValueStyle => CellStyle(
    fontColorHex: _ink,
    backgroundColorHex: ExcelColor.white,
    fontSize: 10,
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
  );

  static void prepareSheet(
    Sheet sheet, {
    required bool arabic,
    double defaultWidth = 18,
  }) {
    sheet.isRTL = arabic;
    sheet.setDefaultColumnWidth(defaultWidth);
    sheet.setDefaultRowHeight(21);
  }

  static void styleTitle(
    Sheet sheet, {
    required int row,
    required int columnCount,
  }) {
    if (columnCount <= 0) return;
    final start = CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row);
    final end = CellIndex.indexByColumnRow(
      columnIndex: columnCount - 1,
      rowIndex: row,
    );
    if (columnCount > 1) sheet.merge(start, end);
    sheet.setMergedCellStyle(start, titleStyle);
    sheet.setRowHeight(row, 30);
  }

  static void styleHeader(Sheet sheet, int row, int columnCount) {
    for (var column = 0; column < columnCount; column++) {
      sheet
              .cell(
                CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
              )
              .cellStyle =
          headerStyle;
      sheet.setColumnWidth(column, column == 0 ? 20 : 18);
    }
    sheet.setRowHeight(row, 27);
  }

  static void styleDataRows(
    Sheet sheet, {
    required int startRow,
    required int rowCount,
    required int columnCount,
    required bool arabic,
  }) {
    for (var offset = 0; offset < rowCount; offset++) {
      final row = startRow + offset;
      final style = dataStyle(arabic: arabic, alternate: offset.isOdd);
      for (var column = 0; column < columnCount; column++) {
        styleCell(
          sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row),
          ),
          style,
        );
      }
      sheet.setRowHeight(row, 24);
    }
  }

  /// Applying a visual style must not replace the native number format that
  /// belongs to dates, times, integers, or decimals. The excel package rejects
  /// a DateTime cell paired with the generic numeric `General` format.
  static void styleCell(Data cell, CellStyle style) {
    final format =
        cell.cellStyle?.numberFormat ?? NumFormat.defaultFor(cell.value);
    cell.cellStyle = style.copyWith(numberFormat: format);
  }

  /// Converts a raw report value to the native XLSX cell type expected by
  /// Microsoft Excel. Keeping numbers, dates and booleans typed prevents
  /// workbook repair warnings and preserves sorting/formulas in exported
  /// operational and accounting reports.
  static CellValue typedValue(
    Object? value, {
    String columnLabel = '',
    ExportValueType? type,
  }) {
    if (value == null) return TextCellValue('');

    DateTime? asDateTime(Object raw) {
      if (raw is DateTime) return raw;
      return DateTime.tryParse(raw.toString());
    }

    num? asNumber(Object raw) {
      if (raw is num) return raw;
      return num.tryParse(raw.toString().replaceAll(',', '').trim());
    }

    switch (type) {
      case ExportValueType.integer:
        final number = asNumber(value);
        return number == null
            ? TextCellValue(value.toString())
            : IntCellValue(number.toInt());
      case ExportValueType.decimal:
      case ExportValueType.money:
        final number = asNumber(value);
        return number == null
            ? TextCellValue(value.toString())
            : DoubleCellValue(number.toDouble());
      case ExportValueType.date:
      case ExportValueType.dateTime:
        final date = asDateTime(value);
        return date == null
            ? TextCellValue(value.toString())
            : DateTimeCellValue.fromDateTime(date);
      case ExportValueType.boolean:
        if (value is bool) return BoolCellValue(value);
        final normalized = value.toString().trim().toLowerCase();
        if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
          return BoolCellValue(true);
        }
        if (normalized == '0' || normalized == 'false' || normalized == 'no') {
          return BoolCellValue(false);
        }
        return TextCellValue(value.toString());
      case ExportValueType.text:
        return TextCellValue(value.toString());
      case null:
        break;
    }

    if (value is bool) return BoolCellValue(value);
    if (value is int) return IntCellValue(value);
    if (value is double) return DoubleCellValue(value);
    if (value is num) return DoubleCellValue(value.toDouble());
    if (value is DateTime) return DateTimeCellValue.fromDateTime(value);

    // Values coming from generic report maps sometimes arrive as strings.
    // Infer only when the column name clearly carries numeric/date semantics;
    // identifiers, document numbers and codes must remain text.
    final label = columnLabel.toLowerCase();
    final looksLikeIdentifier =
        label.contains('id') ||
        label.contains('code') ||
        label.contains('number') ||
        label.contains('رقم') ||
        label.contains('رمز');
    if (!looksLikeIdentifier) {
      if (label.contains('date') ||
          label.contains('time') ||
          label.contains('تاريخ') ||
          label.contains('وقت')) {
        final date = asDateTime(value);
        if (date != null) return DateTimeCellValue.fromDateTime(date);
      }
      if (label.contains('amount') ||
          label.contains('balance') ||
          label.contains('debit') ||
          label.contains('credit') ||
          label.contains('quantity') ||
          label.contains('rate') ||
          label.contains('total') ||
          label.contains('مبلغ') ||
          label.contains('رصيد') ||
          label.contains('مدين') ||
          label.contains('دائن') ||
          label.contains('كمية') ||
          label.contains('سعر') ||
          label.contains('إجمالي')) {
        final number = asNumber(value);
        if (number != null) {
          return number is int
              ? IntCellValue(number)
              : DoubleCellValue(number.toDouble());
        }
      }
    }
    return TextCellValue(value.toString());
  }
}
