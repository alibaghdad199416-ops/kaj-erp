import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'pdf_text_support.dart';
import 'unified_pdf_identity.dart';

/// Canonical printable chrome for every Quality Line ERP document.
///
/// Commercial documents, accounting reports, vouchers, warehouse documents and
/// management reports must use these primitives instead of inventing their own
/// header/table/footer language. The structure intentionally follows the
/// approved KAJ / Quality Line commercial-document visual system.
abstract final class UnifiedPdfDocument {
  static pw.PageTheme pageTheme(
    PdfFontPack fonts, {
    bool landscape = false,
    pw.TextDirection textDirection = pw.TextDirection.ltr,
  }) => pw.PageTheme(
    pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(
      UnifiedPdfIdentity.pageMarginHorizontal,
      UnifiedPdfIdentity.pageMarginTop,
      UnifiedPdfIdentity.pageMarginHorizontal,
      UnifiedPdfIdentity.pageMarginBottom,
    ),
    theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
    textDirection: textDirection,
  );

  static pw.Widget documentHeader({
    required pw.Font bold,
    required String documentType,
    required String documentNumber,
    pw.MemoryImage? logo,
    String brandMark = 'KAJ',
    String companyName = 'Quality Line',
  }) => pw.Container(
    height: 72,
    padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    decoration: const pw.BoxDecoration(
      color: UnifiedPdfIdentity.ink,
      border: pw.Border(
        bottom: pw.BorderSide(color: UnifiedPdfIdentity.accent, width: 3),
      ),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (logo != null) ...[
          pw.Container(
            width: 46,
            height: 46,
            padding: const pw.EdgeInsets.all(3),
            decoration: pw.BoxDecoration(
              color: UnifiedPdfIdentity.white,
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Image(logo, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 12),
        ] else ...[
          PdfTextSupport.text(
            brandMark,
            style: pw.TextStyle(
              font: bold,
              fontSize: 21,
              color: UnifiedPdfIdentity.white,
            ),
          ),
          pw.SizedBox(width: 14),
        ],
        pw.Container(width: 1.5, height: 38, color: UnifiedPdfIdentity.accent),
        pw.SizedBox(width: 14),
        pw.Expanded(
          child: PdfTextSupport.text(
            companyName,
            maxLines: 1,
            style: pw.TextStyle(
              font: bold,
              fontSize: 18,
              color: UnifiedPdfIdentity.white,
            ),
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Container(
          constraints: const pw.BoxConstraints(minWidth: 102, maxWidth: 160),
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            color: UnifiedPdfIdentity.white,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            children: [
              PdfTextSupport.text(
                documentType,
                textAlign: pw.TextAlign.center,
                maxLines: 2,
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 9,
                  color: UnifiedPdfIdentity.ink,
                ),
              ),
              if (documentNumber.trim().isNotEmpty) ...[
                pw.SizedBox(height: 3),
                PdfTextSupport.text(
                  documentNumber,
                  textAlign: pw.TextAlign.center,
                  maxLines: 1,
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 8,
                    color: UnifiedPdfIdentity.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  static pw.Widget titleBlock({
    required pw.Font bold,
    required String title,
    String? subtitle,
    String? status,
  }) => pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(top: 10, bottom: 10),
    padding: const pw.EdgeInsets.fromLTRB(14, 11, 14, 11),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        left: pw.BorderSide(color: UnifiedPdfIdentity.accent, width: 4),
        bottom: pw.BorderSide(color: UnifiedPdfIdentity.border, width: .6),
      ),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              PdfTextSupport.text(
                title,
                style: pw.TextStyle(
                  font: bold,
                  fontSize: 18,
                  color: UnifiedPdfIdentity.ink,
                ),
              ),
              if (subtitle?.trim().isNotEmpty == true) ...[
                pw.SizedBox(height: 3),
                PdfTextSupport.text(
                  subtitle!,
                  style: const pw.TextStyle(
                    fontSize: 8.5,
                    color: UnifiedPdfIdentity.muted,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (status?.trim().isNotEmpty == true)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: pw.BoxDecoration(
              color: UnifiedPdfIdentity.accentSoft,
              border: pw.Border.all(color: UnifiedPdfIdentity.accent, width: .7),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: PdfTextSupport.text(
              status!,
              style: pw.TextStyle(
                font: bold,
                fontSize: 8,
                color: UnifiedPdfIdentity.ink,
              ),
            ),
          ),
      ],
    ),
  );

  static pw.Widget sectionHeader({
    required pw.Font bold,
    required String title,
    String? trailing,
  }) => pw.Container(
    width: double.infinity,
    margin: const pw.EdgeInsets.only(top: 9, bottom: 5),
    padding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 7),
    decoration: const pw.BoxDecoration(
      color: UnifiedPdfIdentity.ink,
      border: pw.Border(
        bottom: pw.BorderSide(color: UnifiedPdfIdentity.accent, width: 2.5),
      ),
    ),
    child: pw.Row(
      children: [
        pw.Container(width: 4, height: 15, color: UnifiedPdfIdentity.accent),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: PdfTextSupport.text(
            title,
            style: pw.TextStyle(
              font: bold,
              fontSize: 10,
              color: UnifiedPdfIdentity.white,
            ),
          ),
        ),
        if (trailing?.trim().isNotEmpty == true)
          PdfTextSupport.text(
            trailing!,
            style: const pw.TextStyle(
              fontSize: 7,
              color: UnifiedPdfIdentity.white,
            ),
          ),
      ],
    ),
  );

  static pw.Widget summaryTile({
    required pw.Font bold,
    required String label,
    required String value,
    double width = 150,
  }) => pw.Container(
    width: width,
    padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 8),
    decoration: pw.BoxDecoration(
      color: UnifiedPdfIdentity.surface,
      border: pw.Border.all(color: UnifiedPdfIdentity.border, width: .55),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        PdfTextSupport.text(
          label,
          maxLines: 1,
          style: const pw.TextStyle(
            fontSize: 6.8,
            color: UnifiedPdfIdentity.muted,
          ),
        ),
        pw.SizedBox(height: 3),
        PdfTextSupport.text(
          value,
          maxLines: 2,
          style: pw.TextStyle(
            font: bold,
            fontSize: 9,
            color: UnifiedPdfIdentity.ink,
          ),
        ),
      ],
    ),
  );

  static pw.Widget table({
    required pw.Font regular,
    required pw.Font bold,
    required List<String> headers,
    required List<List<String>> rows,
    bool arabic = false,
    Map<int, pw.TableColumnWidth>? columnWidths,
  }) => pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    border: pw.TableBorder.all(color: UnifiedPdfIdentity.border, width: .45),
    headerDecoration: const pw.BoxDecoration(color: UnifiedPdfIdentity.tableHeader),
    oddRowDecoration: const pw.BoxDecoration(color: UnifiedPdfIdentity.surface),
    headerStyle: pw.TextStyle(
      font: bold,
      color: UnifiedPdfIdentity.white,
      fontSize: UnifiedPdfIdentity.tableHeaderFontSize,
    ),
    cellStyle: pw.TextStyle(
      font: regular,
      color: UnifiedPdfIdentity.ink,
      fontSize: UnifiedPdfIdentity.tableCellFontSize,
    ),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    cellAlignment: arabic ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
    headerAlignment: pw.Alignment.center,
    columnWidths: columnWidths,
  );

  static pw.Widget signatureBox({
    required pw.Font bold,
    required String title,
  }) => pw.Expanded(
    child: pw.Container(
      height: 64,
      padding: const pw.EdgeInsets.all(7),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: UnifiedPdfIdentity.border, width: .55),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          PdfTextSupport.text(
            title,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: bold, fontSize: 7.5),
          ),
          pw.Container(height: .6, color: UnifiedPdfIdentity.accent),
        ],
      ),
    ),
  );

  static pw.Widget footer({
    required pw.Font regular,
    required int pageNumber,
    required int pageCount,
    required bool arabic,
  }) => pw.Container(
    padding: const pw.EdgeInsets.only(top: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(color: UnifiedPdfIdentity.accent, width: 1.2),
      ),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        PdfTextSupport.text(
          arabic
              ? 'تم إنشاؤه إلكترونيًا بواسطة نظام خط الجودة'
              : 'Generated electronically by Quality Line ERP',
          style: pw.TextStyle(
            font: regular,
            fontSize: 6.5,
            color: UnifiedPdfIdentity.muted,
          ),
        ),
        PdfTextSupport.text(
          '$pageNumber / $pageCount',
          style: pw.TextStyle(
            font: regular,
            fontSize: 6.5,
            color: UnifiedPdfIdentity.muted,
          ),
        ),
      ],
    ),
  );
}
