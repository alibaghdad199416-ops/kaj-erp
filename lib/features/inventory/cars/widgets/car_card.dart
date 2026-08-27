import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/core/localization/operational_status_label.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/features/inventory/cars/controllers/car_images_controller.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_model.dart';

class CarCard extends StatelessWidget {
  const CarCard({
    super.key,
    required this.car,
    this.onEdit,
    this.onDelete,
    this.onHistory,
    this.warehouseName,
    this.carNumber,
    this.plateNumber,
  });

  final CarModel car;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onHistory;
  final String? warehouseName;
  final String? carNumber;
  final String? plateNumber;

  String _t(BuildContext context, String ar, String en) =>
      context.l10n.isArabic ? ar : en;

  Color _statusColor() {
    switch (car.statusValue.name) {
      case 'purchasing':
        return const Color(0xFF8A5CF5);
      case 'available':
        return const Color(0xFF16A36A);
      case 'damaged':
        return const Color(0xFFD9534F);
      case 'selling':
        return const Color(0xFFF59E0B);
      case 'sold':
        return const Color(0xFF2F80ED);
      default:
        return const Color(0xFF607D8B);
    }
  }

  Widget _field(String field, Widget child) => FieldPermissionVisibility(
    resource: 'cars',
    field: field,
    viewPermission: 'cars.view',
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final colors = Theme.of(context).colorScheme;
    final statusColor = _statusColor();
    return Container(
      decoration: BoxDecoration(
        color: KajDesignTokens.surface(brightness),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusLg),
        border: Border.all(color: KajDesignTokens.border(brightness)),
        boxShadow: KajDesignTokens.softShadow(brightness),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              final image = _field(
                'images',
                Container(
                  width: compact ? 56 : 68,
                  height: compact ? 56 : 68,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      KajDesignTokens.radiusMd,
                    ),
                    border: Border.all(
                      color: KajDesignTokens.border(brightness),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _CarThumbnail(carId: car.id),
                ),
              );
              final details = _details(context, colors, statusColor);
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
                        _actions(context, colors),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        image,
                        const SizedBox(width: 10),
                        Expanded(child: details),
                        const SizedBox(width: 8),
                        _actions(context, colors),
                      ],
                    );
            },
          ),
        ),
      ),
    );
  }

  Widget _details(
    BuildContext context,
    ColorScheme colors,
    Color statusColor,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _field(
                  'brand',
                  AppText(
                    '${car.brand} ${car.model}'.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                _field(
                  'year',
                  AppText(
                    '${car.year} • ${car.color}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _field(
            'status',
            _StatusBadge(
              color: statusColor,
              label: operationalStatusLabel(car.status),
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      Wrap(
        spacing: 5,
        runSpacing: 4,
        children: <Widget>[
          _field(
            'chassis',
            _ValueChip(
              label: _t(context, 'رقم الشاصي', 'VIN'),
              value: car.chassis,
            ),
          ),
          _field(
            'warehouseId',
            _ValueChip(
              label: _t(context, 'المخزن', 'Warehouse'),
              value: warehouseName ?? '',
            ),
          ),
          _field(
            'carNumber',
            _ValueChip(
              label: _t(context, 'رقم السيارة', 'Vehicle no.'),
              value: carNumber ?? '',
            ),
          ),
          _field(
            'plateNumber',
            _ValueChip(
              label: _t(context, 'اللوحة', 'Plate'),
              value: plateNumber ?? '',
            ),
          ),
          _field(
            'purchasePrice',
            _ValueChip(
              label: _t(context, 'سعر الشراء', 'Purchase price'),
              value:
                  '${MoneyFormatter.format(car.purchasePrice)} ${car.costCurrency ?? car.currency}',
            ),
          ),
          _field(
            'maintenanceCost',
            _ValueChip(
              label: _t(context, 'كلفة الصيانة', 'Maintenance cost'),
              value:
                  '${MoneyFormatter.format(car.maintenanceCost)} ${car.costCurrency ?? car.currency}',
            ),
          ),
          _field(
            'salePrice',
            _ValueChip(
              label: _t(context, 'سعر البيع', 'Sale price'),
              value:
                  '${MoneyFormatter.format(car.salePrice)} ${car.saleCurrency ?? car.currency}',
            ),
          ),
        ],
      ),
    ],
  );

  Widget _actions(BuildContext context, ColorScheme colors) => Wrap(
    spacing: 2,
    runSpacing: 2,
    alignment: WrapAlignment.end,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: <Widget>[
      if (onEdit != null)
        _ActionButton(
          icon: Icons.edit_outlined,
          label: _t(context, 'تعديل', 'Edit'),
          onPressed: onEdit!,
        ),
      if (onHistory != null)
        _ActionButton(
          icon: Icons.history_rounded,
          label: _t(context, 'السجل', 'History'),
          onPressed: onHistory!,
        ),
      if (onDelete != null)
        IconButton(
          tooltip: _t(context, 'حذف', 'Delete'),
          visualDensity: VisualDensity.compact,
          onPressed: onDelete,
          icon: Icon(Icons.delete_outline, color: colors.error),
        ),
    ],
  );
}

class _CarThumbnail extends StatelessWidget {
  const _CarThumbnail({required this.carId});
  final String carId;

  @override
  Widget build(BuildContext context) {
    return Consumer<CarImagesController>(
      builder: (context, controller, child) {
        final bytes = controller.thumbnailBytesFor(carId);
        if (bytes != null) {
          return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
        }
        return ColoredBox(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: .07),
          child: const Center(
            child: Icon(Icons.directions_car_outlined, size: 40),
          ),
        );
      },
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
  const _StatusBadge({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
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
