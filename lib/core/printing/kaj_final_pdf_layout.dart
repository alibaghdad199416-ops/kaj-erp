import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_text_support.dart';

abstract final class KajFinalPdfLayout {
  static const PdfColor ink = PdfColor.fromInt(0xFF172126);
  static const PdfColor accent = PdfColor.fromInt(0xFF43B8BE);
  static const PdfColor line = PdfColor.fromInt(0xFFD9E0E3);
  static const PdfColor stripe = PdfColor.fromInt(0xFFF4F7F8);

  static pw.PageTheme pageTheme(PdfFontPack fonts, {bool landscape = false}) =>
      pw.PageTheme(
        pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 26, 28, 28),
        theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
      );

  static pw.Widget title(String title, {String? subtitle}) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 10),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: accent, width: 1.5)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        PdfTextSupport.text(
          title,
          style: pw.TextStyle(
            fontSize: 17,
            fontWeight: pw.FontWeight.bold,
            color: ink,
          ),
        ),
        if (subtitle != null) ...[
          pw.SizedBox(height: 3),
          PdfTextSupport.text(
            subtitle,
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ],
    ),
  );

  static pw.Widget compactTable({
    required List<String> headers,
    required List<List<String>> rows,
  }) => pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    border: pw.TableBorder.all(color: line, width: .45),
    headerDecoration: const pw.BoxDecoration(color: ink),
    headerStyle: pw.TextStyle(
      color: PdfColors.white,
      fontSize: 8,
      fontWeight: pw.FontWeight.bold,
    ),
    cellStyle: const pw.TextStyle(fontSize: 7.5, color: ink),
    oddRowDecoration: const pw.BoxDecoration(color: stripe),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    headerAlignment: pw.Alignment.center,
    cellAlignments: {
      for (var i = 0; i < headers.length; i++) i: pw.Alignment.center,
    },
  );
}
