import 'dart:typed_data';

/// Validates the final payload at the shared delivery boundary.
///
/// Builders remain responsible for document content. This guard prevents a
/// browser or native adapter from reporting success for an empty/corrupt file.
abstract final class ExportPayloadValidator {
  static String validate({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) {
    if (bytes.isEmpty) {
      throw StateError('Export payload is empty.');
    }

    final normalizedMimeType = mimeType.trim().toLowerCase();
    if (normalizedMimeType.isEmpty) {
      throw ArgumentError.value(mimeType, 'mimeType', 'MIME type is required.');
    }

    var normalizedName = fileName.trim();
    if (normalizedName.isEmpty) normalizedName = 'quality-line-export';

    if (normalizedMimeType == 'application/pdf') {
      if (!_hasPdfSignature(bytes)) {
        throw StateError('Export payload is not a valid PDF document.');
      }
      if (!normalizedName.toLowerCase().endsWith('.pdf')) {
        normalizedName = '$normalizedName.pdf';
      }
    }

    return normalizedName;
  }

  static bool _hasPdfSignature(Uint8List bytes) =>
      bytes.length >= 5 &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46 &&
      bytes[4] == 0x2d;
}
