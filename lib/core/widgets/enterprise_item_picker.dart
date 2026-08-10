import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/media/app_image_service.dart';
import 'enterprise_item_visual_card.dart';

class EnterprisePickerItem<T> {
  const EnterprisePickerItem({
    required this.value,
    required this.title,
    required this.kind,
    required this.searchText,
    required this.details,
    this.subtitle,
    this.image,
    this.badge,
  });

  final T value;
  final String title;
  final String? subtitle;
  final String kind;
  final String searchText;
  final Map<String, Object?> details;
  final String? image;
  final String? badge;
}

class EnterpriseItemPicker<T> extends StatelessWidget {
  const EnterpriseItemPicker({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
    required this.label,
    this.carKind = 'car',
    this.productKind = 'product',
  });

  final List<EnterprisePickerItem<T>> items;
  final EnterprisePickerItem<T>? selected;
  final ValueChanged<EnterprisePickerItem<T>> onSelected;
  final String label;
  final String carKind;
  final String productKind;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: items.isEmpty ? null : () => _open(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: AppTranslation.translate(label),
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.search),
        ),
        child: selected == null
            ? AppText(AppTranslation.translate('اضغط للبحث والاختيار'))
            : _SelectedItemCard(item: selected!),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final result = await showAppWorkspaceDialogBuilder<EnterprisePickerItem<T>>(
      context: context,
      builder: (_) => _PickerDialog<T>(
        items: items,
        initial: selected,
        carKind: carKind,
        productKind: productKind,
      ),
    );
    if (result != null) onSelected(result);
  }
}

class _PickerDialog<T> extends StatefulWidget {
  const _PickerDialog({
    required this.items,
    required this.initial,
    required this.carKind,
    required this.productKind,
  });

  final List<EnterprisePickerItem<T>> items;
  final EnterprisePickerItem<T>? initial;
  final String carKind;
  final String productKind;

  @override
  State<_PickerDialog<T>> createState() => _PickerDialogState<T>();
}

class _PickerDialogState<T> extends State<_PickerDialog<T>> {
  final _search = TextEditingController();
  String _kind = 'all';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<EnterprisePickerItem<T>> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return widget.items.where((item) {
      if (_kind != 'all' && item.kind != _kind) return false;
      if (query.isEmpty) return true;
      return '${item.title} ${item.subtitle ?? ''} ${item.searchText} ${item.details.entries.map((e) => '${e.key} ${e.value}').join(' ')}'
          .toLowerCase()
          .contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: AppText(AppTranslation.translate('اختيار السيارة أو المنتج')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
                labelText: AppTranslation.translate(
                  'البحث بالاسم أو الكود أو الشاصي أو اللوحة',
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _kindChip(
                  context,
                  label: 'الكل',
                  icon: Icons.apps_rounded,
                  selected: _kind == 'all',
                  onSelected: () => setState(() => _kind = 'all'),
                ),
                _kindChip(
                  context,
                  label: 'السيارات',
                  icon: Icons.directions_car_filled_outlined,
                  selected: _kind == widget.carKind,
                  onSelected: () => setState(() => _kind = widget.carKind),
                ),
                _kindChip(
                  context,
                  label: 'المنتجات',
                  icon: Icons.inventory_2_rounded,
                  selected: _kind == widget.productKind,
                  onSelected: () => setState(() => _kind = widget.productKind),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: AppText(
                      AppTranslation.translate('لا توجد نتائج مطابقة'),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _PickerResultCard(
                          item: item,
                          selected:
                              identical(item.value, widget.initial?.value) ||
                              item.value == widget.initial?.value,
                          onTap: () => Navigator.pop(context, item),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

Widget _kindChip(
  BuildContext context, {
  required String label,
  required IconData icon,
  required bool selected,
  required VoidCallback onSelected,
}) {
  final scheme = Theme.of(context).colorScheme;
  final foreground = selected ? scheme.onPrimary : scheme.onSurfaceVariant;
  return ChoiceChip(
    selected: selected,
    showCheckmark: false,
    selectedColor: scheme.primary,
    backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: .65),
    side: BorderSide(
      color: selected
          ? scheme.primary
          : scheme.outlineVariant.withValues(alpha: .8),
    ),
    shape: const StadiumBorder(),
    padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 10, 4),
    avatar: Icon(icon, size: 17, color: foreground),
    label: AppText(
      label,
      style: TextStyle(
        color: foreground,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    ),
    onSelected: (_) => onSelected(),
  );
}

class _PickerResultCard<T> extends StatelessWidget {
  const _PickerResultCard({
    required this.item,
    required this.onTap,
    required this.selected,
  });

  final EnterprisePickerItem<T> item;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: .18)
          : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              if (item.badge != null && item.badge!.isNotEmpty)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 6,
                      bottom: 6,
                    ),
                    child: Chip(
                      label: AppText(AppTranslation.translate(item.badge!)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              EnterpriseItemVisualCard(
                title: item.title,
                kind: item.kind,
                details: item.details,
                image: item.image,
              ),
              if (item.subtitle != null && item.subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AppText(
                      item.subtitle!,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              const Padding(
                padding: EdgeInsetsDirectional.only(
                  start: 6,
                  end: 6,
                  bottom: 4,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Icon(Icons.chevron_right),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedItemCard<T> extends StatelessWidget {
  const _SelectedItemCard({required this.item});
  final EnterprisePickerItem<T> item;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _PickerImage(image: item.image, isCar: item.kind == 'car', size: 46),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (item.subtitle != null)
              AppText(
                item.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    ],
  );
}

class _PickerImage extends StatelessWidget {
  const _PickerImage({
    required this.image,
    required this.isCar,
    required this.size,
  });
  final String? image;
  final bool isCar;
  final double size;

  @override
  Widget build(BuildContext context) {
    final value = image?.trim() ?? '';
    final fallback = Icon(
      isCar ? Icons.directions_car_outlined : Icons.inventory_2_outlined,
      size: size * .5,
    );
    Widget child;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      child = Image.network(
        value,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Center(child: fallback),
      );
    } else {
      final Uint8List? bytes = AppImageService.decodeBase64(value);
      child = bytes == null
          ? Center(child: fallback)
          : Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(child: fallback),
            );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: SizedBox(width: size, height: size, child: child),
      ),
    );
  }
}
