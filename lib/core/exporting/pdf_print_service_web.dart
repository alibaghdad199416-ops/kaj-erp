// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> printPdf({
  required String fileName,
  required Uint8List bytes,
}) async {
  final safeFileName = _normalizePdfFileName(fileName);

  final blob = html.Blob(<Object>[bytes], 'application/pdf');

  final url = html.Url.createObjectUrlFromBlob(blob);

  // PDF generation is asynchronous, so window.open() no longer runs inside
  // the original browser user-activation turn and Edge may silently block it.
  // A Blob download anchor is supported after async work and is consistent
  // with the Excel/binary export path.
  final anchor = html.AnchorElement(href: url)
    ..download = safeFileName
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  try {
    anchor.click();
  } finally {
    anchor.remove();
  }

  unawaited(
    Future<void>.delayed(const Duration(minutes: 2), () {
      html.Url.revokeObjectUrl(url);
    }),
  );
}

String _normalizePdfFileName(String fileName) {
  final trimmed = fileName.trim();

  if (trimmed.isEmpty) {
    return 'document.pdf';
  }

  if (trimmed.toLowerCase().endsWith('.pdf')) {
    return trimmed;
  }

  return '$trimmed.pdf';
}
