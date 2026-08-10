// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

Future<void> saveBinary({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) async {
  final blob = html.Blob(<Object>[bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  try {
    anchor.click();
  } finally {
    anchor.remove();
    // Edge/Chrome may start the actual download asynchronously after click().
    // Revoking the Blob URL immediately can produce a silent failed export.
    unawaited(
      Future<void>.delayed(const Duration(seconds: 10), () {
        html.Url.revokeObjectUrl(url);
      }),
    );
  }
}
