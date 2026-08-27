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
          padding: const EdgeInsets.all(10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final image = _field(
                'image',
                Container(
                  width: compact ? 52 : 64,
                  height: compact ? 52 : 64,
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
              );
              final details = _details(context, colors);
              return compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            image,
                            const SizedBox(width: 9),
                            Expanded(child: details),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _actions(context),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        image,
                        const SizedBox(width: 10),
                        Expanded(child: details),
                        const SizedBox(width: 8),
                        _actions(context),
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }

  Widget _details(BuildContext context, ColorScheme colors) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: _field(
              'name',
              AppText(
                item.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _field('quantity', _StatusBadge(item: item)),
        ],
      ),
      const SizedBox(height: 5),
      Wrap(
        spacing: 5,
        runSpacing: 4,
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
    ],
  );

  Widget _actions(BuildContext context) => Wrap(
    spacing: 2,
    runSpacing: 2,
    alignment: WrapAlignment.end,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: <Widget>[
      _ActionButton(
        icon: Icons.visibility_outlined,
        label: _t(context, 'تفاصيل', 'Details'),
        onPressed: onView,
      ),
      PermissionVisibility(
        permission: 'inventory.update',
        child: _ActionButton(
          icon: Icons.edit_outlined,
          label: _t(context, 'تعديل', 'Edit'),
          onPressed: onEdit,
        ),
      ),
      PermissionVisibility(
        permission: 'inventory.view_history',
        child: _ActionButton(
          icon: Icons.history_rounded,
          label: _t(context, 'السجل', 'History'),
          onPressed: onHistory,
        ),
      ),
      PermissionVisibility(
        permission: 'inventory.delete',
        child: IconButton(
          tooltip: _t(context, 'حذف', 'Delete'),
          visualDensity: VisualDensity.compact,
          onPressed: onDelete,
          icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
        ),
      ),
    ],
  );

  Widget _image(BuildContext context) {
    final value = item.imageBase64;
    if (value == null || value.isEmpty) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: .06),
        child: const Center(child: Icon(Icons.inventory_2_outlined, size: 34)),
      );
    }
    final bytes = Base64ImageCache.instance.decode(value);
    if (bytes == null) {
      return const Center(child: Icon(Icons.broken_image_outlined, size: 32));
    }
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) =>
          const Center(child: Icon(Icons.broken_image_outlined, size: 32)),
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
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(10),
      ),
      child: AppText(
        '$label: ${value.trim().isEmpty ? '—' : value}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
    ),
    icon: Icon(icon, size: 14),
    label: AppText(label, style: const TextStyle(fontSize: 10)),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: AppText(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
