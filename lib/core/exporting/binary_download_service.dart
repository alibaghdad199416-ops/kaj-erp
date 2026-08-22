import 'dart:typed_data';

import 'binary_download_service_stub.dart'
    if (dart.library.html) 'binary_download_service_web.dart'
    as implementation;
import 'export_payload_validator.dart';

abstract final class BinaryDownloadService {
  static Future<void> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) {
    final normalizedName = ExportPayloadValidator.validate(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
    );
    return implementation.saveBinary(
      fileName: normalizedName,
      bytes: bytes,
      mimeType: mimeType,
    );
  }
}
