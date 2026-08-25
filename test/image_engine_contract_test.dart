import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:quality_line_erp/core/media/app_image_service.dart';

void main() {
  test('central image engine resizes and produces renderable base64', () {
    final source = img.Image(width: 1800, height: 1200);
    final bytes = Uint8List.fromList(img.encodePng(source));
    final result = AppImageService.processBytes(
      bytes,
      maxWidth: 512,
      maxHeight: 512,
    );

    expect(result.width, lessThanOrEqualTo(512));
    expect(result.height, lessThanOrEqualTo(512));
    expect(AppImageService.decodeBase64(result.base64), isNotNull);
    expect(result.bytes.length, lessThanOrEqualTo(900 * 1024));
  });

  test('central image engine rejects invalid data', () {
    expect(
      () => AppImageService.processBytes(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
