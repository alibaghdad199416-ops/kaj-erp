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

  var opened = false;

  try {
    html.window.open(url, '_blank');

    opened = true;
  } catch (_) {
    opened = false;
  }

  if (!opened) {
    final anchor = html.AnchorElement(href: url)
      ..download = safeFileName
      ..target = '_blank'
      ..rel = 'noopener'
      ..style.display = 'none';

    html.document.body?.children.add(anchor);

    try {
      anchor.click();
    } finally {
      anchor.remove();
    }
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
