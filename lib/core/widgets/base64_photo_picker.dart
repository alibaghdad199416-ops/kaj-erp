import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/media/app_image_service.dart';
import 'package:quality_line_erp/core/widgets/app_horizontal_strip.dart';

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
        _ => context.l10n.isArabic
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
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 440;
        final preview = Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .55),
            border: Border.all(color: theme.dividerColor.withValues(alpha: .7)),
          ),
          clipBehavior: Clip.antiAlias,
          child: bytes == null
              ? Icon(Icons.photo_camera_outlined, color: theme.colorScheme.primary)
              : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
        );
        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AppText(widget.label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            AppHorizontalStrip(
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined, size: 19),
                  label: const AppText('اختيار صورة'),
                ),
                if (bytes != null)
                  TextButton.icon(
                    onPressed: _busy ? null : () => widget.onChanged(null),
                    icon: const Icon(Icons.delete_outline, size: 19),
                    label: const AppText('إزالة'),
                  ),
              ],
            ),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [preview, const SizedBox(height: 10), details],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [preview, const SizedBox(width: 14), Expanded(child: details)],
        );
      },
    );
  }
}
