import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_phase3_components.dart';
import 'package:quality_line_erp/design_system/kaj_phase4_components.dart';
import 'package:quality_line_erp/features/customer_service/controllers/opportunities_controller.dart';
import 'package:quality_line_erp/features/customer_service/models/opportunity_model.dart';
import 'package:quality_line_erp/features/maintenance/controllers/maintenance_controller.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';
import 'package:quality_line_erp/features/maintenance/pages/add_maintenance_order_page.dart';
import 'package:quality_line_erp/features/maintenance/pages/maintenance_order_details_dialog.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

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

  bool _isMaintenanceDraft(MaintenanceOrderModel order) =>
      const <String>{'draft', 'order_draft'}.contains(order.workflowStage);

  Future<String?> _reason(
    BuildContext context, {
    required String titleAr,
    required String titleEn,
    required String labelAr,
    required String labelEn,
    required String confirmAr,
    required String confirmEn,
  }) async {
    final ar = context.l10n.isArabic;
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(ar ? titleAr : titleEn),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: InputDecoration(labelText: ar ? labelAr : labelEn),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: AppText(ar ? 'رجوع' : 'Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: AppText(ar ? confirmAr : confirmEn),
          ),
        ],
      ),
    );
    final value = controller.text.trim();
    controller.dispose();
    if (accepted != true) return null;
    if (value.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
              ar ? 'سبب العملية مطلوب.' : 'A reason is required.',
            ),
          ),
        );
      }
      return null;
    }
    return value;
  }

  Future<void> _cancelMaintenance(
    BuildContext context,
    MaintenanceOrderModel order,
  ) async {
    if (!await PermissionAction.require(context, 'maintenance.cancel')) return;
    if (!context.mounted) return;
    final reason = await _reason(
      context,
      titleAr: 'إلغاء أمر الصيانة وعكس آثاره',
      titleEn: 'Cancel and reverse maintenance order',
      labelAr: 'سبب الإلغاء',
      labelEn: 'Cancellation reason',
      confirmAr: 'تأكيد الإلغاء',
      confirmEn: 'Confirm cancellation',
    );
    if (reason == null || !context.mounted) return;
    await context.read<MaintenanceController>().cancelOrder(
      order.id,
      reason: reason,
    );
    if (context.mounted) {
      await context.read<OpportunitiesController>().load(force: true);
    }
  }

  Future<void> _deleteMaintenance(
    BuildContext context,
    MaintenanceOrderModel order,
  ) async {
    if (!await PermissionAction.require(context, 'maintenance.delete')) return;
    if (!context.mounted) return;
    final reason = await _reason(
      context,
      titleAr: _isMaintenanceDraft(order)
          ? 'حذف مسودة أمر الصيانة'
          : 'حذف أمر الصيانة الملغى',
      titleEn: _isMaintenanceDraft(order)
          ? 'Delete maintenance draft'
          : 'Delete cancelled maintenance order',
      labelAr: 'سبب الحذف',
      labelEn: 'Deletion reason',
      confirmAr: 'حذف',
      confirmEn: 'Delete',
    );
    if (reason == null || !context.mounted) return;
    await context.read<MaintenanceController>().deleteOrder(
      order.id,
      reason: reason,
    );
    if (context.mounted) {
      await context.read<OpportunitiesController>().load(force: true);
    }
  }

  Future<void> _openMaintenance(BuildContext context) async {
    final ar = context.l10n.isArabic;
    if (!await PermissionAction.require(context, 'maintenance.view')) return;
    if (!context.mounted) return;

    try {
      final maintenance = context.read<MaintenanceController>();
      var order = await maintenance.findByOpportunity(opportunity.id);

      if (order == null) {
        if (opportunity.status == OpportunityStatus.lost) {
          throw StateError('lost_opportunity_cannot_create_maintenance_order');
        }
        if (!await PermissionAction.require(context, 'maintenance.create')) {
          return;
        }
        if (!context.mounted) return;

        final changed = await showAppWorkspaceDialog<bool>(
          context: context,
          child: AddMaintenanceOrderPage(
            initialCarId: opportunity.carId,
            opportunityId: opportunity.id,
          ),
        );
        if (changed != true || !context.mounted) return;

        order = await maintenance.findByOpportunity(opportunity.id);
        await context.read<OpportunitiesController>().load(force: true);
        if (!context.mounted) return;
        if (order == null) {
          throw StateError('maintenance_opportunity_link_missing_after_save');
        }
      }

      final linkedOrder = order;
      final isDraft = _isMaintenanceDraft(linkedOrder);
      final changed = await showAppWorkspaceDialog<bool>(
        context: context,
        child: MaintenanceOrderDetailsDialog(
          order: linkedOrder,
          onDelete: isDraft || linkedOrder.isCancelled
              ? () => _deleteMaintenance(context, linkedOrder)
              : null,
          // Cancel and Delete are independent. R70.5 preserves a Draft as a
          // cancelled historical document without invoking downstream reversal;
          // executed stages continue through the verified R67 reversal path.
          onCancel: !linkedOrder.isCancelled
              ? () => _cancelMaintenance(context, linkedOrder)
              : null,
        ),
      );
      if (context.mounted && changed == true) {
        await context.read<OpportunitiesController>().load(force: true);
      } else if (context.mounted) {
        await context.read<OpportunitiesController>().load(force: true);
      }
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: AppText(
            userFacingError(
              error,
              isArabic: ar,
              arabicFallback:
                  'تعذر فتح أو إنشاء أمر الصيانة المرتبط بهذه الفرصة.',
              englishFallback:
                  'Unable to open or create the maintenance order linked to this opportunity.',
            ),
          ),
        ),
      );
    }
  }

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
                      _field('car', _info(Icons.directions_car_outlined, opportunity.carName!)),
                    if (opportunity.assignedUserName.trim().isNotEmpty)
                      _field(
                        'assignedUserName',
                        _info(Icons.person_outline, opportunity.assignedUserName),
                      ),
                    if (opportunity.expectedValue > 0)
                      _field(
                        'value',
                        _info(
                          Icons.payments_outlined,
                          const <String>{'USD', 'IQD'}.contains(opportunity.currency)
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
                          DateFormat('yyyy-MM-dd').format(opportunity.followUpDate!),
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
                        _info(Icons.badge_outlined, opportunity.createdByUserName),
                      ),
                    _field(
                      'createdAt',
                      _info(
                        Icons.schedule_outlined,
                        DateFormat('yyyy-MM-dd HH:mm').format(opportunity.createdAt.toLocal()),
                      ),
                    ),
                    if (opportunity.closedAt != null)
                      _field(
                        'closedAt',
                        _info(
                          Icons.event_available_outlined,
                          DateFormat('yyyy-MM-dd HH:mm').format(opportunity.closedAt!.toLocal()),
                        ),
                      ),
                    if (opportunity.updatedAt != null)
                      _field(
                        'updatedAt',
                        _info(
                          Icons.update_outlined,
                          DateFormat('yyyy-MM-dd HH:mm').format(opportunity.updatedAt!.toLocal()),
                        ),
                      ),
                    if ((opportunity.salesOrderNumber ?? '').trim().isNotEmpty ||
                        (opportunity.salesOrderStatus ?? '').trim().isNotEmpty)
                      _field(
                        'linkedSale',
                        _info(
                          Icons.shopping_cart_outlined,
                          [
                            if ((opportunity.salesOrderNumber ?? '').trim().isNotEmpty)
                              opportunity.salesOrderNumber!,
                            if ((opportunity.salesOrderStatus ?? '').trim().isNotEmpty)
                              opportunity.salesOrderStatus!,
                          ].join(' • '),
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
                    if ((opportunity.maintenanceOrderNumber ?? '').trim().isNotEmpty ||
                        (opportunity.maintenanceOrderStatus ?? '').trim().isNotEmpty)
                      _field(
                        'linkedMaintenance',
                        _info(
                          Icons.build_circle_outlined,
                          [
                            if ((opportunity.maintenanceOrderNumber ?? '').trim().isNotEmpty)
                              opportunity.maintenanceOrderNumber!,
                            if ((opportunity.maintenanceOrderStatus ?? '').trim().isNotEmpty)
                              opportunity.maintenanceOrderStatus!,
                          ].join(' • '),
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
                  if (canUpdateStatus && opportunity.status == OpportunityStatus.pending)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
                        ),
                      ),
                      onPressed: onLost,
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: AppText(t('خاسرة', 'Lost'), style: const TextStyle(fontSize: 10)),
                    ),
                  if ((opportunity.saleId != null && canViewSale) ||
                      (opportunity.saleId == null &&
                          opportunity.status != OpportunityStatus.lost &&
                          canUpdateStatus &&
                          canCreateSale))
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
                        ),
                      ),
                      onPressed: onWon,
                      icon: const Icon(Icons.shopping_cart_checkout_rounded, size: 16),
                      label: AppText(
                        opportunity.saleId == null
                            ? t('أمر بيع', 'Sales order')
                            : t('فتح أمر البيع', 'Open sales order'),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  if (opportunity.hasMaintenanceOrder ||
                      opportunity.status != OpportunityStatus.lost)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(KajDesignTokens.radiusSm),
                        ),
                      ),
                      onPressed: () => _openMaintenance(context),
                      icon: const Icon(Icons.build_circle_outlined, size: 16),
                      label: AppText(
                        opportunity.hasMaintenanceOrder
                            ? t('فتح أمر الصيانة', 'Open maintenance')
                            : t('أمر صيانة', 'Maintenance order'),
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
