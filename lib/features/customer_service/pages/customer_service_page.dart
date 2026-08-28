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
import 'package:quality_line_erp/core/widgets/compact_metric_pill.dart';
import 'package:quality_line_erp/design_system/kaj_phase3_components.dart';
import 'package:quality_line_erp/design_system/kaj_query_toolbar.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';
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
  bool get ar => context.l10n.isArabic;
  String t(String arText, String enText) => ar ? arText : enText;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<OpportunitiesController>().loadOpportunities();
    });
  }

  ExportDocument _opportunityExport(List<OpportunityModel> rows) {
    final language = ar ? 'ar' : 'en';
    return ExportDocument(
      title: t('الفرص التجارية', 'Commercial Opportunities'),
      subtitle: t(
        'تقرير دورة الفرصة وربطها بسير المبيعات',
        'Canonical sales-workflow opportunity report',
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
              o.assignedUserName,
              o.expectedValue,
              o.currency,
              o.saleId ?? '',
              o.salesOrderStatus ?? '',
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

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<OpportunitiesController>();
    final access = context.watch<AccessController>();
    final items = controller.visibleOpportunities;
    final scheme = Theme.of(context).colorScheme;
    final selectedStatus = controller.query.state.filters
        .where((token) => token.key == 'status')
        .map((token) => token.value.toString())
        .firstOrNull;
    final filterOptions = <UnifiedQueryFilterOption>[
      UnifiedQueryFilterOption(
        token: UnifiedFilterToken(
          key: 'status',
          label: t('الحالة', 'Status'),
          value: OpportunityStatus.pending.name,
          valueLabel: t('قيد الانتظار', 'Pending'),
        ),
        icon: Icons.hourglass_top_rounded,
      ),
      UnifiedQueryFilterOption(
        token: UnifiedFilterToken(
          key: 'status',
          label: t('الحالة', 'Status'),
          value: OpportunityStatus.won.name,
          valueLabel: t('رابحة', 'Won'),
        ),
        icon: Icons.emoji_events_outlined,
      ),
      UnifiedQueryFilterOption(
        token: UnifiedFilterToken(
          key: 'status',
          label: t('الحالة', 'Status'),
          value: OpportunityStatus.lost.name,
          valueLabel: t('خاسرة', 'Lost'),
        ),
        icon: Icons.trending_down_rounded,
      ),
    ];
    final sortOptions = <UnifiedQuerySortOption>[
      UnifiedQuerySortOption(
        rule: UnifiedSortRule(
          field: 'opportunityNumber',
          label: t('رقم الفرصة', 'Opportunity no.'),
        ),
        icon: Icons.tag_outlined,
      ),
      UnifiedQuerySortOption(
        rule: UnifiedSortRule(
          field: 'customerName',
          label: t('العميل', 'Customer'),
        ),
        icon: Icons.person_outline,
      ),
      UnifiedQuerySortOption(
        rule: UnifiedSortRule(
          field: 'expectedValue',
          label: t('القيمة', 'Value'),
        ),
        icon: Icons.payments_outlined,
      ),
      UnifiedQuerySortOption(
        rule: UnifiedSortRule(field: 'status', label: t('الحالة', 'Status')),
        icon: Icons.flag_outlined,
      ),
      UnifiedQuerySortOption(
        rule: UnifiedSortRule(
          field: 'followUpDate',
          label: t('موعد المتابعة', 'Follow-up'),
        ),
        icon: Icons.event_outlined,
      ),
      UnifiedQuerySortOption(
        rule: UnifiedSortRule(
          field: 'createdAt',
          label: t('تاريخ الإنشاء', 'Created'),
        ),
        icon: Icons.schedule_outlined,
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
          child: Column(
            children: [
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
                primaryAction: access.hasPermission('customer_service.create')
                    ? FilledButton.icon(
                        onPressed: _add,
                        icon: const Icon(Icons.add_rounded),
                        label: AppText(t('فرصة جديدة', 'New opportunity')),
                      )
                    : null,
                secondaryAction:
                    (access.hasPermission('reports.view') ||
                        (access.hasPermission('customer_service.view') &&
                            access.hasPermission('reports.export')))
                    ? Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          if (access.hasPermission('reports.view'))
                            OutlinedButton.icon(
                              onPressed: () => showAppModuleDialog<void>(
                                context: context,
                                title: t(
                                  'تقارير خدمة العملاء والفرص',
                                  'Customer service and opportunity reports',
                                ),
                                maxWidth: 1180,
                                maxHeight: 820,
                                builder: (_) => const ReportsPage(
                                  initialModule: 'opportunities',
                                ),
                              ),
                              icon: const Icon(Icons.summarize_outlined),
                              label: AppText(
                                t('تقرير تنفيذي', 'Executive report'),
                              ),
                            ),
                          if (access.hasPermission('customer_service.view') &&
                              access.hasPermission('reports.export')) ...[
                            OutlinedButton.icon(
                              onPressed: items.isEmpty
                                  ? null
                                  : () => _exportOpportunitiesExcel(items),
                              icon: const Icon(Icons.table_view_outlined),
                              label: const AppText('Excel'),
                            ),
                            OutlinedButton.icon(
                              onPressed: items.isEmpty
                                  ? null
                                  : () => _exportOpportunitiesPdf(items),
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                              label: const AppText('PDF'),
                            ),
                          ],
                        ],
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              KajWorkflowStepper(
                currentIndex: controller.opportunities.isEmpty
                    ? -1
                    : selectedStatus == OpportunityStatus.won.name
                    ? 4
                    : selectedStatus == OpportunityStatus.lost.name
                    ? 3
                    : selectedStatus == OpportunityStatus.pending.name
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
              const SizedBox(height: 12),
              KajQueryToolbar(
                controller: controller.query,
                hintText: t(
                  'البحث برقم الفرصة أو العميل أو الهاتف أو المسؤول',
                  'Search by opportunity, customer, phone, or owner',
                ),
                filters: filterOptions,
                sorts: sortOptions,
                compact: true,
                filterButtonLabel: t('فلترة', 'Filter'),
                sortButtonLabel: t('فرز', 'Sort'),
                clearAllLabel: t('مسح الكل', 'Clear all'),
                clearSearchTooltip: t('مسح البحث', 'Clear search'),
                ascendingLabel: t('تصاعدي', 'Ascending'),
                descendingLabel: t('تنازلي', 'Descending'),
              ),
              const SizedBox(height: 10),
              _StatisticsStrip(controller: controller),
              const SizedBox(height: 14),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: controller.loadOpportunities,
                  child: controller.isLoading && items.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 120),
                            Icon(
                              Icons.support_agent_outlined,
                              size: 54,
                              color: scheme.outline,
                            ),
                            const SizedBox(height: 12),
                            Center(
                              child: AppText(
                                t(
                                  'لا توجد فرص مطابقة للبحث والفلاتر',
                                  'No opportunities match the search and filters',
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: items.length,
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
    await context.read<OpportunitiesController>().markLost(opportunity);
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
    if (confirmed == true && mounted)
      await context.read<OpportunitiesController>().delete(opportunity);
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
            opportunityId: opportunity.id,
          ),
        );
        if (created != true || !mounted) return;
        linked = await repository.findOrderByOpportunity(opportunity.id);
        orderId = linked?['id']?.toString();
      }
      if (!mounted || orderId == null || orderId.isEmpty)
        throw StateError(
          t(
            'تم حفظ المسودة لكن تعذر العثور على أمر البيع المرتبط.',
            'The draft was saved, but the linked sales order could not be found.',
          ),
        );
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(error, isArabic: context.l10n.isArabic),
          ),
        ),
      );
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
