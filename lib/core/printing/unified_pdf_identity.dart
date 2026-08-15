import 'package:pdf/pdf.dart';

/// Canonical visual identity for every PDF/report produced by the ERP.
abstract final class UnifiedPdfIdentity {
  static const PdfColor ink = PdfColor.fromInt(0xFF172126);
  static const PdfColor accent = PdfColor.fromInt(0xFF43B8BE);
  static const PdfColor accentSoft = PdfColor.fromInt(0xFFE7F6F7);
  static const PdfColor surface = PdfColor.fromInt(0xFFF4F7F8);
  static const PdfColor border = PdfColor.fromInt(0xFFD9E0E3);
  static const PdfColor muted = PdfColor.fromInt(0xFF5F6B73);
  static const PdfColor tableHeader = PdfColor.fromInt(0xFF6B6E72);
  static const PdfColor white = PdfColors.white;

  static const double pageMarginHorizontal = 28;
  static const double pageMarginTop = 22;
  static const double pageMarginBottom = 24;
  static const double tableHeaderFontSize = 7.5;
  static const double tableCellFontSize = 7.1;
}
