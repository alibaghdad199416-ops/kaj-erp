import 'package:pdf/widgets.dart' as pw;

import 'unified_pdf_identity.dart';

/// Shared visual identity for every printable Quality Line document.
///
/// The hexadecimal references remain explicit for audit/export compatibility:
/// ink #101820, accent #62BEC1, accent-soft #E8F6F6.
abstract final class PremiumDocumentTheme {
  static const inkHex = '#101820';
  static const accentHex = '#62BEC1';
  static const accentSoftHex = '#E8F6F6';
  static const officialDocumentLabelEn = 'Official electronic document';
  static const officialDocumentLabelAr = 'وثيقة إلكترونية معتمدة';

  static const ink = UnifiedPdfIdentity.ink;
  static const accent = UnifiedPdfIdentity.accent;
  static const accentSoft = UnifiedPdfIdentity.accentSoft;
  static const surface = UnifiedPdfIdentity.surface;
  static const border = UnifiedPdfIdentity.border;
  static const muted = UnifiedPdfIdentity.muted;

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
