import 'dart:typed_data';

import 'pdf_print_service_stub.dart'
    if (dart.library.html) 'pdf_print_service_web.dart'
    as implementation;

/// Cross-platform PDF print/preview entry point.
///
/// On Flutter Web we deliberately avoid Printing.layoutPdf because browser
/// plugin/asset failures can reject an otherwise valid PDF. Downloading the
/// generated Blob avoids popup blockers after asynchronous PDF generation.
abstract final class PdfPrintService {
  static Future<void> print({
    required String fileName,
    required Uint8List bytes,
  }) => implementation.printPdf(fileName: fileName, bytes: bytes);
}
