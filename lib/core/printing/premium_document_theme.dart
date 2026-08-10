import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Shared visual identity for every printable Quality Line document.
abstract final class PremiumDocumentTheme {
  static final ink = PdfColor.fromHex('#101820');
  static final accent = PdfColor.fromHex('#62BEC1');
  static final accentSoft = PdfColor.fromHex('#E8F6F6');
  static final surface = PdfColor.fromHex('#F5F7F8');
  static final border = PdfColor.fromHex('#D6DEE3');
  static final muted = PdfColor.fromHex('#5F6B73');

  static pw.BoxDecoration headerDecoration({double radius = 8}) =>
      pw.BoxDecoration(
        color: ink,
        borderRadius: pw.BorderRadius.circular(radius),
        border: pw.Border(bottom: pw.BorderSide(color: accent, width: 3)),
      );

  static pw.BoxDecoration infoDecoration({double radius = 6}) =>
      pw.BoxDecoration(
        color: accentSoft,
        borderRadius: pw.BorderRadius.circular(radius),
        border: pw.Border.all(color: accent, width: .7),
      );

  static pw.TextStyle footerStyle(pw.Font regular) =>
      pw.TextStyle(font: regular, fontSize: 7, color: muted);
}
