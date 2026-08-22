// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

import 'browser_download_lifecycle.dart';

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
  triggerBrowserDownload(
    attach: () => html.document.body?.children.add(anchor),
    click: anchor.click,
    detach: anchor.remove,
    revoke: () => html.Url.revokeObjectUrl(url),
  );
}
