import 'dart:typed_data';
import 'package:file_saver/file_saver.dart';

Future<void> saveBinary({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) async {
  final dot = fileName.lastIndexOf('.');
  final name = dot > 0 ? fileName.substring(0, dot) : fileName;
  final ext = dot > 0 ? fileName.substring(dot + 1) : 'bin';
  await FileSaver.instance.saveFile(
    name: name,
    bytes: bytes,
    ext: ext,
    mimeType: MimeType.other,
  );
}
