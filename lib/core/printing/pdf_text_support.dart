import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfFontPack {
  const PdfFontPack({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;
}

abstract final class PdfTextSupport {
  static Future<PdfFontPack>? _fontFuture;

  static String canonicalPdfLanguage(String requested) =>
      requested.toLowerCase().startsWith('ar') ? 'ar' : 'en';

  static bool canonicalPdfArabic(bool requested) => requested;

  static Future<PdfFontPack> loadFonts() => _fontFuture ??= _loadFonts();

  static Future<PdfFontPack> _loadFonts() async {
    // Bundle the fonts so Edge exports do not depend on popup/CDN policy or
    // the deprecated JSON AssetManifest endpoint.
    final regular = await rootBundle.load(
      'assets/fonts/NotoNaskhArabic-Regular.ttf',
    );
    final bold = await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf');
    return PdfFontPack(regular: pw.Font.ttf(regular), bold: pw.Font.ttf(bold));
  }

  static String sanitize(Object? value, {bool singleLine = false}) {
    var text = value?.toString() ?? '';
    text = text
        .replaceAll('\uFFFD', '')
        .replaceAll(RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069]'), '')
        .replaceAll('•', ' - ')
        .replaceAll('—', ' - ')
        .replaceAll('–', '-')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), ' ')
        .replaceAll('\t', ' ');
    if (singleLine) text = text.replaceAll(RegExp(r'[\r\n]+'), ' ');
    return text.replaceAll(RegExp(r' {2,}'), ' ').trim();
  }

  static String filePart(Object? value) {
    final clean = sanitize(value, singleLine: true)
        .replaceAll(RegExp(r'[^A-Za-z0-9\u0600-\u06FF_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return clean.isEmpty ? 'quality-line-report' : clean;
  }

  static bool containsArabic(Object? value) =>
      RegExp(r'[؀-ۿ]').hasMatch(value?.toString() ?? '');

  static pw.TextDirection directionFor(Object? value) =>
      containsArabic(value) ? pw.TextDirection.rtl : pw.TextDirection.ltr;

  static pw.Alignment alignmentFor(Object? value) => containsArabic(value)
      ? pw.Alignment.centerRight
      : pw.Alignment.centerLeft;

  static pw.Text text(
    Object? value, {
    pw.TextStyle? style,
    int? maxLines,
    pw.TextAlign? textAlign,
  }) {
    final clean = sanitize(value);
    final arabic = containsArabic(clean);
    return pw.Text(
      clean,
      style: style,
      maxLines: maxLines,
      textDirection: arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      textAlign: textAlign ?? (arabic ? pw.TextAlign.right : pw.TextAlign.left),
    );
  }
}
