import 'dart:typed_data';

import 'binary_download_service_stub.dart'
    if (dart.library.html) 'binary_download_service_web.dart'
    as implementation;

abstract final class BinaryDownloadService {
  static Future<void> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) => implementation.saveBinary(
    fileName: fileName,
    bytes: bytes,
    mimeType: mimeType,
  );
}
