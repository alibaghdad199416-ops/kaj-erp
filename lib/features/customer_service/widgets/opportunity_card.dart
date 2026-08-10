import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_phase3_components.dart';
import 'package:quality_line_erp/design_system/kaj_phase4_components.dart';
import 'package:quality_line_erp/features/customer_service/models/opportunity_model.dart';

class OpportunityCard extends StatelessWidget {
  const OpportunityCard({
    super.key,
    required this.opportunity,
    required this.onEdit,
    required this.onWon,
    required this.onLost,
    required this.onDelete,
    required this.canEdit,
    required this.canDelete,
    required this.canUpdateStatus,
    required this.canCreateSale,
    required this.canViewSale,
  });

  final OpportunityModel opportunity;
  final VoidCallback onEdit;
  final VoidCallback onWon;
  final VoidCallback onLost;
  final VoidCallback onDelete;
  final bool canEdit;
  final bool canDelete;
  final bool canUpdateStatus;
  final bool canCreateSale;
  final bool canViewSale;

  Color _color() => switch (opportunity.status) {
    OpportunityStatus.won => Colors.green,
    OpportunityStatus.lost => Colors.red,
    OpportunityStatus.pending => Colors.orange,
  };

  String _label(BuildContext context) {
    final ar = context.l10n.isArabic;
    return switch (opportunity.status) {
      OpportunityStatus.won => ar ? 'رابحة' : 'Won',
      OpportunityStatus.lost => ar ? 'خاسرة' : 'Lost',
      OpportunityStatus.pending => ar ? 'قيد الانتظار' : 'Pending',
    };
  }

  Widget _field(String field, Widget child) => FieldPermissionVisibility(
    resource: 'opportunities',
    field: field,
    viewPermission: 'customer_service.view',
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    String t(String arText, String enText) => ar ? arText : enText;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: KajPartnerCardShell(
        accent: _color(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: _color().withValues(alpha: .13),
                child: Icon(
                  Icons.support_agent_rounded,
                  color: _color(),
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _field(
                            'title',
                            AppText(
                              opportunity.title.trim().isEmpty
                                  ? t('فرصة بدون عنوان', 'Untitled opportunity')
                                  : opportunity.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        _field(
                          'status',
                          KajStatusBadge(
                            label: _label(context),
                            color: _color(),
                            icon: opportunity.status == OpportunityStatus.won
                                ? Icons.workspace_premium_outlined
                                : opportunity.status == OpportunityStatus.lost
                                ? Icons.cancel_outlined
                                : Icons.schedule_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 5,
                      runSpacing: 3,
                      children: [
                        _field(
                          'opportunityNumber',
                          AppText(
                            opportunity.opportunityNumber,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        _field(
                          'customerName',
                          AppText(
                            opportunity.customerName,
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        if (opportunity.customerPhone.trim().isNotEmpty)
                          _field(
                            'customerPhone',
                            AppText(
                              opportunity.customerPhone,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if ((opportunity.notes ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      _field(
                        'notes',
                        AppText(
                          opportunity.notes!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 5,
                  children: [
                    if ((opportunity.carName ?? '').trim().isNotEmpty)
                      _field(
                        'car',
                        _info(
                          Icons.directions_car_outlined,
                          opportunity.carName!,
                        ),
                      ),
                    if (opportunity.assignedUserName.trim().isNotEmpty)
                      _field(
                        'assignedUserName',
                        _info(
                          Icons.person_outline,
                          opportunity.assignedUserName,
                        ),
                      ),
                    if (opportunity.expectedValue > 0)
                      _field(
                        'value',
                        _info(
                          Icons.payments_outlined,
                          const <String>{
                                'USD',
                                'IQD',
                              }.contains(opportunity.currency)
                              ? MoneyFormatter.withCurrency(
                                  opportunity.expectedValue,
                                  opportunity.currency,
                                )
                              : t(
                                  'قيمة متوقعة بعملة غير محددة',
                                  'Expected value currency missing',
                                ),
                        ),
                      ),
                    if (opportunity.followUpDate != null)
                      _field(
                        'followUpDate',
                        _info(
                          Icons.event_outlined,
                          DateFormat(
                            'yyyy-MM-dd',
                          ).format(opportunity.followUpDate!),
                        ),
                      ),
                    if (opportunity.source.trim().isNotEmpty)
                      _field(
                        'source',
                        _info(
                          Icons.campaign_outlined,
                          AppTranslation.translate(opportunity.source),
                        ),
                      ),
                    if (opportunity.createdByUserName.trim().isNotEmpty)
                      _field(
                        'createdBy',
                        _info(
                          Icons.badge_outlined,
                          opportunity.createdByUserName,
                        ),
                      ),
                    _field(
                      'createdAt',
                      _info(
                        Icons.schedule_outlined,
                        DateFormat(
                          'yyyy-MM-dd HH:mm',
                        ).format(opportunity.createdAt.toLocal()),
                      ),
                    ),
                    if (opportunity.closedAt != null)
                      _field(
                        'closedAt',
                        _info(
                          Icons.event_available_outlined,
                          DateFormat(
                            'yyyy-MM-dd HH:mm',
                          ).format(opportunity.closedAt!.toLocal()),
                        ),
                      ),
                    if (opportunity.updatedAt != null)
                      _field(
                        'updatedAt',
                        _info(
                          Icons.update_outlined,
                          DateFormat(
                            'yyyy-MM-dd HH:mm',
                          ).format(opportunity.updatedAt!.toLocal()),
                        ),
                      ),
                    if ((opportunity.salesOrderStatus ?? '').trim().isNotEmpty)
                      _field(
                        'linkedSale',
                        _info(
                          Icons.shopping_cart_outlined,
                          '${t('البيع', 'Sales')}: ${opportunity.salesOrderStatus}',
                        ),
                      ),
                    if ((opportunity.deliveryNumber ?? '').trim().isNotEmpty)
                      _field(
                        'linkedSale',
                        _info(
                          Icons.local_shipping_outlined,
                          '${opportunity.deliveryNumber} • ${opportunity.deliveryStatus ?? '-'}',
                        ),
                      ),
                    if ((opportunity.invoiceNumber ?? '').trim().isNotEmpty)
                      _field(
                        'linkedSale',
                        _info(
                          Icons.receipt_long_outlined,
                          '${opportunity.invoiceNumber} • ${opportunity.invoiceStatus ?? '-'}',
                        ),
                      ),
                    if ((opportunity.paymentStatus ?? '').trim().isNotEmpty)
                      _field(
                        'linkedSale',
                        _info(
                          Icons.account_balance_wallet_outlined,
                          '${t('الدفع', 'Payment')}: ${opportunity.paymentStatus}',
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  if (canUpdateStatus &&
                      opportunity.status == OpportunityStatus.pending)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 7,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            KajDesignTokens.radiusSm,
                          ),
                        ),
                      ),
                      onPressed: onLost,
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: AppText(
                        t('خاسرة', 'Lost'),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  if (opportunity.status != OpportunityStatus.lost &&
                      (opportunity.saleId == null
                          ? canUpdateStatus && canCreateSale
                          : canViewSale))
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            KajDesignTokens.radiusSm,
                          ),
                        ),
                      ),
                      onPressed: onWon,
                      icon: const Icon(
                        Icons.shopping_cart_checkout_rounded,
                        size: 16,
                      ),
                      label: AppText(
                        opportunity.saleId == null
                            ? t('أمر بيع', 'Sales order')
                            : t('فتح أمر البيع', 'Open sales order'),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  if (canEdit)
                    IconButton(
                      tooltip: t('تعديل', 'Edit'),
                      visualDensity: VisualDensity.compact,
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 19),
                    ),
                  if (canDelete)
                    IconButton(
                      tooltip: t('حذف', 'Delete'),
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 19),
                      color: Colors.red,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _info(IconData icon, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 15),
      const SizedBox(width: 4),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 145),
        child: AppText(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10.5),
        ),
      ),
    ],
  );
}
