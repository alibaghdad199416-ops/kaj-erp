import 'dart:typed_data';

import 'excel_download_service_stub.dart'
    if (dart.library.html) 'excel_download_service_web.dart'
    as implementation;

/// Saves an XLSX payload using a browser-native download on Flutter Web and
/// FileSaver on native platforms. The web path avoids plugin/runtime issues
/// observed with older file_saver releases in Edge/Chrome.
class ExcelDownloadService {
  const ExcelDownloadService._();

  static Future<void> save({
    required String fileName,
    required Uint8List bytes,
  }) => implementation.saveExcel(fileName: fileName, bytes: bytes);
}
