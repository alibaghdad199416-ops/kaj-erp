import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/erp_display_formatter.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/exporting/excel_export_service.dart';
import 'package:quality_line_erp/core/exporting/binary_download_service.dart';
import 'package:quality_line_erp/core/exporting/export_document.dart';
import 'package:quality_line_erp/core/exporting/pdf_export_service.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_chrome_scope.dart';
import 'package:quality_line_erp/core/widgets/compact_metric_pill.dart';
import 'package:quality_line_erp/design_system/kaj_phase3_components.dart';
import 'package:quality_line_erp/design_system/kaj_relationship_stage5_components.dart';
import 'package:quality_line_erp/features/business_partners/customers/controllers/customers_controller.dart';
import 'package:quality_line_erp/features/customer_service/controllers/opportunities_controller.dart';
import 'package:quality_line_erp/features/customer_service/models/opportunity_model.dart';
import 'package:quality_line_erp/features/customer_service/widgets/opportunity_card.dart';
import 'package:quality_line_erp/features/sales/workflow/pages/order_details_dialog.dart';
import 'package:quality_line_erp/features/sales/workflow/pages/sales_order_draft_page.dart';
import 'package:quality_line_erp/features/sales/workflow/repositories/sales_workflow_repository.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/settings/reports/pages/reports_page.dart';
import 'add_opportunity_page.dart';

class CustomerServicePage extends StatefulWidget {
  const CustomerServicePage({super.key});

  @override
  State<CustomerServicePage> createState() => _CustomerServicePageState();
}

class _CustomerServicePageState extends State<CustomerServicePage> {
  final TextEditingController _searchController = TextEditingController();
  OpportunityStatus? _filter;

  bool get ar => context.l10n.isArabic;
  String t(String arText, String enText) => ar ? arText : enText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.wait<void>([
        context.read<OpportunitiesController>().loadOpportunities(),
        context.read<CustomersController>().loadCustomers(),
      ]);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<OpportunityModel> _visibleItems(List<OpportunityModel> source) {
    final query = _searchController.text.trim().toLowerCase();
    return source
        .where((item) {
          final matchesStatus = _filter == null || item.status == _filter;
          final haystack = [
            item.opportunityNumber,
            item.title,
            item.customerName,
            item.customerPhone,
            item.assignedUserName,
            item.source,
            item.stage,
            item.currency,
            item.salesOrderNumber ?? '',
            item.salesOrderStatus ?? '',
            item.deliveryNumber ?? '',
            item.deliveryStatus ?? '',
            item.invoiceNumber ?? '',
            item.invoiceStatus ?? '',
            item.paymentStatus ?? '',
            item.maintenanceOrderNumber ?? '',
            item.maintenanceOrderStatus ?? '',
            item.carName ?? '',
          ].join(' ').toLowerCase();
          return matchesStatus && (query.isEmpty || haystack.contains(query));
        })
        .toList(growable: false);
  }

  Widget _filterChip(OpportunityStatus? value, String label) => FilterChip(
    label: AppText(label, style: const TextStyle(fontSize: 11)),
    selected: _filter == value,
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 3),
    onSelected: (_) => setState(() => _filter = value),
  );

  ExportDocument _opportunityExport(List<OpportunityModel> rows) {
    final language = ar ? 'ar' : 'en';
    return ExportDocument(
      title: t('الفرص التجارية', 'Commercial Opportunities'),
      subtitle: t(
        'تقرير دورة الفرصة وربطها بسير المبيعات والصيانة',
        'Canonical sales and maintenance opportunity report',
      ),
      language: language,
      generatedAt: DateTime.now(),
      columns: <ExportColumn>[
        ExportColumn(key: 'number', label: t('رقم الفرصة', 'Opportunity No.')),
        ExportColumn(key: 'title', label: t('العنوان', 'Title'), width: 1.5),
        ExportColumn(
          key: 'customer',
          label: t('العميل', 'Customer'),
          width: 1.3,
        ),
        ExportColumn(key: 'phone', label: t('الهاتف', 'Phone')),
        ExportColumn(key: 'status', label: t('الحالة', 'Status')),
        ExportColumn(key: 'stage', label: t('المرحلة', 'Stage')),
        ExportColumn(key: 'owner', label: t('المسؤول', 'Owner')),
        ExportColumn(
          key: 'value',
          label: t('القيمة المتوقعة', 'Expected value'),
          type: ExportValueType.money,
        ),
        ExportColumn(key: 'currency', label: t('العملة', 'Currency')),
        ExportColumn(key: 'salesOrder', label: t('أمر البيع', 'Sales order')),
        ExportColumn(
          key: 'salesStatus',
          label: t('حالة البيع', 'Sales status'),
        ),
        ExportColumn(
          key: 'maintenanceOrder',
          label: t('أمر الصيانة', 'Maintenance order'),
        ),
        ExportColumn(
          key: 'maintenanceStatus',
          label: t('حالة الصيانة', 'Maintenance status'),
        ),
        ExportColumn(key: 'delivery', label: t('التسليم', 'Delivery')),
        ExportColumn(key: 'invoice', label: t('الفاتورة', 'Invoice')),
        ExportColumn(
          key: 'invoiceStatus',
          label: t('حالة الفاتورة', 'Invoice status'),
        ),
        ExportColumn(
          key: 'paymentStatus',
          label: t('حالة الدفع', 'Payment status'),
        ),
        ExportColumn(
          key: 'paid',
          label: t('المدفوع', 'Paid'),
          type: ExportValueType.money,
        ),
        ExportColumn(
          key: 'remaining',
          label: t('المتبقي', 'Remaining'),
          type: ExportValueType.money,
        ),
        ExportColumn(
          key: 'createdAt',
          label: t('تاريخ الإنشاء', 'Created at'),
          type: ExportValueType.dateTime,
        ),
        ExportColumn(
          key: 'closedAt',
          label: t('تاريخ الإغلاق', 'Closed at'),
          type: ExportValueType.dateTime,
        ),
      ],
      rows: rows
          .map(
            (o) => <Object?>[
              o.opportunityNumber,
              o.title,
              o.customerName,
              o.customerPhone,
              o.status.name,
              o.stage,
              o.assignedUserName,
              o.expectedValue,
              o.currency,
              o.salesOrderNumber ?? '',
              o.salesOrderStatus ?? '',
              o.maintenanceOrderNumber ?? '',
              o.maintenanceOrderStatus ?? '',
              o.deliveryNumber ?? '',
              o.invoiceNumber ?? '',
              o.invoiceStatus ?? '',
              o.paymentStatus ?? '',
              o.paidAmount,
              o.remainingAmount,
              o.createdAt,
              o.closedAt,
            ],
          )
          .toList(growable: false),
    );
  }

  Future<void> _exportOpportunitiesExcel(List<OpportunityModel> rows) async {
    final bytes = await ExcelExportService().build(_opportunityExport(rows));
    await BinaryDownloadService.save(
      fileName: 'opportunities_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      bytes: bytes,
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  Future<void> _exportOpportunitiesPdf(List<OpportunityModel> rows) async {
    await PdfExportService().save(_opportunityExport(rows));
  }

  void _showOpportunityError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Theme.of(context).colorScheme.error,
        content: AppText(
          userFacingError(
            error,
            isArabic: context.l10n.isArabic,
            arabicFallback: 'تعذر تنفيذ عملية الفرصة التجارية.',
            englishFallback: 'Unable to complete the opportunity action.',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<OpportunitiesController>();
    final access = context.watch<AccessController>();
    final items = _visibleItems(controller.opportunities);
    final scheme = Theme.of(context).colorScheme;
    final shellOwnsIdentity = AppWorkspaceChromeScope.hasTopBarOf(context);
    final canCreate = access.hasPermission('customer_service.create');
    final canViewReports = access.hasPermission('reports.view');
    final canExport =
        access.hasPermission('customer_service.view') &&
        access.hasPermission('reports.export');

    final newOpportunity = canCreate
        ? FilledButton.icon(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            ),
            onPressed: _add,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: AppText(t('فرصة جديدة', 'New opportunity')),
          )
        : null;

    final secondaryActions = <Widget>[
      if (canViewReports)
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          ),
          onPressed: () => showAppModuleDialog<void>(
            context: context,
            title: t(
              'تقارير خدمة العملاء والفرص',
              'Customer service and opportunity reports',
            ),
            maxWidth: 1180,
            maxHeight: 820,
            builder: (_) => const ReportsPage(initialModule: 'opportunities'),
          ),
          icon: const Icon(Icons.summarize_outlined, size: 17),
          label: AppText(t('تقرير تنفيذي', 'Executive report')),
        ),
      if (canExport) ...[
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
          ),
          onPressed: items.isEmpty
              ? null
              : () => _exportOpportunitiesExcel(items),
          icon: const Icon(Icons.table_view_outlined, size: 17),
          label: const AppText('Excel'),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
          ),
          onPressed: items.isEmpty
              ? null
              : () => _exportOpportunitiesPdf(items),
          icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
          label: const AppText('PDF'),
        ),
      ],
    ];

    final actions = Wrap(
      spacing: 7,
      runSpacing: 7,
      alignment: WrapAlignment.end,
      children: <Widget>[...secondaryActions, ?newOpportunity],
    );

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(22, shellOwnsIdentity ? 8 : 16, 22, 18),
          child: Column(
            children: [
              if (shellOwnsIdentity)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 1080;
                    if (stacked) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _StatisticsStrip(controller: controller),
                          if (actions.children.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: actions,
                            ),
                          ],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(
                          child: _StatisticsStrip(controller: controller),
                        ),
                        if (actions.children.isNotEmpty) ...[
                          const SizedBox(width: 10),
                          actions,
                        ],
                      ],
                    );
                  },
                )
              else ...[
                KajRelationshipHero(
                  eyebrow: t(
                    'تطوير الأعمال وتجربة العميل',
                    'CUSTOMER EXPERIENCE & GROWTH',
                  ),
                  title: t(
                    'مركز الفرص التجارية',
                    'Commercial opportunity center',
                  ),
                  subtitle: t(
                    'حوّل الاهتمام الأولي إلى علاقة تجارية قابلة للقياس، مع متابعة المصدر والمالك والقيمة وموعد التواصل والارتباط بأمر البيع.',
                    'Turn first interest into a measurable commercial relationship with source, owner, value, follow-up, and sales-order linkage in one premium workspace.',
                  ),
                  icon: Icons.auto_graph_rounded,
                  primaryAction: newOpportunity,
                  secondaryAction: secondaryActions.isEmpty
                      ? null
                      : Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: secondaryActions,
                        ),
                ),
                const SizedBox(height: 10),
                _StatisticsStrip(controller: controller),
              ],
              const SizedBox(height: 9),
              KajWorkflowStepper(
                currentIndex: controller.opportunities.isEmpty
                    ? -1
                    : _filter == OpportunityStatus.won
                    ? 4
                    : _filter == OpportunityStatus.lost
                    ? 3
                    : _filter == OpportunityStatus.pending
                    ? 2
                    : 0,
                compact: MediaQuery.sizeOf(context).width < 1100,
                steps: <String>[
                  t('الاهتمام', 'Lead'),
                  t('التأهيل', 'Qualification'),
                  t('المتابعة', 'Follow-up'),
                  t('القرار', 'Decision'),
                  t('أمر البيع', 'Sales order'),
                ],
              ),
              const SizedBox(height: 9),
              LayoutBuilder(
                builder: (context, constraints) {
                  final search = TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                      hintText: t(
                        'البحث برقم الفرصة أو العميل أو أمر البيع أو أمر الصيانة',
                        'Search by opportunity, customer, sales order, or maintenance order',
                      ),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                    ),
                  );
                  final filters = Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _filterChip(null, t('الكل', 'All')),
                      _filterChip(
                        OpportunityStatus.pending,
                        t('قيد الانتظار', 'Pending'),
                      ),
                      _filterChip(OpportunityStatus.won, t('رابحة', 'Won')),
                      _filterChip(OpportunityStatus.lost, t('خاسرة', 'Lost')),
                    ],
                  );
                  final results = Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.filter_list_rounded, size: 16),
                    label: AppText(
                      '${t('النتائج', 'Results')}: ${items.length}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  );

                  if (constraints.maxWidth < 980) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        search,
                        const SizedBox(height: 7),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: filters),
                            const SizedBox(width: 7),
                            results,
                          ],
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: search),
                      const SizedBox(width: 8),
                      filters,
                      const SizedBox(width: 7),
                      results,
                    ],
                  );
                },
              ),
              const SizedBox(height: 9),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: controller.loadOpportunities,
                  child: controller.isLoading && items.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(top: 48),
                          children: [
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.support_agent_outlined,
                                    size: 38,
                                    color: scheme.outline,
                                  ),
                                  const SizedBox(height: 8),
                                  AppText(
                                    t(
                                      'لا توجد فرص مطابقة للبحث والفلاتر',
                                      'No opportunities match the search and filters',
                                    ),
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.only(bottom: 4),
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final opportunity = items[index];
                            return OpportunityCard(
                              opportunity: opportunity,
                              onEdit: () => _edit(opportunity),
                              onWon: () => _won(opportunity),
                              onLost: () => _lost(opportunity),
                              onDelete: () => _delete(opportunity),
                              canEdit: access.hasPermission(
                                'customer_service.update',
                              ),
                              canDelete: access.hasPermission(
                                'customer_service.delete',
                              ),
                              canUpdateStatus: access.hasPermission(
                                'customer_service.update',
                              ),
                              canCreateSale: access.hasPermission(
                                'sales.create',
                              ),
                              canViewSale: access.hasPermission('sales.view'),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _add() async {
    if (!await PermissionAction.require(context, 'customer_service.create'))
      return;
    if (!mounted) return;
    await context.read<CustomersController>().loadCustomers();
    if (!mounted) return;
    await showAppWorkspaceDialog<void>(
      context: context,
      title: t('إضافة فرصة', 'Add opportunity'),
      windowKey: 'opportunities:add',
      child: const AddOpportunityPage(),
    );
  }

  Future<void> _edit(OpportunityModel opportunity) async {
    if (!await PermissionAction.require(context, 'customer_service.update'))
      return;
    if (!mounted) return;
    await context.read<CustomersController>().loadCustomers();
    if (!mounted) return;
    await showAppWorkspaceDialog<void>(
      context: context,
      title: t('تعديل فرصة', 'Edit opportunity'),
      windowKey: 'opportunities:edit:${opportunity.id}',
      child: AddOpportunityPage(opportunity: opportunity),
    );
  }

  Future<void> _lost(OpportunityModel opportunity) async {
    if (!await PermissionAction.require(context, 'customer_service.update'))
      return;
    if (!mounted) return;
    try {
      await context.read<OpportunitiesController>().markLost(opportunity);
    } catch (error) {
      _showOpportunityError(error);
    }
  }

  Future<void> _delete(OpportunityModel opportunity) async {
    if (!await PermissionAction.require(context, 'customer_service.delete'))
      return;
    if (!mounted) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: AppTranslation.translate('حذف الفرصة'),
      message: AppTranslation.translate('هل تريد حذف الفرصة المحددة؟'),
      confirmLabel: AppTranslation.translate('حذف'),
      destructive: true,
    );

    if (confirmed == true && mounted) {
      try {
        await context.read<OpportunitiesController>().delete(opportunity);
      } catch (error) {
        _showOpportunityError(error);
      }
    }
  }

  Future<void> _won(OpportunityModel opportunity) async {
    final repository = SalesWorkflowRepository();
    try {
      var linked = await repository.findOrderByOpportunity(opportunity.id);
      if (!mounted) return;
      if (linked == null) {
        if (!await PermissionAction.require(context, 'customer_service.update'))
          return;
        if (!mounted) return;
        if (!await PermissionAction.require(context, 'sales.create')) return;
      } else if (!await PermissionAction.require(context, 'sales.view')) {
        return;
      }
      if (!mounted) return;
      var orderId = linked?['id']?.toString();

      if (orderId == null || orderId.isEmpty) {
        final created = await showAppWorkspaceDialog<bool>(
          context: context,
          title: t('إنشاء مسودة أمر بيع', 'Create sales order draft'),
          windowKey: 'opportunities:sales-order:${opportunity.id}:draft',
          child: SalesOrderDraftPage(
            initialCustomerId: opportunity.customerId,
            initialCurrency: opportunity.currency,
            initialOpportunityNumber: opportunity.opportunityNumber,
            opportunityId: opportunity.id,
          ),
        );
        if (created != true || !mounted) return;
        linked = await repository.findOrderByOpportunity(opportunity.id);
        orderId = linked?['id']?.toString();
      }

      if (!mounted || orderId == null || orderId.isEmpty) {
        throw StateError(
          t(
            'تم حفظ المسودة لكن تعذر العثور على أمر البيع المرتبط.',
            'The draft was saved, but the linked sales order could not be found.',
          ),
        );
      }

      await showAppWorkspaceDialog<bool>(
        context: context,
        title: t('أمر البيع المرتبط بالفرصة', 'Opportunity sales order'),
        windowKey: 'opportunities:sales-order:${opportunity.id}:workflow',
        maxWidth: 1180,
        maxHeight: 820,
        child: OrderDetailsDialog(orderId: orderId, purchase: false),
      );
      if (!mounted) return;
      await context.read<OpportunitiesController>().loadOpportunities();
    } catch (error) {
      _showOpportunityError(error);
    }
  }
}

class _StatisticsStrip extends StatelessWidget {
  const _StatisticsStrip({required this.controller});

  final OpportunitiesController controller;

  String _pipelineValue(
    BuildContext context,
    OpportunitiesController controller,
  ) {
    final totals = controller.pipelineValueByCurrency;
    if (totals.isEmpty) return '-';
    final locale = context.l10n.isArabic ? 'ar_IQ' : 'en_US';
    final preferredOrder = <String>['USD', 'IQD'];
    final currencies = <String>[
      ...preferredOrder.where(totals.containsKey),
      ...totals.keys.where((code) => !preferredOrder.contains(code)).toList()
        ..sort(),
    ];
    return currencies
        .map(
          (currency) => ErpDisplayFormatter.money(
            totals[currency],
            currency,
            locale: locale,
          ),
        )
        .join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    String t(String arText, String enText) => ar ? arText : enText;
    final items = <({IconData icon, String label, String value})>[
      (
        icon: Icons.hourglass_top_rounded,
        label: t('قيد الانتظار', 'Pending'),
        value: '${controller.pendingCount}',
      ),
      (
        icon: Icons.emoji_events_outlined,
        label: t('رابحة', 'Won'),
        value: '${controller.wonCount}',
      ),
      (
        icon: Icons.trending_down_rounded,
        label: t('خاسرة', 'Lost'),
        value: '${controller.lostCount}',
      ),
      (
        icon: Icons.account_tree_outlined,
        label: t('قيمة المسار', 'Pipeline value'),
        value: _pipelineValue(context, controller),
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            CompactMetricPill(
              icon: items[index].icon,
              label: items[index].label,
              value: items[index].value,
            ),
            if (index != items.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}
