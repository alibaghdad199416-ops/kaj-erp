import 'dart:typed_data';

import 'pdf_print_service_stub.dart'
    if (dart.library.html) 'pdf_print_service_web.dart'
    as implementation;
import 'export_payload_validator.dart';

/// Cross-platform PDF print/preview entry point.
///
/// On Flutter Web we deliberately avoid Printing.layoutPdf because browser
/// plugin/asset failures can reject an otherwise valid PDF. Downloading the
/// generated Blob avoids popup blockers after asynchronous PDF generation.
abstract final class PdfPrintService {
  static Future<void> print({
    required String fileName,
    required Uint8List bytes,
  }) {
    final normalizedName = ExportPayloadValidator.validate(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/pdf',
    );
    return implementation.printPdf(fileName: normalizedName, bytes: bytes);
  }
}
