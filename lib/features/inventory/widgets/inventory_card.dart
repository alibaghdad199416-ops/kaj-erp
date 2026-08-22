import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/core/utils/base64_image_cache.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_model.dart';

class InventoryCard extends StatelessWidget {
  const InventoryCard({
    super.key,
    required this.item,
    required this.onDelete,
    required this.onView,
    required this.onEdit,
    required this.onHistory,
  });

  final InventoryModel item;
  final VoidCallback onDelete;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onHistory;

  String _t(BuildContext context, String ar, String en) =>
      context.l10n.isArabic ? ar : en;

  Widget _field(String field, Widget child) => FieldPermissionVisibility(
    resource: 'inventory',
    field: field,
    viewPermission: 'inventory.view',
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: KajDesignTokens.surface(brightness),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusLg),
        border: Border.all(color: KajDesignTokens.border(brightness)),
        boxShadow: KajDesignTokens.softShadow(brightness),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onView,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _field(
                'image',
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      KajDesignTokens.radiusMd,
                    ),
                    border: Border.all(
                      color: KajDesignTokens.border(brightness),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _image(context),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _field(
                            'name',
                            AppText(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        _field('quantity', _StatusBadge(item: item)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 4,
                      runSpacing: 3,
                      children: <Widget>[
                        _field(
                          'category',
                          _ValueChip(
                            label: _t(context, 'المجموعة', 'Group'),
                            value: item.category,
                          ),
                        ),
                        _field(
                          'quantity',
                          _ValueChip(
                            label: _t(context, 'الكمية', 'Quantity'),
                            value: '${item.quantity} ${item.unit}',
                          ),
                        ),
                        _field(
                          'quantity',
                          _ValueChip(
                            label: _t(context, 'المتاح', 'Available'),
                            value: '${item.availableQuantity}',
                          ),
                        ),
                        _field(
                          'unitCost',
                          _ValueChip(
                            label: _t(context, 'الكلفة', 'Cost'),
                            value:
                                '${MoneyFormatter.format(item.unitCost)} ${item.costCurrency ?? item.currency}',
                          ),
                        ),
                        _field(
                          'salePrice',
                          _ValueChip(
                            label: _t(context, 'البيع', 'Sale'),
                            value:
                                '${MoneyFormatter.format(item.salePrice)} ${item.saleCurrency ?? item.currency}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Wrap(
                        spacing: 1,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          _ActionButton(
                            icon: Icons.visibility_outlined,
                            label: _t(context, 'تفاصيل', 'Details'),
                            onPressed: onView,
                          ),
                          _ActionButton(
                            icon: Icons.edit_outlined,
                            label: _t(context, 'تعديل', 'Edit'),
                            onPressed: onEdit,
                          ),
                          _ActionButton(
                            icon: Icons.history_rounded,
                            label: _t(context, 'السجل', 'History'),
                            onPressed: onHistory,
                          ),
                          _ActionButton(
                            icon: Icons.delete_outline,
                            label: _t(context, 'حذف', 'Delete'),
                            onPressed: onDelete,
                            color: colors.error,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _image(BuildContext context) {
    final value = item.imageBase64;
    if (value == null || value.isEmpty) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .06),
        child: const Center(child: Icon(Icons.inventory_2_outlined, size: 30)),
      );
    }
    final bytes = Base64ImageCache.instance.decode(value);
    if (bytes == null) {
      return const Center(child: Icon(Icons.broken_image_outlined, size: 28));
    }
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) =>
          const Center(child: Icon(Icons.broken_image_outlined, size: 28)),
    );
  }
}

class _ValueChip extends StatelessWidget {
  const _ValueChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(10),
      ),
      child: AppText(
        '$label: ${value.trim().isEmpty ? '—' : value}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 9.2, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    color: color,
    visualDensity: VisualDensity.compact,
    constraints: const BoxConstraints.tightFor(width: 30, height: 30),
    padding: EdgeInsets.zero,
    icon: Icon(icon, size: 16),
  );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.item});
  final InventoryModel item;

  @override
  Widget build(BuildContext context) {
    final warning = item.isLowStock;
    final color = warning ? const Color(0xFFF59E0B) : const Color(0xFF16A36A);
    final label = context.l10n.isArabic
        ? (warning ? 'منخفض' : 'متوفر')
        : (warning ? 'Low stock' : 'Available');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: AppText(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.2,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
