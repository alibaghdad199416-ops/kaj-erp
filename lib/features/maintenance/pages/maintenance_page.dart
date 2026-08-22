import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/finance/invoice_payment_batch_dialog.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/printing/maintenance_document_pdf_service.dart';
import 'package:quality_line_erp/core/utils/currency_totals_formatter.dart';
import 'package:quality_line_erp/core/utils/erp_display_formatter.dart';
import 'package:quality_line_erp/core/widgets/app_module_action_icon.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_chrome_scope.dart';
import 'package:quality_line_erp/core/widgets/compact_metric_pill.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_phase3_components.dart';
import 'package:quality_line_erp/design_system/kaj_surface.dart';
import 'package:quality_line_erp/design_system/kaj_relationship_stage5_components.dart';
import 'package:quality_line_erp/features/maintenance/controllers/maintenance_controller.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_cost_reconciliation.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_filter.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'add_maintenance_order_page.dart';
import 'maintenance_order_details_dialog.dart';

class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key, this.initialOrderId});

  final String? initialOrderId;

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  final _search = TextEditingController();
  UnifiedFilterCriteria _criteria = const UnifiedFilterCriteria();
  final Set<String> _busyOrderIds = <String>{};
  bool get ar => context.l10n.isArabic;
  String t(String a, String e) => ar ? a : e;

  String get _stage =>
      _criteria.statuses.length == 1 ? _criteria.statuses.first : 'all';

  void _setSearchCriteria(String value) {
    setState(() {
      _criteria = _criteria.copyWith(searchText: value, offset: 0);
    });
  }

  void _setStageCriteria(String stage) {
    setState(() {
      _criteria = _criteria.copyWith(
        statuses: stage == 'all' ? const <String>{} : <String>{stage},
        offset: 0,
      );
    });
  }

  bool _canAction(String action, String legacyPermission) =>
      context.read<AccessController>().canPerformAction(
        'maintenance',
        action,
        legacyPermission: legacyPermission,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final controller = context.read<MaintenanceController>();
      await controller.loadOrders();
      if (!mounted) return;
      final id = widget.initialOrderId?.trim();
      if (id == null || id.isEmpty) return;
      MaintenanceOrderModel? target;
      for (final order in controller.orders) {
        if (order.id == id) {
          target = order;
          break;
        }
      }
      if (target != null) await _openDetails(target);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open([MaintenanceOrderModel? order]) async {
    final permission = order == null
        ? 'maintenance.create'
        : 'maintenance.update';
    if (!await PermissionAction.require(context, permission)) return;
    if (!mounted) return;
    final changed = await showAppWorkspaceDialog<bool>(
      context: context,
      child: AddMaintenanceOrderPage(order: order),
    );
    if (changed == true && mounted)
      await context.read<MaintenanceController>().loadOrders(force: true);
  }

  Future<void> _openDetails(MaintenanceOrderModel order) async {
    final changed = await showAppWorkspaceDialog<bool>(
      context: context,
      child: MaintenanceOrderDetailsDialog(
        order: order,
        onPrint: () => _print(order),
        onEdit: order.canEdit ? () => _open(order) : null,
        onDelete:
            const <String>{
              'order_draft',
              'draft',
              'cancelled',
            }.contains(order.workflowStage)
            ? () => _delete(order)
            : null,
        onCancel: !order.isCancelled ? () => _cancel(order) : null,
        onPayment:
            order.workflowStage == 'invoice_approved' &&
                _canAction('payment', 'cashbox.receipt')
            ? () => _pay(order)
            : null,
      ),
    );
    if (changed == true && mounted) {
      await context.read<MaintenanceController>().loadOrders(force: true);
    }
  }

  Future<void> _run(
    Future<void> Function() task,
    String arFallback,
    String enFallback,
  ) async {
    try {
      await task();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: AppText(
            userFacingError(
              error,
              isArabic: ar,
              arabicFallback: arFallback,
              englishFallback: enFallback,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _delete(MaintenanceOrderModel order) async {
    if (!await PermissionAction.require(context, 'maintenance.delete')) {
      return;
    }
    if (!mounted) return;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: AppText(t('حذف مسودة الصيانة', 'Delete maintenance draft')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppText(
              t(
                'سيتم عكس التجهيز والفاتورة والقيود والارتباطات. تبقى الدفعات المالية كرصيد غير مخصص للعميل وتُحتسب تلقائيًا في أمر لاحق للعميل نفسه وبالعملة نفسها.',
                'This draft and its unexecuted lines will be deleted.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: t('سبب حذف المسودة', 'Draft deletion reason'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: AppText(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: AppText(t('حذف المسودة', 'Delete draft')),
          ),
        ],
      ),
    );
    final value = reason.text;
    reason.dispose();
    if (ok != true || !mounted) return;
    if (value.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            t('سبب الحذف مطلوب.', 'Deletion reason is required.'),
          ),
        ),
      );
      return;
    }
    setState(() => _busyOrderIds.add(order.id));
    await _run(
      () async {
        final controller = context.read<MaintenanceController>();
        await controller.deleteOrder(order.id, reason: value.trim());
      },
      'تعذر حذف أمر الصيانة أو تحديث ارتباطاته.',
      'Unable to delete the maintenance order or update its links.',
    );
    if (mounted) setState(() => _busyOrderIds.remove(order.id));
  }

  Future<void> _cancel(MaintenanceOrderModel order) async {
    if (!await PermissionAction.require(context, 'maintenance.cancel')) {
      return;
    }
    if (!mounted) return;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: AppText(
          t(
            'إلغاء أمر الصيانة وعكس آثاره',
            'Cancel and reverse maintenance order',
          ),
        ),
        content: TextField(
          controller: reason,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: t('سبب الإلغاء', 'Cancellation reason'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: AppText(t('رجوع', 'Back')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: AppText(t('تأكيد', 'Confirm')),
          ),
        ],
      ),
    );
    final value = reason.text;
    reason.dispose();
    if (ok != true || !mounted) return;
    await _run(
      () => context.read<MaintenanceController>().cancelOrder(
        order.id,
        reason: value,
      ),
      'تعذر إلغاء الأمر.',
      'Unable to cancel order.',
    );
  }

  Future<void> _pay(MaintenanceOrderModel order) async {
    if (!_canAction('payment', 'cashbox.receipt')) {
      await context.read<AccessController>().recordDeniedAccess(
        'action:maintenance.payment',
      );
      return;
    }
    if (!mounted) return;

    final controller = context.read<MaintenanceController>();
    final results = await Future.wait([
      controller.listCashAccounts(),
      controller.listSettlementAccounts(),
    ]);
    if (!mounted) return;
    final cashAccounts = results[0].toList(growable: false);
    final settlementAccounts = results[1].toList(growable: false);
    if (cashAccounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            t(
              'لا يوجد صندوق مالي فعال لتسجيل الدفعة',
              'No active cashbox is available for this payment',
            ),
          ),
        ),
      );
      return;
    }

    final remaining = (order.salePrice - order.paidAmount)
        .clamp(0, double.infinity)
        .toDouble();
    if (remaining <= .01) return;

    final drafts = await showInvoicePaymentBatchDialog(
      context: context,
      invoiceCurrency: order.currencyCode,
      remainingAmount: remaining,
      cashAccounts: cashAccounts,
      settlementAccounts: settlementAccounts,
      purchase: false,
      documentLabelArabic: 'دفعات فاتورة الصيانة',
      documentLabelEnglish: 'Maintenance invoice payments',
    );
    if (drafts == null || drafts.isEmpty || !mounted) return;

    await _run(
      () => controller.recordPaymentsBatch(
        order.id,
        drafts.map((draft) => draft.toRpcJson()).toList(growable: false),
      ),
      'تعذر تسجيل دفعات الصيانة.',
      'Unable to record maintenance payments.',
    );
  }

  Future<void> _print(MaintenanceOrderModel order) async {
    final controller = context.read<MaintenanceController>();
    final results = await Future.wait<Object>(<Future<Object>>[
      controller.getOrderLines(order.id),
      controller.getCostReconciliation(order.id),
    ]);
    final lines = results[0] as List<MaintenanceLineModel>;
    final reconciliation = results[1] as MaintenanceCostReconciliation;
    await const MaintenanceDocumentPdfService().print(
      order: order,
      lines: lines,
      issueEvents: reconciliation.issueEvents,
      authoritativeIssuedQuantity: reconciliation.lines
          .where((line) => line['lineType']?.toString() != 'service')
          .fold<double>(
            0,
            (total, line) =>
                total + ((line['issuedQuantity'] as num?)?.toDouble() ?? 0),
          ),
      arabic: ar,
    );
  }

  String _stageLabel(String stage) => switch (stage) {
    'all' => t('الكل', 'All'),
    'order_draft' => t('مسودة أمر', 'Order draft'),
    'order_approved' => t('أمر مصدق', 'Order approved'),
    'stock_issue_draft' => t('مسودة تجهيز', 'Issue draft'),
    'stock_issue_approved' => t('تجهيز مصدق', 'Issue approved'),
    'invoice_draft' => t('مسودة فاتورة', 'Invoice draft'),
    'invoice_approved' => t('فاتورة مصدقة', 'Invoice approved'),
    'paid' => t('مدفوع', 'Paid'),
    'completed' => t('مكتمل', 'Completed'),
    'cancelled' => t('ملغي', 'Cancelled'),
    _ => stage,
  };

  // Retained for compact/alternate workflow presentations.
  // ignore: unused_element
  String _next(MaintenanceOrderModel o) => switch (o.workflowStage) {
    'order_draft' => t('تصديق أمر الصيانة', 'Approve order'),
    'order_approved' => t('إنشاء مسودة تجهيز', 'Create issue draft'),
    'stock_issue_draft' => t('تصديق التجهيز', 'Approve stock issue'),
    'stock_issue_approved' =>
      o.pricingType == 'paid'
          ? t('إنشاء مسودة فاتورة', 'Create invoice draft')
          : t('إكمال الصيانة', 'Complete maintenance'),
    'invoice_draft' => t('تصديق الفاتورة', 'Approve invoice'),
    _ => '',
  };

  // ignore: unused_element
  IconData _nextIcon(MaintenanceOrderModel order) =>
      switch (order.workflowStage) {
        'order_draft' => Icons.verified_outlined,
        'order_approved' => Icons.inventory_2_outlined,
        'stock_issue_draft' => Icons.fact_check_outlined,
        'stock_issue_approved' =>
          order.pricingType == 'paid'
              ? Icons.receipt_long_outlined
              : Icons.task_alt_rounded,
        'invoice_draft' => Icons.verified_user_outlined,
        _ => Icons.arrow_forward_rounded,
      };

  Widget _maintenanceOrdersTable(List<MaintenanceOrderModel> orders) {
    final scheme = Theme.of(context).colorScheme;
    return KajSurface(
      padding: EdgeInsets.zero,
      child: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 44,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 58,
              columnSpacing: 18,
              columns: <DataColumn>[
                DataColumn(label: AppText(t('رقم الأمر', 'Order number'))),
                DataColumn(label: AppText(t('التاريخ والوقت', 'Date / time'))),
                DataColumn(label: AppText(t('العميل', 'Customer'))),
                DataColumn(label: AppText(t('السيارة', 'Car'))),
                DataColumn(label: AppText(t('أُنشئ بواسطة', 'Created by'))),
                DataColumn(label: AppText(t('العملة', 'Currency'))),
                DataColumn(label: AppText(t('الإجمالي', 'Total'))),
                DataColumn(label: AppText(t('مرحلة العمل', 'Workflow stage'))),
                DataColumn(label: AppText(t('الإجراءات', 'Actions'))),
              ],
              rows: orders
                  .map((order) {
                    final dateText = ErpDisplayFormatter.formatDateTime(
                      order.maintenanceDate,
                    );
                    return DataRow(
                      onSelectChanged: (_) => _openDetails(order),
                      cells: <DataCell>[
                        DataCell(
                          AppText(
                            ErpDisplayFormatter.formatReference(
                              order.orderNumber,
                            ),
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        DataCell(AppText(dateText)),
                        DataCell(
                          AppText(
                            order.customerName?.trim().isNotEmpty == true
                                ? order.customerName!
                                : '—',
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 220,
                            child: AppText(
                              order.carName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          AppText(
                            order.createdByName?.trim().isNotEmpty == true
                                ? order.createdByName!
                                : '—',
                          ),
                        ),
                        DataCell(
                          AppText(
                            ErpDisplayFormatter.normalizeCurrency(
                              order.currencyCode,
                            ),
                          ),
                        ),
                        DataCell(
                          AppText(
                            ErpDisplayFormatter.formatMoney(
                              order.salePrice,
                              order.currencyCode,
                            ),
                          ),
                        ),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (order.isCancelled
                                          ? scheme.error
                                          : scheme.primary)
                                      .withValues(alpha: .09),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: AppText(
                              order.workflowLabel(ar),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: order.isCancelled
                                    ? scheme.error
                                    : scheme.primary,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Wrap(
                            spacing: 2,
                            children: <Widget>[
                              AppModuleActionIcon(
                                tooltip: t(
                                  'Details & Items',
                                  'Details & Items',
                                ),
                                icon: Icons.table_rows_outlined,
                                onPressed: () => _openDetails(order),
                              ),
                              AppModuleActionIcon(
                                tooltip: t('PDF / طباعة', 'PDF / Print'),
                                icon: Icons.picture_as_pdf_outlined,
                                onPressed: () => _print(order),
                              ),
                              if (order.workflowStage == 'invoice_approved' &&
                                  _canAction('payment', 'cashbox.receipt'))
                                AppModuleActionIcon(
                                  tooltip: t('تسجيل دفعة', 'Record payment'),
                                  icon: Icons.payments_outlined,
                                  onPressed: () => _pay(order),
                                ),
                              if (order.canEdit &&
                                  PermissionAction.allowed(
                                    context,
                                    'maintenance.update',
                                  ))
                                AppModuleActionIcon(
                                  tooltip: t('تعديل', 'Edit'),
                                  icon: Icons.edit_outlined,
                                  onPressed: () => _open(order),
                                ),
                              if (!order.isCancelled &&
                                  PermissionAction.allowed(
                                    context,
                                    'maintenance.cancel',
                                  ) &&
                                  !<String>{
                                    'draft',
                                    'order_draft',
                                  }.contains(order.workflowStage))
                                AppModuleActionIcon(
                                  tooltip: t('إلغاء وعكس', 'Cancel & reverse'),
                                  icon: Icons.undo_rounded,
                                  onPressed: () => _cancel(order),
                                ),
                              if (<String>{
                                    'draft',
                                    'order_draft',
                                    'cancelled',
                                  }.contains(order.workflowStage) &&
                                  PermissionAction.allowed(
                                    context,
                                    'maintenance.delete',
                                  ))
                                AppModuleActionIcon(
                                  tooltip: t('حذف', 'Delete'),
                                  icon: Icons.delete_outline_rounded,
                                  destructive: true,
                                  busy: _busyOrderIds.contains(order.id),
                                  onPressed: _busyOrderIds.contains(order.id)
                                      ? null
                                      : () => _delete(order),
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  })
                  .toList(growable: false),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<MaintenanceController>();
    final orders = MaintenanceOrderFilter.apply(controller.orders, _criteria);
    final shellOwnsIdentity = AppWorkspaceChromeScope.hasTopBarOf(context);
    final stages = <String>[
      'all',
      'order_draft',
      'order_approved',
      'stock_issue_draft',
      'stock_issue_approved',
      'invoice_draft',
      'invoice_approved',
      'paid',
      'completed',
      'cancelled',
    ];

    return AppEntityPage(
      title: t('إدارة الصيانة والخدمات', 'Service & Maintenance'),
      subtitle: t(
        'متابعة أوامر الصيانة والتجهيز والفوترة والتحصيل من شاشة واحدة.',
        'Track service orders, stock issue, invoicing, and collection in one workspace.',
      ),
      showBackButton: false,
      hideHeader: true,
      actions: const <Widget>[],
      statistics: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CompactMetricPill(
            icon: Icons.build_circle_outlined,
            label: t('إجمالي الأوامر', 'Total orders'),
            value: controller.orders.length.toString(),
          ),
          const SizedBox(width: 10),
          CompactMetricPill(
            icon: Icons.pending_actions_outlined,
            label: t('قيد التنفيذ', 'In progress'),
            value: controller.orders
                .where(
                  (order) => !<String>{
                    'paid',
                    'completed',
                    'cancelled',
                  }.contains(order.workflowStage),
                )
                .length
                .toString(),
          ),
          const SizedBox(width: 10),
          CompactMetricPill(
            icon: Icons.payments_outlined,
            label: t('الإيراد المحصل', 'Collected revenue'),
            value: CurrencyTotalsFormatter.format(
              controller.paidRevenueByCurrency,
            ),
          ),
          const SizedBox(width: 10),
          CompactMetricPill(
            icon: Icons.receipt_long_outlined,
            label: t('إجمالي الكلفة', 'Total cost'),
            value: CurrencyTotalsFormatter.format(
              controller.totalCostByCurrency,
            ),
          ),
        ],
      ),
      toolbar: LayoutBuilder(
        builder: (context, constraints) {
          final commandHero = KajRelationshipHero(
            eyebrow: t('مركز عمليات ما بعد البيع', 'AFTERSALES COMMAND CENTER'),
            title: t(
              'الصيانة والخدمة بوضوح تنفيذي',
              'Maintenance with executive clarity',
            ),
            subtitle: t(
              'تابع استقبال المركبة، التشخيص، المواد، التنفيذ، الفوترة والتحصيل ضمن مسار بصري موحد ومتوافق مع هوية خط الجودة.',
              'Control vehicle intake, diagnosis, parts, execution, invoicing, and collection through one premium KAJ workflow.',
            ),
            icon: Icons.car_repair_rounded,
            primaryAction:
                PermissionAction.allowed(context, 'maintenance.create')
                ? FilledButton.icon(
                    onPressed: () => _open(),
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: AppText(t('أمر صيانة جديد', 'New service order')),
                  )
                : null,
            secondaryAction: OutlinedButton.icon(
              onPressed: () =>
                  context.read<MaintenanceController>().loadOrders(force: true),
              icon: const Icon(Icons.refresh_rounded, size: 17),
              label: AppText(t('تحديث مباشر', 'Live refresh')),
            ),
          );
          final search = TextField(
            controller: _search,
            onChanged: _setSearchCriteria,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: t(
                'بحث برقم الأمر أو السيارة أو العميل',
                'Search by order, vehicle, or customer',
              ),
              suffixIcon: _criteria.searchText.trim().isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _search.clear();
                        _setSearchCriteria('');
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          );
          final stageFilters = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: stages
                  .map(
                    (stage) => Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        label: AppText(
                          _stageLabel(stage),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        selected: _stage == stage,
                        selectedColor: KajDesignTokens.electricBlue.withValues(
                          alpha: .20,
                        ),
                        side: BorderSide(
                          color: _stage == stage
                              ? KajDesignTokens.electricBlue.withValues(
                                  alpha: .48,
                                )
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                        onSelected: (_) => _setStageCriteria(stage),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (shellOwnsIdentity && constraints.maxWidth >= 900)
                Row(
                  children: <Widget>[
                    Expanded(child: search),
                    const SizedBox(width: 8),
                    commandHero,
                  ],
                )
              else ...<Widget>[commandHero, const SizedBox(height: 6), search],
              const SizedBox(height: 6),
              stageFilters,
              const SizedBox(height: 8),
              KajWorkflowStepper(
                compact: constraints.maxWidth < 1100,
                currentIndex: _stage == 'all'
                    ? 0
                    : (stages.indexOf(_stage) - 1).clamp(0, 7).toInt(),
                steps: <String>[
                  t('الاستقبال', 'Intake'),
                  t('التصديق', 'Approval'),
                  t('التجهيز', 'Stock issue'),
                  t('التنفيذ', 'Execution'),
                  t('الفاتورة', 'Invoice'),
                  t('التحصيل', 'Collection'),
                  t('الإكمال', 'Completion'),
                  t('الأرشفة', 'Archive'),
                ],
              ),
            ],
          );
        },
      ),
      body: controller.isLoading
          ? KajRelationshipState.loading(
              label: context.relationshipText(
                'جارٍ تحميل البيانات...',
                'Loading data...',
              ),
            )
          : orders.isEmpty
          ? Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.home_repair_service_outlined,
                      size: 34,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    AppText(
                      t('لا توجد أوامر مطابقة.', 'No matching service orders.'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : _maintenanceOrdersTable(orders),
    );
  }
}

// Retained for alternate compact KPI presentations.
// ignore: unused_element
class _MaintenanceFact extends StatelessWidget {
  const _MaintenanceFact({
    required this.icon,
    required this.label,
    required this.value,
    // ignore: unused_element_parameter
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 118, maxWidth: 170),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: emphasized
            ? KajDesignTokens.electricBlue.withValues(alpha: .08)
            : scheme.surfaceContainerHighest.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: emphasized
              ? KajDesignTokens.electricBlue.withValues(alpha: .24)
              : scheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            size: 14,
            color: emphasized
                ? KajDesignTokens.electricBlue
                : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppText(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 8.5,
                  ),
                ),
                const SizedBox(height: 1),
                AppText(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: emphasized ? KajDesignTokens.electricBlue : null,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
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
