import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:uuid/uuid.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/media/app_image_service.dart';

import 'package:quality_line_erp/features/inventory/cars/models/car_image_model.dart';

class CarImagesEditor extends StatefulWidget {
  const CarImagesEditor({
    super.key,
    required this.carId,
    required this.initialImages,
    required this.onChanged,
  });

  final String carId;
  final List<CarImageModel> initialImages;
  final ValueChanged<List<CarImageModel>> onChanged;

  @override
  State<CarImagesEditor> createState() => _CarImagesEditorState();
}

class _CarImagesEditorState extends State<CarImagesEditor> {
  static const int _maximumImages = 16;

  late List<CarImageModel> _images;
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    _images = [...widget.initialImages]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  Future<void> _pickImages() async {
    if (_isPicking || _images.length >= _maximumImages) return;
    setState(() => _isPicking = true);
    try {
      final available = _maximumImages - _images.length;
      final batch = await AppImageService.pickManyAndProcess(
        maxFiles: available,
        maxWidth: 1800,
        maxHeight: 1400,
        quality: 82,
        maxOutputBytes: 260 * 1024,
      );
      if (!mounted) return;

      final added = <CarImageModel>[];
      for (final processed in batch.images) {
        final thumbnail = AppImageService.processBytes(
          processed.bytes,
          maxWidth: 240,
          maxHeight: 180,
          quality: 68,
          maxInputBytes: 320 * 1024,
          maxOutputBytes: 24 * 1024,
        );
        added.add(
          CarImageModel(
            id: const Uuid().v4(),
            carId: widget.carId,
            imageBase64: processed.base64,
            thumbnailBase64: thumbnail.base64,
            sortOrder: _images.length + added.length,
            createdAt: DateTime.now(),
          ),
        );
      }
      if (added.isNotEmpty) {
        setState(() => _images = [..._images, ...added]);
        _notifyChanged();
      }
      if (batch.rejectedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
              context.l10n.isArabic
                  ? 'أضيفت الصور الصالحة، وتعذر قبول ${batch.rejectedCount} صورة للسيارة.'
                  : 'Valid images were added; ${batch.rejectedCount} car image(s) could not be accepted.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            context.l10n.isArabic
                ? 'تعذر قراءة الصور أو ضغطها. استخدم JPG أو PNG أو WEBP.'
                : 'The images could not be read or compressed. Use JPG, PNG, or WEBP.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  List<CarImageModel> _normalized() => List.generate(
    _images.length,
    (index) => CarImageModel(
      id: _images[index].id,
      carId: widget.carId,
      imageBase64: _images[index].imageBase64,
      thumbnailBase64: _images[index].thumbnailBase64,
      sortOrder: index,
      createdAt: _images[index].createdAt,
    ),
  );

  void _notifyChanged() {
    final normalized = _normalized();
    _images = normalized;
    widget.onChanged(List.unmodifiable(normalized));
  }

  void _remove(int index) {
    if (index < 0 || index >= _images.length) return;
    setState(() => _images.removeAt(index));
    _notifyChanged();
  }

  void _setPrimary(int index) {
    if (index <= 0 || index >= _images.length) return;
    setState(() {
      final image = _images.removeAt(index);
      _images.insert(0, image);
    });
    _notifyChanged();
  }

  void _reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex || oldIndex < 0 || oldIndex >= _images.length) {
      return;
    }
    setState(() {
      final image = _images.removeAt(oldIndex);
      _images.insert(newIndex.clamp(0, _images.length).toInt(), image);
    });
    _notifyChanged();
  }

  Uint8List? _decode(CarImageModel image) {
    try {
      return base64Decode(image.imageBase64);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openPreview(int initialIndex) async {
    if (_images.isEmpty) return;
    var currentIndex = initialIndex.clamp(0, _images.length - 1).toInt();
    await showAppWorkspaceDialogBuilder<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: .78),
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (_images.isEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(dialogContext).canPop()) {
                Navigator.of(dialogContext).pop();
              }
            });
            return const SizedBox.shrink();
          }
          currentIndex = currentIndex.clamp(0, _images.length - 1).toInt();
          final bytes = _decode(_images[currentIndex]);
          return Dialog.fullscreen(
            backgroundColor: const Color(0xFF080B10),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: AppTranslation.translate('إغلاق'),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          icon: const Icon(Icons.close, color: Colors.white),
                        ),
                        Expanded(
                          child: AppText(
                            '${currentIndex + 1} / ${_images.length}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: currentIndex == 0
                              ? null
                              : () {
                                  _setPrimary(currentIndex);
                                  setDialogState(() => currentIndex = 0);
                                },
                          icon: const Icon(Icons.star_outline),
                          label: const AppText('تعيين رئيسية'),
                        ),
                        IconButton(
                          tooltip: AppTranslation.translate('حذف الصورة'),
                          onPressed: () {
                            _remove(currentIndex);
                            if (_images.isNotEmpty) {
                              setDialogState(() {
                                currentIndex = currentIndex
                                    .clamp(0, _images.length - 1)
                                    .toInt();
                              });
                            }
                          },
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        _PreviewArrow(
                          icon: Icons.chevron_left,
                          enabled: currentIndex > 0,
                          onPressed: () =>
                              setDialogState(() => currentIndex -= 1),
                        ),
                        Expanded(
                          child: bytes == null
                              ? const Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.white70,
                                    size: 64,
                                  ),
                                )
                              : InteractiveViewer(
                                  minScale: .7,
                                  maxScale: 5,
                                  child: Center(
                                    child: Image.memory(
                                      bytes,
                                      fit: BoxFit.contain,
                                      gaplessPlayback: true,
                                    ),
                                  ),
                                ),
                        ),
                        _PreviewArrow(
                          icon: Icons.chevron_right,
                          enabled: currentIndex < _images.length - 1,
                          onPressed: () =>
                              setDialogState(() => currentIndex += 1),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: AppText(
                      'استخدم عجلة الفأرة أو اللمس للتكبير والتحريك',
                      style: TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = _maximumImages - _images.length;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.photo_library_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: AppText(
                    context.l10n.isArabic ? 'صور السيارة' : 'Car photos',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                AppText(
                  '${_images.length}/$_maximumImages',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: remaining <= 0 || _isPicking ? null : _pickImages,
                  icon: _isPicking
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_a_photo_outlined),
                  label: AppText(_isPicking ? 'جاري القراءة...' : 'إضافة صور'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            AppText(
              'اسحب الصور لإعادة ترتيبها. الصورة الأولى هي الصورة الرئيسية للبطاقة.',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_images.isEmpty)
              InkWell(
                onTap: _pickImages,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 142,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: .04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: .25),
                    ),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_upload_outlined, size: 38),
                      SizedBox(height: 8),
                      AppText(
                        'اضغط لاختيار عدة صور للسيارة',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 4),
                      AppText(
                        'يتم ضغط الصور تلقائياً لتحسين سرعة المزامنة',
                        style: TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                height: 154,
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  proxyDecorator: (child, _, animation) => AnimatedBuilder(
                    animation: animation,
                    builder: (_, _) => Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(14),
                      child: child,
                    ),
                  ),
                  itemCount: _images.length,
                  onReorderItem: _reorder,
                  itemBuilder: (context, index) {
                    final image = _images[index];
                    final bytes = _decode(image);
                    return Padding(
                      key: ValueKey(image.id),
                      padding: const EdgeInsetsDirectional.only(end: 10),
                      child: SizedBox(
                        width: 184,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Material(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(14),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => _openPreview(index),
                                child: bytes == null
                                    ? const Icon(Icons.broken_image_outlined)
                                    : Image.memory(
                                        bytes,
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true,
                                      ),
                              ),
                            ),
                            PositionedDirectional(
                              top: 6,
                              start: 6,
                              child: ReorderableDragStartListener(
                                index: index,
                                child: _RoundImageAction(
                                  tooltip: AppTranslation.translate(
                                    'اسحب لإعادة الترتيب',
                                  ),
                                  icon: Icons.drag_indicator,
                                  onPressed: null,
                                ),
                              ),
                            ),
                            PositionedDirectional(
                              top: 6,
                              end: 6,
                              child: _RoundImageAction(
                                tooltip: AppTranslation.translate('حذف'),
                                icon: Icons.close,
                                color: theme.colorScheme.error,
                                onPressed: () => _remove(index),
                              ),
                            ),
                            PositionedDirectional(
                              start: 7,
                              bottom: 7,
                              child: index == 0
                                  ? const Chip(
                                      avatar: Icon(Icons.star, size: 16),
                                      label: AppText('الرئيسية'),
                                      visualDensity: VisualDensity.compact,
                                    )
                                  : ActionChip(
                                      avatar: const Icon(
                                        Icons.star_outline,
                                        size: 16,
                                      ),
                                      label: const AppText('اجعلها رئيسية'),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _setPrimary(index),
                                    ),
                            ),
                            PositionedDirectional(
                              end: 7,
                              bottom: 7,
                              child: _RoundImageAction(
                                tooltip: AppTranslation.translate('تكبير'),
                                icon: Icons.fullscreen,
                                onPressed: () => _openPreview(index),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundImageAction extends StatelessWidget {
  const _RoundImageAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? Colors.white;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: .58),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 30,
            child: Icon(icon, size: 17, color: foreground),
          ),
        ),
      ),
    );
  }
}

class _PreviewArrow extends StatelessWidget {
  const _PreviewArrow({
    required this.icon,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onPressed : null,
      iconSize: 38,
      color: Colors.white,
      disabledColor: Colors.white24,
      icon: Icon(icon),
    );
  }
}
