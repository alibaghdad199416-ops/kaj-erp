import 'dart:typed_data';

import 'binary_download_service_web.dart' as browser_download;

Future<void> printPdf({
  required String fileName,
  required Uint8List bytes,
}) async {
  // PDF generation is asynchronous, so window.open() no longer runs inside
  // the original browser user-activation turn and Edge may silently block it.
  // A Blob download anchor is supported after async work and is consistent
  // with the Excel/binary export path.
  await browser_download.saveBinary(
    fileName: fileName,
    bytes: bytes,
    mimeType: 'application/pdf',
  );
}
