import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/features/sales/models/sale_model.dart';

class SaleCard extends StatelessWidget {
  const SaleCard({
    super.key,
    required this.sale,
    this.onEdit,
    required this.onDelete,
    required this.onPrint,
    this.onResell,
    this.customerName,
    this.carName,
  });

  final SaleModel sale;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPrint;
  final VoidCallback? onResell;
  final String? customerName;
  final String? carName;

  String _visible(String? preferred, String fallback) {
    final value = preferred?.trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  Widget _field(String field, Widget child) => FieldPermissionVisibility(
    resource: 'sales',
    field: field,
    viewPermission: 'sales.view',
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final invoice = sale.invoiceNumber.trim();
    final title = invoice.isEmpty
        ? AppTranslation.translate('فاتورة بيع')
        : '${AppTranslation.translate('فاتورة')} $invoice';
    final customer = _visible(
      customerName,
      AppTranslation.translate('عميل غير محدد'),
    );
    final vehicle = _visible(
      carName,
      AppTranslation.translate('سيارة غير محددة'),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: KajDesignTokens.space12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 9, 10, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    child: const Icon(Icons.point_of_sale_rounded, size: 18),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _field(
                          'invoice',
                          AppText(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _field(
                          'customerId',
                          AppText(
                            customer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _field(
                    'status',
                    _Status(
                      label: sale.remainingAmount <= 0
                          ? AppTranslation.translate('مدفوعة')
                          : AppTranslation.translate('غير مكتملة'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _field(
                    'carId',
                    _Metric(
                      icon: Icons.directions_car_outlined,
                      label: AppTranslation.translate('السيارة'),
                      value: vehicle,
                    ),
                  ),
                  _field(
                    'operationalDate',
                    _Metric(
                      icon: Icons.schedule_rounded,
                      label: AppTranslation.translate('التاريخ'),
                      value: sale.saleDate,
                    ),
                  ),
                  _field(
                    'itemPrice',
                    _Metric(
                      icon: Icons.payments_outlined,
                      label: AppTranslation.translate('السعر'),
                      value: MoneyFormatter.withCurrency(
                        sale.salePrice,
                        sale.currencyCode,
                      ),
                    ),
                  ),
                  _field(
                    'payments',
                    _Metric(
                      icon: Icons.account_balance_wallet_outlined,
                      label: AppTranslation.translate('المتبقي'),
                      value: MoneyFormatter.withCurrency(
                        sale.remainingAmount,
                        sale.currencyCode,
                      ),
                    ),
                  ),
                  if ((sale.createdByUserName ?? '').trim().isNotEmpty)
                    _field(
                      'createdBy',
                      _Metric(
                        icon: Icons.badge_outlined,
                        label: AppTranslation.translate('المنفذ'),
                        value: sale.createdByUserName!.trim(),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  if (onResell != null)
                    _Action(
                      label: AppTranslation.translate('إعادة بيع'),
                      icon: Icons.repeat_rounded,
                      onPressed: () => onResell?.call(),
                    ),
                  _Action(
                    label: AppTranslation.translate('طباعة'),
                    icon: Icons.print_outlined,
                    onPressed: onPrint,
                  ),
                  if (onEdit != null)
                    _Action(
                      label: AppTranslation.translate('تعديل'),
                      icon: Icons.edit_outlined,
                      onPressed: onEdit!,
                      primary: true,
                    ),
                  _Action(
                    label: AppTranslation.translate('حذف'),
                    icon: Icons.delete_outline,
                    onPressed: onDelete,
                    destructive: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 116, maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: s.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: s.primary),
          const SizedBox(width: 5),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppText(
                  label,
                  style: TextStyle(fontSize: 8.5, color: s.onSurfaceVariant),
                ),
                AppText(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: s.primary.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: s.primary.withValues(alpha: .25)),
      ),
      child: AppText(
        label,
        style: TextStyle(
          fontSize: 9.5,
          color: s.primary,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
    this.primary = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool destructive;
  final bool primary;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final fg = destructive ? s.error : (primary ? s.onPrimary : s.primary);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 30,
        padding: const EdgeInsetsDirectional.only(start: 7, end: 9),
        decoration: BoxDecoration(
          color: primary ? s.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: destructive
                ? s.error.withValues(alpha: .45)
                : s.primary.withValues(alpha: .35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 10,
              backgroundColor: primary
                  ? s.onPrimary.withValues(alpha: .18)
                  : s.primary.withValues(alpha: .1),
              child: Icon(icon, size: 12, color: fg),
            ),
            const SizedBox(width: 5),
            AppText(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
