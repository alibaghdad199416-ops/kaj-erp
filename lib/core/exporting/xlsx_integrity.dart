import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Normalizes the XLSX package emitted by `package:excel` before download.
///
/// `excel 4.0.6` can emit worksheet metadata that is tolerated by some XLSX
/// readers but rejected/repaired by Microsoft Excel: `sheetFormatPr` can appear
/// before `dimension`/`sheetViews`, and `dimension` can remain `A1` even when
/// the worksheet contains a larger used range. This finalizer repairs those
/// package-level invariants without changing cell values, styles, relations,
/// formulas, workbook language, or sheet direction.
abstract final class XlsxIntegrity {
  static final RegExp _worksheetPath = RegExp(r'^xl/worksheets/[^/]+\.xml$');
  static final RegExp _cellReference = RegExp(r'<c\b[^>]*\br="([^"]+)"');
  static final RegExp _mergeReference = RegExp(
    r'<mergeCell\b[^>]*\bref="([^"]+)"',
  );
  static final RegExp _dimensionElement = RegExp(r'<dimension\b[^>]*/>');
  static final RegExp _sheetFormatElement = RegExp(r'<sheetFormatPr\b[^>]*/>');
  static final RegExp _sheetViewsElement = RegExp(
    r'<sheetViews\b[^>]*>.*?</sheetViews>|<sheetViews\b[^>]*/>',
    dotAll: true,
  );
  static final RegExp _sheetPrElement = RegExp(
    r'<sheetPr\b[^>]*>.*?</sheetPr>|<sheetPr\b[^>]*/>',
    dotAll: true,
  );

  static Uint8List finalize(List<int> encoded, {bool? rightToLeft}) {
    final archive = ZipDecoder().decodeBytes(encoded, verify: true);

    for (var index = 0; index < archive.length; index++) {
      final file = archive[index];
      if (!file.isFile || !_worksheetPath.hasMatch(file.name)) continue;

      final original = utf8.decode(file.content as List<int>);
      final normalized = _normalizeWorksheet(
        original,
        rightToLeft: rightToLeft,
      );
      if (normalized == original) continue;

      final replacementBytes = Uint8List.fromList(utf8.encode(normalized));
      final replacement =
          ArchiveFile(file.name, replacementBytes.length, replacementBytes)
            ..mode = file.mode
            ..ownerId = file.ownerId
            ..groupId = file.groupId
            ..lastModTime = file.lastModTime
            ..comment = file.comment
            ..compress = file.compress;
      archive[index] = replacement;
    }

    final result = ZipEncoder().encode(archive);
    if (result == null || result.isEmpty) {
      throw StateError('Unable to finalize XLSX package.');
    }

    // Fail closed if repacking introduced a CRC/central-directory problem.
    ZipDecoder().decodeBytes(result, verify: true);
    return Uint8List.fromList(result);
  }

  static String _normalizeWorksheet(String xml, {bool? rightToLeft}) {
    var result = _normalizeDimension(xml);
    result = _normalizeSheetDirection(result, rightToLeft);
    result = _normalizeSheetFormatOrder(result);
    _assertWorksheetInvariants(result);
    return result;
  }

  static String _normalizeDimension(String xml) {
    final bounds = _usedRange(xml);
    if (bounds == null) return xml;

    final reference = bounds.reference;
    final dimension = _dimensionElement.firstMatch(xml);
    if (dimension != null) {
      return xml.replaceRange(
        dimension.start,
        dimension.end,
        '<dimension ref="$reference"/>',
      );
    }

    final insertionPoint = _dimensionInsertionPoint(xml);
    return xml.replaceRange(
      insertionPoint,
      insertionPoint,
      '<dimension ref="$reference"/>',
    );
  }

  // R57_XLSX_RTL_V3
  static String _normalizeSheetDirection(String xml, bool? rightToLeft) {
    if (rightToLeft == null) return xml;

    final sheetView = RegExp(r'<sheetView\b[^>]*>').firstMatch(xml);
    if (sheetView != null) {
      var element = sheetView.group(0)!;
      element = element.replaceAll(RegExp(r'\s+rightToLeft="[^"]*"'), '');

      if (rightToLeft) {
        if (element.endsWith('/>')) {
          element =
              '${element.substring(0, element.length - 2)} rightToLeft="1"/>';
        } else {
          element =
              '${element.substring(0, element.length - 1)} rightToLeft="1">';
        }
      }

      return xml.replaceRange(sheetView.start, sheetView.end, element);
    }

    if (!rightToLeft) return xml;

    final existingViews = _sheetViewsElement.firstMatch(xml);
    if (existingViews != null) {
      final element = existingViews.group(0)!;

      if (element.endsWith('/>')) {
        return xml.replaceRange(
          existingViews.start,
          existingViews.end,
          '<sheetViews><sheetView workbookViewId="0" '
          'rightToLeft="1"/></sheetViews>',
        );
      }

      final closingIndex = element.lastIndexOf('</sheetViews>');
      if (closingIndex >= 0) {
        final replacement =
            '${element.substring(0, closingIndex)}'
            '<sheetView workbookViewId="0" rightToLeft="1"/>'
            '${element.substring(closingIndex)}';

        return xml.replaceRange(
          existingViews.start,
          existingViews.end,
          replacement,
        );
      }
    }

    final dimension = _dimensionElement.firstMatch(xml);
    final insertionPoint = dimension?.end ?? _dimensionInsertionPoint(xml);

    return xml.replaceRange(
      insertionPoint,
      insertionPoint,
      '<sheetViews><sheetView workbookViewId="0" '
      'rightToLeft="1"/></sheetViews>',
    );
  }

  static String _normalizeSheetFormatOrder(String xml) {
    final format = _sheetFormatElement.firstMatch(xml);
    if (format == null) return xml;

    final element = format.group(0)!;
    var result = xml.replaceRange(format.start, format.end, '');

    final views = _sheetViewsElement.firstMatch(result);
    if (views != null) {
      return result.replaceRange(views.end, views.end, element);
    }

    final dimension = _dimensionElement.firstMatch(result);
    final insertionPoint = dimension?.end ?? _dimensionInsertionPoint(result);
    return result.replaceRange(insertionPoint, insertionPoint, element);
  }

  static int _dimensionInsertionPoint(String xml) {
    final sheetPr = _sheetPrElement.firstMatch(xml);
    if (sheetPr != null) return sheetPr.end;

    final worksheetStart = xml.indexOf('<worksheet');
    if (worksheetStart < 0) {
      throw FormatException('Worksheet root element is missing.');
    }
    final rootEnd = xml.indexOf('>', worksheetStart);
    if (rootEnd < 0) {
      throw FormatException('Worksheet root element is malformed.');
    }
    return rootEnd + 1;
  }

  static _CellRange? _usedRange(String xml) {
    int? minColumn;
    int? minRow;
    int? maxColumn;
    int? maxRow;

    void include(String rawReference) {
      for (final rawCell in rawReference.split(':')) {
        final cell = _parseCellReference(rawCell);
        if (cell == null) continue;
        minColumn = minColumn == null
            ? cell.column
            : (cell.column < minColumn! ? cell.column : minColumn);
        minRow = minRow == null
            ? cell.row
            : (cell.row < minRow! ? cell.row : minRow);
        maxColumn = maxColumn == null
            ? cell.column
            : (cell.column > maxColumn! ? cell.column : maxColumn);
        maxRow = maxRow == null
            ? cell.row
            : (cell.row > maxRow! ? cell.row : maxRow);
      }
    }

    for (final match in _cellReference.allMatches(xml)) {
      include(match.group(1)!);
    }
    for (final match in _mergeReference.allMatches(xml)) {
      include(match.group(1)!);
    }

    if (minColumn == null ||
        minRow == null ||
        maxColumn == null ||
        maxRow == null) {
      return null;
    }
    return _CellRange(
      minColumn: minColumn!,
      minRow: minRow!,
      maxColumn: maxColumn!,
      maxRow: maxRow!,
    );
  }

  static _CellReference? _parseCellReference(String raw) {
    final normalized = raw.replaceAll(r'$', '').trim().toUpperCase();
    final match = RegExp(r'^([A-Z]+)([1-9][0-9]*)$').firstMatch(normalized);
    if (match == null) return null;

    var column = 0;
    for (final unit in match.group(1)!.codeUnits) {
      column = column * 26 + (unit - 64);
    }
    return _CellReference(column: column, row: int.parse(match.group(2)!));
  }

  static String _columnName(int column) {
    if (column <= 0) throw RangeError.value(column, 'column');
    final units = <int>[];
    var value = column;
    while (value > 0) {
      value--;
      units.add(65 + value % 26);
      value ~/= 26;
    }
    return String.fromCharCodes(units.reversed);
  }

  static void _assertWorksheetInvariants(String xml) {
    final dimension = _dimensionElement.firstMatch(xml);
    final format = _sheetFormatElement.firstMatch(xml);
    final views = _sheetViewsElement.firstMatch(xml);
    final colsIndex = xml.indexOf('<cols');
    final dataIndex = xml.indexOf('<sheetData');

    if (format != null) {
      if (dimension != null && format.start < dimension.end) {
        throw StateError(
          'Invalid XLSX worksheet order: sheetFormatPr/dimension.',
        );
      }
      if (views != null && format.start < views.end) {
        throw StateError(
          'Invalid XLSX worksheet order: sheetFormatPr/sheetViews.',
        );
      }
      if (colsIndex >= 0 && format.end > colsIndex) {
        throw StateError('Invalid XLSX worksheet order: sheetFormatPr/cols.');
      }
      if (dataIndex >= 0 && format.end > dataIndex) {
        throw StateError(
          'Invalid XLSX worksheet order: sheetFormatPr/sheetData.',
        );
      }
    }

    final bounds = _usedRange(xml);
    if (bounds != null &&
        dimension?.group(0) != '<dimension ref="${bounds.reference}"/>') {
      throw StateError('Invalid XLSX worksheet dimension.');
    }
  }
}

class _CellReference {
  const _CellReference({required this.column, required this.row});

  final int column;
  final int row;
}

class _CellRange {
  const _CellRange({
    required this.minColumn,
    required this.minRow,
    required this.maxColumn,
    required this.maxRow,
  });

  final int minColumn;
  final int minRow;
  final int maxColumn;
  final int maxRow;

  String get reference {
    final first = '${XlsxIntegrity._columnName(minColumn)}$minRow';
    final last = '${XlsxIntegrity._columnName(maxColumn)}$maxRow';
    return first == last ? first : '$first:$last';
  }
}
