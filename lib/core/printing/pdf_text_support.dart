import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfFontPack {
  const PdfFontPack({required this.regular, required this.bold});

  final pw.Font regular;
  final pw.Font bold;
}

abstract final class PdfTextSupport {
  static Future<PdfFontPack>? _fontFuture;
  static PdfFontPack? _loadedFonts;

  static const Map<int, int> _windows1252Bytes = <int, int>{
    0x20AC: 0x80,
    0x201A: 0x82,
    0x0192: 0x83,
    0x201E: 0x84,
    0x2026: 0x85,
    0x2020: 0x86,
    0x2021: 0x87,
    0x02C6: 0x88,
    0x2030: 0x89,
    0x0160: 0x8A,
    0x2039: 0x8B,
    0x0152: 0x8C,
    0x017D: 0x8E,
    0x2018: 0x91,
    0x2019: 0x92,
    0x201C: 0x93,
    0x201D: 0x94,
    0x2022: 0x95,
    0x2013: 0x96,
    0x2014: 0x97,
    0x02DC: 0x98,
    0x2122: 0x99,
    0x0161: 0x9A,
    0x203A: 0x9B,
    0x0153: 0x9C,
    0x017E: 0x9E,
    0x0178: 0x9F,
  };

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
    final pack = PdfFontPack(
      regular: pw.Font.ttf(regular),
      bold: pw.Font.ttf(bold),
    );
    _loadedFonts = pack;
    return pack;
  }

  static String _repairUtf8Mojibake(String text) {
    if (!text.contains('Ø') &&
        !text.contains('Ù') &&
        !text.contains('Ã') &&
        !text.contains('Â')) {
      return text;
    }

    final bytes = <int>[];
    for (final rune in text.runes) {
      final windowsByte = _windows1252Bytes[rune];
      if (windowsByte != null) {
        bytes.add(windowsByte);
      } else if (rune <= 0xFF) {
        bytes.add(rune);
      } else {
        return text;
      }
    }

    try {
      return utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      return text;
    }
  }

  static String sanitize(Object? value, {bool singleLine = false}) {
    var text = _repairUtf8Mojibake(value?.toString() ?? '');
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
    final regular = _loadedFonts?.regular;
    final effectiveStyle = regular != null && style?.font == null
        ? (style ?? const pw.TextStyle()).copyWith(font: regular)
        : style;
    return pw.Text(
      clean,
      style: effectiveStyle,
      maxLines: maxLines,
      textDirection: arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      textAlign: textAlign ?? (arabic ? pw.TextAlign.right : pw.TextAlign.left),
    );
  }
}
