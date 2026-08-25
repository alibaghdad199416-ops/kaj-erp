import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/media/app_image_service.dart';

class Base64PhotoPicker extends StatefulWidget {
  const Base64PhotoPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'الصورة',
    this.maxWidth = 1024,
    this.maxHeight = 1024,
    this.maxOutputBytes = 240 * 1024,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  final int maxWidth;
  final int maxHeight;
  final int maxOutputBytes;

  @override
  State<Base64PhotoPicker> createState() => _Base64PhotoPickerState();
}

class _Base64PhotoPickerState extends State<Base64PhotoPicker> {
  bool _busy = false;

  Uint8List? get _bytes => AppImageService.decodeBase64(widget.value);

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await AppImageService.pickAndProcess(
        maxWidth: widget.maxWidth,
        maxHeight: widget.maxHeight,
        maxOutputBytes: widget.maxOutputBytes,
      );
      if (result != null) widget.onChanged(result.base64);
    } on FormatException catch (error) {
      if (!mounted) return;
      final message = switch (error.message) {
        'image_input_too_large' || 'image_output_too_large' =>
          context.l10n.isArabic
              ? 'تعذر ضغط الصورة إلى الحجم الآمن. اختر صورة أخرى.'
              : 'The image could not be compressed to a safe size. Choose another image.',
        'image_bytes_unavailable' =>
          context.l10n.isArabic
              ? 'تعذر قراءة ملف الصورة من المتصفح.'
              : 'The browser could not read the selected image.',
        _ =>
          context.l10n.isArabic
              ? 'ملف الصورة غير صالح. استخدم JPG أو PNG أو WEBP.'
              : 'Invalid image file. Use JPG, PNG, or WEBP.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText(message), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 34,
              backgroundImage: bytes == null ? null : MemoryImage(bytes),
              child: bytes == null
                  ? const Icon(Icons.photo_camera_outlined)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    widget.label,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _pick,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_photo_alternate_outlined),
                        label: const AppText('اختيار صورة'),
                      ),
                      if (bytes != null)
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => widget.onChanged(null),
                          icon: const Icon(Icons.delete_outline),
                          label: const AppText('إزالة'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
