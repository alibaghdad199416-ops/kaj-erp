import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';

Future<void> saveExcel({
  required String fileName,
  required Uint8List bytes,
}) async {
  final normalized = fileName.toLowerCase().endsWith('.xlsx')
      ? fileName.substring(0, fileName.length - 5)
      : fileName;
  await FileSaver.instance.saveFile(
    name: normalized,
    bytes: bytes,
    ext: 'xlsx',
    mimeType: MimeType.microsoftExcel,
  );
}
