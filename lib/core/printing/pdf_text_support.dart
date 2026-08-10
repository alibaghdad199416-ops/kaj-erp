import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class PdfFontPack {
  const PdfFontPack({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;
}

abstract final class PdfTextSupport {
  static Future<PdfFontPack>? _fontFuture;

  /// Browser PDF output is canonical English. The built-in browser-safe PDF
  /// fonts cover Latin reliably and avoid AssetManifest/font-CDN failures.
  /// Arabic PDF output remains available on non-Web platforms where Noto can
  /// be loaded without the Flutter Web asset-manifest path.
  static String canonicalPdfLanguage(String requested) =>
      kIsWeb ? 'en' : (requested.toLowerCase().startsWith('ar') ? 'ar' : 'en');

  static bool canonicalPdfArabic(bool requested) => !kIsWeb && requested;

  static Future<PdfFontPack> loadFonts() => _fontFuture ??= _loadFonts();

  static Future<PdfFontPack> _loadFonts() async {
    // PdfGoogleFonts consults AssetManifest.json on Flutter Web. Modern Flutter
    // debug servers expose AssetManifest.bin instead, which produced a noisy
    // 404 and could abort exports. Browser exports are English-first and use
    // built-in PDF fonts; Arabic/native exports keep Noto support.
    if (kIsWeb) {
      return PdfFontPack(
        regular: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      );
    }
    try {
      // Noto Naskh contains Arabic and Latin glyphs. Using one font family for
      // both languages avoids mixed baselines and missing-glyph squares inside
      // the same table cell.
      return PdfFontPack(
        regular: await PdfGoogleFonts.notoNaskhArabicRegular(),
        bold: await PdfGoogleFonts.notoNaskhArabicBold(),
      );
    } catch (_) {
      // Native Arabic output must never silently fall back to a Latin-only
      // font because that produces corrupted Arabic glyphs. Let the caller
      // surface a localized error instead. Browser output never reaches this
      // branch because canonicalPdfLanguage/canonicalPdfArabic force English.
      rethrow;
    }
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
