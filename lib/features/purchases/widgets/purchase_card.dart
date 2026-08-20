import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/features/purchases/models/purchase_model.dart';

class PurchaseCard extends StatelessWidget {
  const PurchaseCard({
    super.key,
    required this.purchase,
    required this.onDelete,
    this.onEdit,
    required this.onView,
    required this.onPrint,
  });
  final PurchaseModel purchase;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;
  final VoidCallback onView;
  final VoidCallback onPrint;

  Widget _field(String field, Widget child) => FieldPermissionVisibility(
    resource: 'purchases',
    field: field,
    viewPermission: 'purchases.view',
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = purchase.isPaid
        ? AppTranslation.translate('مدفوعة')
        : purchase.isPartial
        ? AppTranslation.translate('جزئية')
        : AppTranslation.translate('آجلة');
    final number = purchase.invoiceNumber.trim();
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onView,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 9, 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: scheme.secondaryContainer,
                    foregroundColor: scheme.onSecondaryContainer,
                    child: const Icon(
                      Icons.shopping_cart_checkout_rounded,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _field(
                          'invoice',
                          AppText(
                            number.isEmpty
                                ? AppTranslation.translate('فاتورة شراء')
                                : '${AppTranslation.translate('فاتورة')} $number',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _field(
                          'supplierId',
                          AppText(
                            purchase.supplierName.trim().isEmpty
                                ? AppTranslation.translate('مورد غير محدد')
                                : purchase.supplierName,
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
                  _field('status', _Status(label: status)),
                ],
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _field(
                    'operationalDate',
                    _Metric(
                      icon: Icons.schedule_rounded,
                      label: AppTranslation.translate('التاريخ'),
                      value: DateFormat(
                        'yyyy/MM/dd HH:mm',
                      ).format(purchase.purchaseDate.toLocal()),
                    ),
                  ),
                  _field(
                    'itemCost',
                    _Metric(
                      icon: Icons.payments_outlined,
                      label: AppTranslation.translate('الإجمالي'),
                      value: MoneyFormatter.withCurrency(
                        purchase.totalAmount,
                        purchase.currencyCode,
                      ),
                    ),
                  ),
                  _field(
                    'payments',
                    _Metric(
                      icon: Icons.account_balance_wallet_outlined,
                      label: AppTranslation.translate('المدفوع'),
                      value: MoneyFormatter.withCurrency(
                        purchase.paidAmount,
                        purchase.currencyCode,
                      ),
                    ),
                  ),
                  _field(
                    'payments',
                    _Metric(
                      icon: Icons.pending_actions_outlined,
                      label: AppTranslation.translate('المتبقي'),
                      value: MoneyFormatter.withCurrency(
                        purchase.remainingAmount,
                        purchase.currencyCode,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  _Action(
                    label: AppTranslation.translate('التفاصيل'),
                    icon: Icons.visibility_outlined,
                    onPressed: onView,
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
      constraints: const BoxConstraints(minWidth: 108, maxWidth: 200),
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
        height: 28,
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
