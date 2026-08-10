import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;

class AppImageResult {
  const AppImageResult({
    required this.base64,
    required this.bytes,
    required this.width,
    required this.height,
    required this.originalBytes,
  });

  final String base64;
  final Uint8List bytes;
  final int width;
  final int height;
  final int originalBytes;
}

class AppImageBatchResult {
  const AppImageBatchResult({
    required this.images,
    required this.selectedCount,
    required this.rejectedCount,
    this.lastErrorCode,
  });

  final List<AppImageResult> images;
  final int selectedCount;
  final int rejectedCount;
  final String? lastErrorCode;
}

class AppImageService {
  const AppImageService._();

  // Modern phone photos can be considerably larger than 8 MB. They are never
  // sent to Supabase as-is; the service decodes, orients, resizes, and
  // recompresses them first.
  static const int defaultMaxInputBytes = 32 * 1024 * 1024;
  static const int defaultMaxOutputBytes = 320 * 1024;
  static const int _minimumDimension = 160;

  static Uint8List? decodeBase64(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    try {
      final payload = text.contains(',')
          ? text.substring(text.indexOf(',') + 1)
          : text;
      return base64Decode(payload.replaceAll(RegExp(r'\s+'), ''));
    } catch (_) {
      return null;
    }
  }

  static Future<AppImageResult?> pickAndProcess({
    int maxWidth = 1024,
    int maxHeight = 1024,
    int quality = 82,
    int maxInputBytes = defaultMaxInputBytes,
    int maxOutputBytes = defaultMaxOutputBytes,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final bytes = result.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('image_bytes_unavailable');
    }
    return processBytes(
      bytes,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      quality: quality,
      maxInputBytes: maxInputBytes,
      maxOutputBytes: maxOutputBytes,
    );
  }

  static Future<AppImageBatchResult> pickManyAndProcess({
    int maxFiles = 16,
    int maxWidth = 1400,
    int maxHeight = 1400,
    int quality = 82,
    int maxInputBytes = defaultMaxInputBytes,
    int maxOutputBytes = defaultMaxOutputBytes,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return const AppImageBatchResult(
        images: <AppImageResult>[],
        selectedCount: 0,
        rejectedCount: 0,
      );
    }

    final selected = result.files.take(math.max(1, maxFiles)).toList();
    final images = <AppImageResult>[];
    var rejected = result.files.length - selected.length;
    String? lastErrorCode;

    for (final file in selected) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        rejected += 1;
        lastErrorCode = 'image_bytes_unavailable';
        continue;
      }
      try {
        images.add(
          processBytes(
            bytes,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            quality: quality,
            maxInputBytes: maxInputBytes,
            maxOutputBytes: maxOutputBytes,
          ),
        );
      } on FormatException catch (error) {
        rejected += 1;
        lastErrorCode = error.message;
      }
    }

    return AppImageBatchResult(
      images: List<AppImageResult>.unmodifiable(images),
      selectedCount: result.files.length,
      rejectedCount: rejected,
      lastErrorCode: lastErrorCode,
    );
  }

  static AppImageResult processBytes(
    Uint8List source, {
    int maxWidth = 1024,
    int maxHeight = 1024,
    int quality = 82,
    int maxInputBytes = defaultMaxInputBytes,
    int maxOutputBytes = defaultMaxOutputBytes,
  }) {
    if (source.isEmpty) throw const FormatException('empty_image');
    if (source.length > maxInputBytes) {
      throw const FormatException('image_input_too_large');
    }
    if (maxWidth <= 0 || maxHeight <= 0 || maxOutputBytes <= 0) {
      throw const FormatException('invalid_image_limits');
    }

    img.Image? decoded;
    try {
      decoded = img.decodeImage(source);
    } catch (_) {
      throw const FormatException('invalid_image');
    }
    if (decoded == null) throw const FormatException('invalid_image');

    var normalized = img.bakeOrientation(decoded);
    normalized = _fitWithin(normalized, maxWidth, maxHeight);

    var currentQuality = quality.clamp(50, 95).toInt();
    var working = normalized;
    Uint8List output = Uint8List(0);

    // First lower JPEG quality. If that is not enough, keep reducing dimensions
    // and retry. This prevents detailed phone photos from being rejected merely
    // because quality 45 at the first resolution is still too large.
    for (var pass = 0; pass < 18; pass += 1) {
      output = Uint8List.fromList(
        img.encodeJpg(working, quality: currentQuality),
      );
      if (output.length <= maxOutputBytes) break;

      if (currentQuality > 50) {
        currentQuality = math.max(50, currentQuality - 8);
        continue;
      }

      final nextWidth = math.max(
        _minimumDimension,
        (working.width * .82).round(),
      );
      final nextHeight = math.max(
        _minimumDimension,
        (working.height * .82).round(),
      );
      if (nextWidth == working.width && nextHeight == working.height) break;
      working = img.copyResize(
        working,
        width: nextWidth,
        height: nextHeight,
        interpolation: img.Interpolation.average,
      );
      currentQuality = quality.clamp(68, 86).toInt();
    }

    if (output.isEmpty || output.length > maxOutputBytes) {
      throw const FormatException('image_output_too_large');
    }

    return AppImageResult(
      base64: base64Encode(output),
      bytes: output,
      width: working.width,
      height: working.height,
      originalBytes: source.length,
    );
  }

  static img.Image _fitWithin(img.Image source, int maxWidth, int maxHeight) {
    final scale = math.min(
      1.0,
      math.min(maxWidth / source.width, maxHeight / source.height),
    );
    if (scale >= 1) return source;
    return img.copyResize(
      source,
      width: math.max(1, (source.width * scale).round()),
      height: math.max(1, (source.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
  }
}
