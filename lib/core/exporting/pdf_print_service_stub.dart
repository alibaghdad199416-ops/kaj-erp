import 'dart:typed_data';

import 'package:printing/printing.dart';

Future<void> printPdf({
  required String fileName,
  required Uint8List bytes,
}) async {
  await Printing.layoutPdf(name: fileName, onLayout: (_) async => bytes);
}
