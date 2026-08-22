import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../printing/pdf_text_support.dart';

/// Builds readable PDF tables by splitting wide reports into column groups and
/// long reports into bounded row chunks. Every chunk repeats its headers, so a
/// page never begins with orphaned data whose column meaning is unclear.
abstract final class AdaptivePdfTable {
  static List<pw.Widget> build({
    required List<String> headers,
    required List<List<String>> rows,
    required pw.Font regular,
    required pw.Font bold,
    required bool arabic,
    PdfColor headerColor = PdfColors.grey700,
    PdfColor alternateColor = PdfColors.grey100,
    int maxColumnsPerGroup = 6,
    int maxRowsPerChunk = 14,
  }) {
    if (headers.isEmpty) return const <pw.Widget>[];
    final groups = <List<int>>[];
    for (var index = 0; index < headers.length; index += maxColumnsPerGroup) {
      groups.add(
        List<int>.generate(
          (index + maxColumnsPerGroup > headers.length)
              ? headers.length - index
              : maxColumnsPerGroup,
          (offset) => index + offset,
        ),
      );
    }

    final chunks = <List<List<String>>>[];
    if (rows.isEmpty) {
      chunks.add(const <List<String>>[]);
    } else {
      final safeChunkSize = maxRowsPerChunk.clamp(1, 40).toInt();
      for (var offset = 0; offset < rows.length; offset += safeChunkSize) {
        final end = (offset + safeChunkSize).clamp(0, rows.length).toInt();
        chunks.add(rows.sublist(offset, end));
      }
    }

    final widgets = <pw.Widget>[];
    var emittedSection = false;
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      for (var chunkIndex = 0; chunkIndex < chunks.length; chunkIndex++) {
        if (emittedSection) widgets.add(pw.NewPage());
        emittedSection = true;
        if (groups.length > 1 || chunks.length > 1) {
          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: PdfTextSupport.text(
                _sectionLabel(
                  arabic: arabic,
                  groupIndex: groupIndex,
                  groupCount: groups.length,
                  chunkIndex: chunkIndex,
                  chunkCount: chunks.length,
                ),
                style: pw.TextStyle(font: bold, fontSize: 7.5),
              ),
            ),
          );
        }
        widgets.add(
          _table(
            indexes: groups[groupIndex],
            headers: headers,
            rows: chunks[chunkIndex],
            regular: regular,
            bold: bold,
            arabic: arabic,
            headerColor: headerColor,
            alternateColor: alternateColor,
          ),
        );
      }
    }
    return widgets;
  }

  static String _sectionLabel({
    required bool arabic,
    required int groupIndex,
    required int groupCount,
    required int chunkIndex,
    required int chunkCount,
  }) {
    final columnPart = groupCount <= 1
        ? ''
        : (arabic
              ? 'مجموعة الأعمدة ${groupIndex + 1} من $groupCount'
              : 'Column group ${groupIndex + 1} of $groupCount');
    final pagePart = chunkCount <= 1
        ? ''
        : (arabic
              ? 'صفحة البيانات ${chunkIndex + 1} من $chunkCount'
              : 'Data page ${chunkIndex + 1} of $chunkCount');
    return <String>[
      columnPart,
      pagePart,
    ].where((value) => value.isNotEmpty).join(' - ');
  }

  static pw.Widget _table({
    required List<int> indexes,
    required List<String> headers,
    required List<List<String>> rows,
    required pw.Font regular,
    required pw.Font bold,
    required bool arabic,
    required PdfColor headerColor,
    required PdfColor alternateColor,
  }) {
    final widths = <int, pw.TableColumnWidth>{};
    for (var local = 0; local < indexes.length; local++) {
      final index = indexes[local];
      final longest = <String>[
        headers[index],
        ...rows.map((row) => index < row.length ? row[index] : ''),
      ].fold<int>(0, (max, value) => value.length > max ? value.length : max);
      widths[local] = pw.FlexColumnWidth(
        longest >= 28
            ? 2.0
            : longest >= 16
            ? 1.45
            : 1.0,
      );
    }
    return pw.Table(
      columnWidths: widths,
      border: pw.TableBorder.all(color: PdfColors.grey400, width: .35),
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: headerColor),
          children: [
            for (final index in indexes)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 5,
                ),
                alignment: pw.Alignment.center,
                child: PdfTextSupport.text(
                  headers[index],
                  textAlign: pw.TextAlign.center,
                  maxLines: 3,
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 7,
                    color: PdfColors.white,
                    lineSpacing: 1.2,
                  ),
                ),
              ),
          ],
        ),
        if (rows.isEmpty)
          pw.TableRow(
            children: [
              for (var index = 0; index < indexes.length; index++)
                pw.Container(
                  height: 24,
                  alignment: pw.Alignment.center,
                  child: index == 0
                      ? PdfTextSupport.text(
                          arabic ? 'لا توجد بيانات' : 'No data',
                          style: pw.TextStyle(font: regular, fontSize: 7),
                        )
                      : pw.SizedBox(),
                ),
            ],
          ),
        for (var rowIndex = 0; rowIndex < rows.length; rowIndex++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: rowIndex.isOdd ? alternateColor : PdfColors.white,
            ),
            children: [
              for (final index in indexes)
                pw.Container(
                  constraints: const pw.BoxConstraints(minHeight: 22),
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  alignment: arabic
                      ? pw.Alignment.centerRight
                      : pw.Alignment.centerLeft,
                  child: PdfTextSupport.text(
                    index < rows[rowIndex].length ? rows[rowIndex][index] : '',
                    textAlign: arabic ? pw.TextAlign.right : pw.TextAlign.left,
                    maxLines: 5,
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 6.8,
                      lineSpacing: 1.1,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
