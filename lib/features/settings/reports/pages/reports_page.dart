import 'package:quality_line_erp/app/route_names.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/currency_totals_formatter.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';

import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/widgets/app_top_navigation.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_back_button.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/settings/reports/controllers/reports_controller.dart';
import 'package:quality_line_erp/features/settings/reports/data/contextual_reports_repository.dart';
import 'package:quality_line_erp/features/settings/reports/data/execution_audit_repository.dart';
import 'package:quality_line_erp/features/settings/reports/models/contextual_report_section.dart';
import 'package:quality_line_erp/features/settings/reports/models/execution_audit_row.dart';
import 'package:quality_line_erp/features/settings/reports/models/report_export_options.dart';
import 'package:quality_line_erp/features/settings/reports/models/report_model.dart';
import 'package:quality_line_erp/features/settings/reports/services/report_export_service.dart';
import 'package:quality_line_erp/features/settings/reports/services/report_preferences_service.dart';
import 'package:quality_line_erp/features/settings/reports/widgets/report_section_customization_dialog.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, this.initialModule = 'overview'});

  final String initialModule;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  final _exportService = ReportExportService();
  final _preferencesService = ReportPreferencesService();
  bool _isExporting = false;
  ReportExportOptions _exportOptions = const ReportExportOptions();
  List<SavedReportPreset> _savedPresets = const [];
  late String _selectedModule;
  final _executionRepository = ExecutionAuditRepository();
  List<ExecutionAuditRow> _executionRows = const [];
  final _contextualRepository = ContextualReportsRepository();
  List<ContextualReportSection> _contextualSections = const [];
  bool _isLoadingContextual = false;
  String? _contextualError;

  Widget _reportField(String field, Widget child, {String? writePermission}) =>
      FieldPermissionControl(
        resource: 'reports',
        field: field,
        viewPermission: 'reports.view',
        writePermission: writePermission,
        child: child,
      );

  Widget _reportValue(String field, Widget child) => FieldPermissionVisibility(
    resource: 'reports',
    field: field,
    viewPermission: 'reports.view',
    child: child,
  );

  bool _canViewReportField(String field) => context
      .read<AccessController>()
      .canViewField('reports', field, viewPermission: 'reports.view');

  @override
  void initState() {
    super.initState();
    _selectedModule = widget.initialModule;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<ReportsController>().loadReports();
      if (_canViewReportField('auditDetails')) {
        await _loadExecutionRows();
      }
      if (_canViewReportField('contextualDetails')) {
        await _loadContextualSections();
      }
      await _loadReportPreferences();
    });
  }

  Future<void> _loadReportPreferences() async {
    final options = await _preferencesService.loadOptions();
    final presets = await _preferencesService.loadPresets();
    if (!mounted) return;
    setState(() {
      _exportOptions = options;
      _savedPresets = presets;
    });
  }

  String _periodLabel(ReportsController controller) {
    final formatter = DateFormat('yyyy/MM/dd');
    if (controller.startDate == null || controller.endDate == null) {
      return AppTranslation.translate('جميع الفترات');
    }
    return '${AppTranslation.translate('من')} ${formatter.format(controller.startDate!)} ${AppTranslation.translate('إلى')} ${formatter.format(controller.endDate!)}';
  }

  Future<void> _showExportSettings() async {
    final titleController = TextEditingController(text: _exportOptions.title);
    var draft = _exportOptions;

    await showAppWorkspaceDialogBuilder<void>(
      context: context,
      title: context.l10n.isArabic ? 'تخصيص التقرير' : 'Customize report',
      builder: (pageContext) => StatefulBuilder(
        builder: (context, setPageState) {
          Future<void> savePreset() async {
            final nameController = TextEditingController(
              text: titleController.text.trim(),
            );
            final name = await showAppWorkspaceDialogBuilder<String>(
              context: context,
              title: context.l10n.isArabic
                  ? 'حفظ إعداد تقرير'
                  : 'Save report preset',
              builder: (dialogContext) => AlertDialog(
                title: const AppText('حفظ إعداد تقرير'),
                content: TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: AppTranslation.translate('اسم الإعداد'),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const AppText('إلغاء'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      dialogContext,
                      nameController.text.trim(),
                    ),
                    child: const AppText('حفظ'),
                  ),
                ],
              ),
            );
            nameController.dispose();
            if (name == null || name.isEmpty) return;

            draft = draft.copyWith(
              title: titleController.text.trim().isEmpty
                  ? 'تقرير خط الجودة'
                  : titleController.text.trim(),
            );
            final updated = [
              ..._savedPresets.where((item) => item.name != name),
              SavedReportPreset(name: name, options: draft),
            ];
            await _preferencesService.savePresets(updated);
            if (!mounted || !context.mounted) return;
            setState(() => _savedPresets = updated);
            setPageState(() {});
          }

          Future<void> apply() async {
            draft = draft.copyWith(
              title: titleController.text.trim().isEmpty
                  ? 'تقرير خط الجودة'
                  : titleController.text.trim(),
            );
            await _preferencesService.saveOptions(draft);
            if (!mounted) return;
            setState(() => _exportOptions = draft);
            if (pageContext.mounted) Navigator.pop(pageContext);
          }

          return Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: const AppText('تخصيص التقرير'),
              actions: [
                OutlinedButton.icon(
                  onPressed: savePreset,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const AppText('حفظ كإعداد'),
                ),
                const SizedBox(width: 6),
                TextButton(
                  onPressed: () => Navigator.pop(pageContext),
                  child: const AppText('إلغاء'),
                ),
                const SizedBox(width: 6),
                FilledButton(onPressed: apply, child: const AppText('تطبيق')),
                const SizedBox(width: 8),
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate('عنوان التقرير'),
                      prefixIcon: const Icon(Icons.title),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: draft.language,
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate('لغة التقرير'),
                      prefixIcon: const Icon(Icons.language),
                      border: const OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'ar',
                        child: AppText('العربية — مصطلحات محاسبية عربية'),
                      ),
                      DropdownMenuItem(
                        value: 'en',
                        child: AppText('الإنجليزية — المصطلحات المحاسبية'),
                      ),
                    ],
                    onChanged: (value) => setPageState(
                      () => draft = draft.copyWith(language: value ?? 'ar'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    value: draft.includeModuleDetails,
                    onChanged: (value) => setPageState(
                      () => draft = draft.copyWith(includeModuleDetails: value),
                    ),
                    title: const AppText('تفاصيل المودل المحدد'),
                    subtitle: const AppText(
                      'يخصص المؤشرات بحسب المبيعات أو المشتريات أو المخزون أو المالية وغيرها.',
                    ),
                  ),
                  SwitchListTile(
                    value: draft.includeGeneratedAt,
                    onChanged: (value) => setPageState(
                      () => draft = draft.copyWith(includeGeneratedAt: value),
                    ),
                    title: const AppText('إظهار تاريخ إنشاء التقرير'),
                  ),
                  SwitchListTile(
                    value: draft.includeSummary,
                    onChanged: (value) => setPageState(
                      () => draft = draft.copyWith(includeSummary: value),
                    ),
                    title: const AppText('الملخص المالي والإداري'),
                  ),
                  SwitchListTile(
                    value: draft.includeOperational,
                    onChanged: (value) => setPageState(
                      () => draft = draft.copyWith(includeOperational: value),
                    ),
                    title: const AppText('المؤشرات التشغيلية'),
                  ),
                  SwitchListTile(
                    value: draft.includeMonthly,
                    onChanged: (value) => setPageState(
                      () => draft = draft.copyWith(includeMonthly: value),
                    ),
                    title: const AppText('أداء الأشهر'),
                  ),
                  SwitchListTile(
                    value: draft.includeExecutors,
                    onChanged: (value) => setPageState(
                      () => draft = draft.copyWith(includeExecutors: value),
                    ),
                    title: const AppText('سجل منفذي الإدخال'),
                  ),
                  SwitchListTile(
                    value: draft.landscape,
                    onChanged: (value) => setPageState(
                      () => draft = draft.copyWith(landscape: value),
                    ),
                    secondary: Icon(
                      draft.landscape
                          ? Icons.landscape_outlined
                          : Icons.portrait_outlined,
                    ),
                    title: AppText(
                      context.l10n.isArabic
                          ? (draft.landscape ? 'A4 أفقي' : 'A4 عمودي')
                          : (draft.landscape ? 'A4 Landscape' : 'A4 Portrait'),
                    ),
                    subtitle: AppText(
                      context.l10n.isArabic
                          ? 'يمكن اختيار اتجاه الصفحة، والجداول العريضة تتحول تلقائيًا إلى الوضع الأفقي.'
                          : 'Choose the page orientation. Wide tables automatically use landscape mode.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _contextualSections.isEmpty
                        ? null
                        : () async {
                            final customized =
                                await showAppWorkspaceDialogBuilder<
                                  ReportExportOptions
                                >(
                                  context: context,
                                  title: context.l10n.isArabic
                                      ? 'اختيار الحقول والفلاتر والفرز'
                                      : 'Fields, filters, and sorting',
                                  builder: (_) =>
                                      ReportSectionCustomizationDialog(
                                        sections: _contextualSections,
                                        initialOptions: draft,
                                      ),
                                );
                            if (customized != null && context.mounted) {
                              setPageState(() => draft = customized);
                            }
                          },
                    icon: const Icon(Icons.view_column_outlined),
                    label: const AppText('اختيار الحقول والفلاتر والفرز'),
                  ),
                  if (_savedPresets.isNotEmpty) ...[
                    const Divider(height: 28),
                    const AppText(
                      'الإعدادات المحفوظة',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _savedPresets
                          .map(
                            (preset) => InputChip(
                              label: AppText(preset.name),
                              onPressed: () => setPageState(() {
                                draft = preset.options;
                                titleController.text = draft.title;
                              }),
                              onDeleted: () async {
                                final updated = _savedPresets
                                    .where((item) => item.name != preset.name)
                                    .toList();
                                await _preferencesService.savePresets(updated);
                                if (!mounted || !context.mounted) return;
                                setState(() => _savedPresets = updated);
                                setPageState(() {});
                              },
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
    titleController.dispose();
  }

  Future<void> _loadContextualSections() async {
    if (!_canViewReportField('contextualDetails')) {
      if (mounted) {
        setState(() {
          _contextualSections = const [];
          _contextualError = null;
          _isLoadingContextual = false;
        });
      }
      return;
    }
    if (mounted) {
      setState(() => _isLoadingContextual = true);
    }
    final controller = context.read<ReportsController>();
    try {
      final sections = await _contextualRepository.load(
        _selectedModule,
        startDate: controller.startDate,
        endDate: controller.endDate,
      );
      if (mounted)
        setState(() {
          _contextualSections = sections;
          _contextualError = null;
        });
    } catch (error) {
      if (mounted)
        setState(() {
          _contextualSections = const [];
          AppLogger.debug('Contextual report loading failed: $error');
          _contextualError = userFacingError(
            error,
            isArabic: context.l10n.isArabic,
            arabicFallback: 'تعذر تحميل بيانات التقرير.',
            englishFallback: 'Unable to load report data.',
          );
        });
    } finally {
      if (mounted) setState(() => _isLoadingContextual = false);
    }
  }

  Future<void> _loadExecutionRows() async {
    if (!_canViewReportField('auditDetails')) {
      if (mounted) setState(() => _executionRows = const []);
      return;
    }
    final controller = context.read<ReportsController>();
    final rows = await _executionRepository.load(
      _selectedModule,
      startDate: controller.startDate,
      endDate: controller.endDate,
    );
    if (mounted) setState(() => _executionRows = rows);
  }

  Future<void> _pickDateRange(ReportsController controller) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange:
          controller.startDate != null && controller.endDate != null
          ? DateTimeRange(
              start: controller.startDate!,
              end: controller.endDate!,
            )
          : null,
    );
    if (range != null) {
      await controller.loadReports(startDate: range.start, endDate: range.end);
      await Future.wait([
        if (_canViewReportField('contextualDetails')) _loadContextualSections(),
        if (_canViewReportField('auditDetails')) _loadExecutionRows(),
      ]);
    }
  }

  Future<void> _export(Future<void> Function() action) async {
    setState(() => _isExporting = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
              userFacingError(
                error,
                isArabic: context.l10n.isArabic,
                arabicFallback: 'تعذر تصدير التقرير.',
                englishFallback: 'Unable to export the report.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ReportsController>();
    final report = controller.report;

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async {
              await controller.loadReports(
                startDate: controller.startDate,
                endDate: controller.endDate,
              );
              await Future.wait([
                if (_canViewReportField('contextualDetails'))
                  _loadContextualSections(),
                if (_canViewReportField('auditDetails')) _loadExecutionRows(),
              ]);
            },
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                _buildHeader(controller, report),
                const SizedBox(height: 20),
                if (controller.isLoading)
                  const LinearProgressIndicator(color: Colors.black),
                if (controller.errorMessage != null) _buildError(controller),
                const SizedBox(height: 12),
                _buildModuleSelector(),
                const SizedBox(height: 16),
                _buildModuleReport(report),
                const SizedBox(height: 20),
                _reportValue('contextualDetails', _buildContextualDetails()),
                const SizedBox(height: 20),
                _reportValue('auditDetails', _buildExecutionActivity()),
                const SizedBox(height: 20),
                _reportValue('summaryCards', _buildSummary(report)),
                const SizedBox(height: 20),
                _buildFinancialCards(report),
                const SizedBox(height: 20),
                _reportValue('monthlyTrend', _buildMonthlyChart(report)),
                const SizedBox(height: 20),
                _reportValue('summaryCards', _buildOperationalSummary(report)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModuleSelector() {
    const modules = <MapEntry<String, String>>[
      MapEntry('overview', 'نظرة عامة'),
      MapEntry('cars', 'السيارات'),
      MapEntry('products', 'المنتجات'),
      MapEntry('warehouses', 'المخازن'),
      MapEntry('customers', 'العملاء'),
      MapEntry('customer_service', 'خدمة العملاء'),
      MapEntry('opportunities', 'الفرص التجارية'),
      MapEntry('suppliers', 'الموردون'),
      MapEntry('sales', 'المبيعات'),
      MapEntry('purchases', 'المشتريات'),
      MapEntry('payments', 'الدفعات'),
      MapEntry('accounting', 'المحاسبة'),
      MapEntry('inventory', 'الحركات المخزنية'),
      MapEntry('finance', 'المالية'),
      MapEntry('partners', 'الشركاء التجاريون'),
      MapEntry('operations', 'التشغيل'),
    ];
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: modules.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final module = modules[index];
          return ChoiceChip(
            label: AppText(module.value),
            selected: _selectedModule == module.key,
            onSelected: (_) async {
              setState(() => _selectedModule = module.key);
              await _loadExecutionRows();
              await _loadContextualSections();
            },
          );
        },
      ),
    );
  }

  double _contextualRowCount([String? titleContains]) {
    final normalized = titleContains?.trim().toLowerCase();
    return _contextualSections
        .where(
          (section) =>
              normalized == null ||
              normalized.isEmpty ||
              section.title.toLowerCase().contains(normalized),
        )
        .fold<int>(0, (total, section) => total + section.rows.length)
        .toDouble();
  }

  Widget _buildModuleReport(ReportModel report) {
    final data = switch (_selectedModule) {
      'cars' => [
        (
          'إجمالي السيارات',
          report.totalCars.toDouble(),
          Icons.directions_car_outlined,
        ),
        (
          'المتاحة',
          report.availableCars.toDouble(),
          Icons.check_circle_outline,
        ),
        (
          'قيد البيع',
          report.reservedCars.toDouble(),
          Icons.event_available_outlined,
        ),
        ('المباعة', report.soldCars.toDouble(), Icons.sell_outlined),
      ],
      'products' => [
        (
          'إجمالي المنتجات',
          report.totalInventoryItems.toDouble(),
          Icons.inventory_2_outlined,
        ),
        (
          'قيمة المخزون',
          CurrencyTotalsFormatter.format(report.inventoryValueByCurrency),
          Icons.price_check_outlined,
        ),
        ('سجلات التقرير', _contextualRowCount(), Icons.table_rows_outlined),
        (
          'المخازن المرتبطة',
          _contextualRowCount('مخزن'),
          Icons.warehouse_outlined,
        ),
      ],
      'warehouses' => [
        ('إجمالي المخازن', _contextualRowCount(), Icons.warehouse_outlined),
        (
          'إجمالي المنتجات',
          report.totalInventoryItems.toDouble(),
          Icons.inventory_2_outlined,
        ),
        (
          'قيمة المخزون',
          CurrencyTotalsFormatter.format(report.inventoryValueByCurrency),
          Icons.price_check_outlined,
        ),
        (
          'السيارات المتاحة',
          report.availableCars.toDouble(),
          Icons.directions_car_outlined,
        ),
      ],
      'customers' => [
        (
          'إجمالي العملاء',
          report.totalCustomers.toDouble(),
          Icons.people_outline,
        ),
        (
          'ذمم العملاء',
          CurrencyTotalsFormatter.format(report.totalReceivablesByCurrency),
          Icons.receipt_long_outlined,
        ),
        (
          'إجمالي المبيعات',
          CurrencyTotalsFormatter.format(report.totalSalesByCurrency),
          Icons.point_of_sale_outlined,
        ),
        ('سجلات التقرير', _contextualRowCount(), Icons.table_rows_outlined),
      ],
      'suppliers' => [
        (
          'إجمالي الموردين',
          report.totalSuppliers.toDouble(),
          Icons.local_shipping_outlined,
        ),
        (
          'ذمم الموردين',
          CurrencyTotalsFormatter.format(report.totalPurchaseDebtByCurrency),
          Icons.account_balance_wallet_outlined,
        ),
        (
          'إجمالي المشتريات',
          CurrencyTotalsFormatter.format(report.totalPurchasesByCurrency),
          Icons.shopping_cart_outlined,
        ),
        ('سجلات التقرير', _contextualRowCount(), Icons.table_rows_outlined),
      ],
      'payments' => [
        ('إجمالي الدفعات', _contextualRowCount(), Icons.payments_outlined),
        (
          'المحصل من المبيعات',
          CurrencyTotalsFormatter.format(report.totalPaidSalesByCurrency),
          Icons.call_received_outlined,
        ),
        (
          'ذمم العملاء',
          CurrencyTotalsFormatter.format(report.totalReceivablesByCurrency),
          Icons.receipt_long_outlined,
        ),
        (
          'ذمم الموردين',
          CurrencyTotalsFormatter.format(report.totalPurchaseDebtByCurrency),
          Icons.call_made_outlined,
        ),
      ],
      'accounting' => [
        (
          'سجلات الحسابات والقيود',
          _contextualRowCount(),
          Icons.account_balance_outlined,
        ),
        ('رصيد الصندوق USD', report.cashBalanceUsd, Icons.attach_money),
        (
          'رصيد الصندوق IQD',
          report.cashBalanceIqd,
          Icons.account_balance_wallet_outlined,
        ),
        (
          'صافي الربح',
          CurrencyTotalsFormatter.format(report.netProfitByCurrency),
          Icons.trending_up_outlined,
        ),
      ],
      'sales' => [
        (
          'إجمالي المبيعات',
          CurrencyTotalsFormatter.format(report.totalSalesByCurrency),
          Icons.point_of_sale_outlined,
        ),
        (
          'المحصل',
          CurrencyTotalsFormatter.format(report.totalPaidSalesByCurrency),
          Icons.payments_outlined,
        ),
        (
          'ذمم العملاء',
          CurrencyTotalsFormatter.format(report.totalReceivablesByCurrency),
          Icons.receipt_long_outlined,
        ),
        (
          'صافي الربح',
          CurrencyTotalsFormatter.format(report.netProfitByCurrency),
          Icons.trending_up,
        ),
      ],
      'purchases' => [
        (
          'إجمالي المشتريات',
          CurrencyTotalsFormatter.format(report.totalPurchasesByCurrency),
          Icons.shopping_cart_outlined,
        ),
        (
          'ذمم الموردين',
          CurrencyTotalsFormatter.format(report.totalPurchaseDebtByCurrency),
          Icons.account_balance_wallet_outlined,
        ),
        (
          'قيمة المخزون',
          CurrencyTotalsFormatter.format(report.inventoryValueByCurrency),
          Icons.inventory_2_outlined,
        ),
        (
          'المصاريف',
          CurrencyTotalsFormatter.format(report.totalExpensesByCurrency),
          Icons.money_off_outlined,
        ),
      ],
      'inventory' => [
        (
          'عدد قطع المخزون',
          report.totalInventoryItems.toDouble(),
          Icons.inventory_2_outlined,
        ),
        (
          'قيمة المخزون',
          CurrencyTotalsFormatter.format(report.inventoryValueByCurrency),
          Icons.price_check_outlined,
        ),
        (
          'إجمالي المشتريات',
          CurrencyTotalsFormatter.format(report.totalPurchasesByCurrency),
          Icons.download_outlined,
        ),
        (
          'إجمالي المبيعات',
          CurrencyTotalsFormatter.format(report.totalSalesByCurrency),
          Icons.upload_outlined,
        ),
      ],
      'finance' => [
        ('رصيد الصندوق USD', report.cashBalanceUsd, Icons.attach_money),
        (
          'رصيد الصندوق IQD',
          report.cashBalanceIqd,
          Icons.account_balance_wallet_outlined,
        ),
        (
          'الذمم المدينة',
          CurrencyTotalsFormatter.format(report.totalReceivablesByCurrency),
          Icons.call_received,
        ),
        (
          'الذمم الدائنة',
          CurrencyTotalsFormatter.format(report.totalPurchaseDebtByCurrency),
          Icons.call_made,
        ),
      ],
      'partners' => [
        ('العملاء', report.totalCustomers.toDouble(), Icons.people_outline),
        (
          'الموردون',
          report.totalSuppliers.toDouble(),
          Icons.local_shipping_outlined,
        ),
        (
          'الحجوزات النشطة',
          report.activeReservations.toDouble(),
          Icons.event_available_outlined,
        ),
        (
          'الأقساط المتأخرة',
          report.overdueInstallments.toDouble(),
          Icons.warning_amber_outlined,
        ),
      ],
      'operations' => [
        (
          'الحجوزات النشطة',
          report.activeReservations.toDouble(),
          Icons.event_available_outlined,
        ),
        (
          'الأقساط المتأخرة',
          report.overdueInstallments.toDouble(),
          Icons.warning_amber_outlined,
        ),
        (
          'السيارات المتاحة',
          report.availableCars.toDouble(),
          Icons.directions_car_outlined,
        ),
        (
          'قطع المخزون',
          report.totalInventoryItems.toDouble(),
          Icons.inventory_2_outlined,
        ),
      ],
      _ => [
        (
          'إجمالي المبيعات',
          CurrencyTotalsFormatter.format(report.totalSalesByCurrency),
          Icons.sell_outlined,
        ),
        (
          'إجمالي المشتريات',
          CurrencyTotalsFormatter.format(report.totalPurchasesByCurrency),
          Icons.shopping_cart_outlined,
        ),
        (
          'المصاريف',
          CurrencyTotalsFormatter.format(report.totalExpensesByCurrency),
          Icons.money_off_outlined,
        ),
        (
          'صافي الربح',
          CurrencyTotalsFormatter.format(report.netProfitByCurrency),
          Icons.trending_up,
        ),
      ],
    };
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 4
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: data
              .map((item) => _metric(width, item.$1, item.$2, item.$3))
              .toList(),
        );
      },
    );
  }

  List<({String route, String label, IconData icon})> _relatedModules(
    ContextualReportSection section,
  ) {
    final key = '$_selectedModule ${section.key}'.toLowerCase();
    final destinations = <({String route, String label, IconData icon})>[];

    void add(String route, String ar, String en, IconData icon) {
      if (destinations.any((item) => item.route == route)) return;
      destinations.add((
        route: route,
        label: context.l10n.isArabic ? ar : en,
        icon: icon,
      ));
    }

    if (key.contains('opportun') || key.contains('customer_service')) {
      add(
        AppRouteNames.customerService,
        'الفرص التجارية',
        'Opportunities',
        Icons.support_agent_outlined,
      );
      add(
        AppRouteNames.sales,
        'المبيعات',
        'Sales',
        Icons.point_of_sale_rounded,
      );
    }
    if (key.contains('sale')) {
      add(
        AppRouteNames.sales,
        'المبيعات',
        'Sales',
        Icons.point_of_sale_rounded,
      );
      add(
        AppRouteNames.inventory,
        'المخازن',
        'Inventory',
        Icons.warehouse_outlined,
      );
      add(
        AppRouteNames.accounting,
        'الحسابات',
        'Accounting',
        Icons.account_balance_outlined,
      );
      add(
        AppRouteNames.products,
        'السيارات والمواد',
        'Vehicles & products',
        Icons.directions_car_outlined,
      );
    }
    if (key.contains('purchase') || key.contains('supplier')) {
      add(
        AppRouteNames.purchases,
        'المشتريات',
        'Purchases',
        Icons.shopping_cart_checkout_rounded,
      );
      add(
        AppRouteNames.inventory,
        'المخازن',
        'Inventory',
        Icons.warehouse_outlined,
      );
      add(
        AppRouteNames.accounting,
        'الحسابات',
        'Accounting',
        Icons.account_balance_outlined,
      );
      add(
        AppRouteNames.products,
        'السيارات والمواد',
        'Vehicles & products',
        Icons.directions_car_outlined,
      );
    }
    if (key.contains('warehouse') ||
        key.contains('inventory') ||
        key.contains('product') ||
        key.contains('transfer')) {
      add(
        AppRouteNames.inventory,
        'المخازن',
        'Inventory',
        Icons.warehouse_outlined,
      );
      add(
        AppRouteNames.products,
        'السيارات والمواد',
        'Vehicles & products',
        Icons.inventory_2_outlined,
      );
      add(
        AppRouteNames.sales,
        'المبيعات',
        'Sales',
        Icons.point_of_sale_rounded,
      );
      add(
        AppRouteNames.purchases,
        'المشتريات',
        'Purchases',
        Icons.shopping_cart_checkout_rounded,
      );
    }
    if (key.contains('car') ||
        key.contains('vehicle') ||
        key.contains('fleet')) {
      add(
        AppRouteNames.products,
        'السيارات',
        'Vehicles',
        Icons.directions_car_outlined,
      );
      add(
        AppRouteNames.sales,
        'المبيعات',
        'Sales',
        Icons.point_of_sale_rounded,
      );
      add(
        AppRouteNames.purchases,
        'المشتريات',
        'Purchases',
        Icons.shopping_cart_checkout_rounded,
      );
    }
    if (key.contains('journal') ||
        key.contains('account') ||
        key.contains('payment') ||
        key.contains('cash')) {
      add(
        AppRouteNames.accounting,
        'الحسابات والصندوق',
        'Accounting & cashbox',
        Icons.account_balance_wallet_outlined,
      );
      add(
        AppRouteNames.sales,
        'المبيعات',
        'Sales',
        Icons.point_of_sale_rounded,
      );
      add(
        AppRouteNames.purchases,
        'المشتريات',
        'Purchases',
        Icons.shopping_cart_checkout_rounded,
      );
      add(
        AppRouteNames.maintenance,
        'الصيانة',
        'Maintenance',
        Icons.build_circle_outlined,
      );
    }
    if (key.contains('maintenance')) {
      add(
        AppRouteNames.maintenance,
        'الصيانة',
        'Maintenance',
        Icons.build_circle_outlined,
      );
      add(
        AppRouteNames.inventory,
        'المخازن',
        'Inventory',
        Icons.warehouse_outlined,
      );
      add(
        AppRouteNames.accounting,
        'الحسابات',
        'Accounting',
        Icons.account_balance_outlined,
      );
    }
    return destinations;
  }

  double _contextCellWidth(String value) {
    final length = value.runes.length;
    if (length >= 80) return 280;
    if (length >= 40) return 230;
    if (length >= 18) return 180;
    return 132;
  }

  Widget _relatedModuleLinks(ContextualReportSection section) {
    final destinations = _relatedModules(section);
    if (destinations.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 10),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          AppText(
            context.l10n.isArabic ? 'المودلات المرتبطة:' : 'Related modules:',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          ...destinations.map(
            (item) => ActionChip(
              avatar: Icon(item.icon, size: 16),
              label: AppText(item.label, style: const TextStyle(fontSize: 11)),
              onPressed: () => AppModuleNavigation.open(context, item.route),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContextualDetails() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.table_view_outlined),
                const SizedBox(width: 8),
                AppText(
                  'تفاصيل بيانات المودل',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _isLoadingContextual
                      ? null
                      : _loadContextualSections,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (_isLoadingContextual) const LinearProgressIndicator(),
            if (_contextualError != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: AppText(
                  'تعذر تحميل بعض بيانات التقرير: $_contextualError',
                ),
              ),
            if (!_isLoadingContextual && _contextualSections.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: AppText(
                  'لا توجد جداول أو بيانات مرتبطة بهذا المودل ضمن الفترة المحددة.',
                ),
              ),
            ..._contextualSections.map(
              (section) => ExpansionTile(
                title: AppText(section.title),
                subtitle: AppText('${section.rows.length} سجل'),
                children: [
                  _relatedModuleLinks(section),
                  if (section.rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: AppText('لا توجد بيانات.'),
                    )
                  else
                    SizedBox(
                      height: 360,
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: DataTable(
                              headingRowHeight: 48,
                              dataRowMinHeight: 48,
                              dataRowMaxHeight: 112,
                              columnSpacing: 24,
                              horizontalMargin: 14,
                              dividerThickness: .6,
                              columns: section.columns
                                  .map(
                                    (column) =>
                                        DataColumn(label: AppText(column)),
                                  )
                                  .toList(),
                              rows: section.rows
                                  .take(100)
                                  .map(
                                    (row) => DataRow(
                                      cells: row
                                          .map(
                                            (value) => DataCell(
                                              ConstrainedBox(
                                                constraints: BoxConstraints(
                                                  minWidth: 112,
                                                  maxWidth: _contextCellWidth(
                                                    value,
                                                  ),
                                                ),
                                                child: AppSelectableText(
                                                  value,
                                                  maxLines: 6,
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    height: 1.35,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (section.rows.length > 100)
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: AppText(
                        'المعاينة تعرض أول 100 سجل، بينما PDF وExcel يتضمنان جميع السجلات.',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutionActivity() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_user_outlined),
                const SizedBox(width: 8),
                AppText(
                  'سجل منفذي الإدخال',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _loadExecutionRows,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_executionRows.isEmpty)
              const AppText('لا توجد عمليات مسجلة ضمن هذا المودل.'),
            if (_executionRows.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: AppText('المستخدم')),
                    DataColumn(label: AppText('العملية')),
                    DataColumn(label: AppText('نوع السجل')),
                    DataColumn(label: AppText('التاريخ والوقت')),
                  ],
                  rows: _executionRows
                      .take(50)
                      .map(
                        (row) => DataRow(
                          cells: [
                            DataCell(AppText(row.userName)),
                            DataCell(AppText(row.action)),
                            DataCell(AppText(row.entityType)),
                            DataCell(
                              AppText(
                                DateFormat(
                                  'yyyy/MM/dd HH:mm',
                                ).format(row.createdAt.toLocal()),
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ReportsController controller, ReportModel report) {
    final period = _periodLabel(controller);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(18),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final buttons = Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _reportField(
                'dateRange',
                OutlinedButton.icon(
                  onPressed: () => _pickDateRange(controller),
                  icon: const Icon(Icons.date_range),
                  label: AppText(period),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
                writePermission: 'reports.view',
              ),
              if (controller.startDate != null)
                _reportField(
                  'dateRange',
                  IconButton(
                    tooltip: AppTranslation.translate('إلغاء الفترة'),
                    onPressed: controller.clearFilter,
                    color: Colors.white,
                    icon: const Icon(Icons.filter_alt_off),
                  ),
                  writePermission: 'reports.view',
                ),
              _reportField(
                'exportPdf',
                OutlinedButton.icon(
                  onPressed: _showExportSettings,
                  icon: const Icon(Icons.tune),
                  label: const AppText('تخصيص'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
                writePermission: 'reports.export',
              ),
              _reportField(
                'exportPdf',
                PopupMenuButton<String>(
                  enabled: !_isExporting,
                  tooltip: AppTranslation.translate('PDF والطباعة'),
                  onSelected: (value) async {
                    final periodValue = _periodLabel(controller);
                    if (value == 'preview') {
                      await _export(
                        () => _exportService.previewPdf(
                          report,
                          module: _selectedModule,
                          executionRows: _executionRows,
                          options: _exportOptions,
                          period: periodValue,
                          sections: _contextualSections,
                        ),
                      );
                    } else {
                      await _export(
                        () => _exportService.downloadPdf(
                          report,
                          module: _selectedModule,
                          executionRows: _executionRows,
                          options: _exportOptions,
                          period: periodValue,
                          sections: _contextualSections,
                        ),
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'preview',
                      child: ListTile(
                        leading: Icon(Icons.print_outlined),
                        title: AppText('معاينة وطباعة PDF'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'download',
                      child: ListTile(
                        leading: Icon(Icons.download_outlined),
                        title: AppText('تنزيل PDF'),
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.picture_as_pdf_outlined,
                          color: Colors.black,
                        ),
                        SizedBox(width: 8),
                        AppText(
                          'PDF',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, color: Colors.black),
                      ],
                    ),
                  ),
                ),
                writePermission: 'reports.export',
              ),
              _reportField(
                'exportExcel',
                FilledButton.icon(
                  onPressed: _isExporting
                      ? null
                      : () => _export(
                          () => _exportService.exportExcel(
                            report,
                            module: _selectedModule,
                            executionRows: _executionRows,
                            options: _exportOptions,
                            period: _periodLabel(controller),
                            sections: _contextualSections,
                          ),
                        ),
                  icon: const Icon(Icons.table_view_outlined),
                  label: const AppText('Excel'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                  ),
                ),
                writePermission: 'reports.export',
              ),
              _reportField(
                'exportExcel',
                OutlinedButton.icon(
                  onPressed: _isExporting
                      ? null
                      : () => _export(
                          () => _exportService.exportCsv(
                            report,
                            module: _selectedModule,
                            executionRows: _executionRows,
                            options: _exportOptions,
                            period: _periodLabel(controller),
                            sections: _contextualSections,
                          ),
                        ),
                  icon: const Icon(Icons.description_outlined),
                  label: const AppText('CSV'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                ),
                writePermission: 'reports.export',
              ),
            ],
          );

          final title = const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                'التقارير التنفيذية',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 6),
              AppText(
                'مؤشرات المبيعات والمشتريات والسيولة والمخزون.',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          );

          final titleWithBack = Row(
            children: [
              const AppBackButton(color: Colors.white),
              const SizedBox(width: 8),
              const Icon(
                Icons.analytics_outlined,
                color: Colors.white,
                size: 42,
              ),
              const SizedBox(width: 16),
              Expanded(child: title),
            ],
          );

          if (constraints.maxWidth > 850) {
            return Row(
              children: [
                Expanded(child: titleWithBack),
                buttons,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [titleWithBack, const SizedBox(height: 18), buttons],
          );
        },
      ),
    );
  }

  Widget _buildError(ReportsController controller) => Card(
    color: Colors.red.shade50,
    child: ListTile(
      leading: const Icon(Icons.error_outline, color: Colors.red),
      title: AppText(controller.errorMessage!),
      trailing: IconButton(
        onPressed: controller.loadReports,
        icon: const Icon(Icons.refresh),
      ),
    ),
  );

  Widget _buildSummary(ReportModel report) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 1000
            ? (constraints.maxWidth - 48) / 4
            : constraints.maxWidth >= 600
            ? (constraints.maxWidth - 16) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _metric(
              width,
              'إجمالي المبيعات',
              CurrencyTotalsFormatter.format(report.totalSalesByCurrency),
              Icons.sell_outlined,
            ),
            _metric(
              width,
              'إجمالي المشتريات',
              CurrencyTotalsFormatter.format(report.totalPurchasesByCurrency),
              Icons.shopping_cart_outlined,
            ),
            _metric(
              width,
              'المصاريف',
              CurrencyTotalsFormatter.format(report.totalExpensesByCurrency),
              Icons.money_off_outlined,
            ),
            _reportValue(
              'netProfit',
              _metric(
                width,
                'صافي الربح',
                CurrencyTotalsFormatter.format(report.netProfitByCurrency),
                Icons.trending_up,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFinancialCards(ReportModel report) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 900
            ? (constraints.maxWidth - 32) / 3
            : constraints.maxWidth;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _reportValue(
              'receivablesPayables',
              _infoPanel(width, 'الذمم والتحصيل', [
                _row(
                  'المبيعات المحصلة',
                  CurrencyTotalsFormatter.format(
                    report.totalPaidSalesByCurrency,
                  ),
                ),
                _row(
                  'ذمم العملاء',
                  CurrencyTotalsFormatter.format(
                    report.totalReceivablesByCurrency,
                  ),
                ),
                _row(
                  'ذمم الموردين',
                  CurrencyTotalsFormatter.format(
                    report.totalPurchaseDebtByCurrency,
                  ),
                ),
              ]),
            ),
            _reportValue(
              'cashBalances',
              _infoPanel(width, 'السيولة', [
                _row('رصيد الصندوق USD', report.cashBalanceUsd),
                _row('رصيد الصندوق IQD', report.cashBalanceIqd),
              ]),
            ),
            _reportValue(
              'inventoryValue',
              _infoPanel(width, 'المخزون', [
                _row(
                  'قيمة المخزون',
                  CurrencyTotalsFormatter.format(
                    report.inventoryValueByCurrency,
                  ),
                ),
              ]),
            ),
            _reportValue(
              'summaryCards',
              _infoPanel(width, 'تنبيهات التشغيل', [
                _textRow(
                  'الحجوزات النشطة',
                  report.activeReservations.toString(),
                ),
                _textRow(
                  'الأقساط المتأخرة',
                  report.overdueInstallments.toString(),
                ),
                _textRow('قطع المخزون', report.totalInventoryItems.toString()),
              ]),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMonthlyChart(ReportModel report) {
    final currencies = <String>{
      ...report.totalSalesByCurrency.entries
          .where((e) => e.value.abs() > 0.0000001)
          .map((e) => e.key),
      ...report.totalPurchasesByCurrency.entries
          .where((e) => e.value.abs() > 0.0000001)
          .map((e) => e.key),
      ...report.totalExpensesByCurrency.entries
          .where((e) => e.value.abs() > 0.0000001)
          .map((e) => e.key),
    };
    if (currencies.length > 1) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListTile(
            leading: const Icon(Icons.currency_exchange_outlined),
            title: AppText(
              context.l10n.isArabic
                  ? 'الاتجاه المالي حسب العملة'
                  : 'Financial trend by currency',
            ),
            subtitle: AppText(
              context.l10n.isArabic
                  ? 'تم إخفاء الرسم المالي الموحّد لأن الفترة تحتوي أكثر من عملة، لتجنب جمع USD وIQD في محور واحد.'
                  : 'The combined financial chart is hidden because the period contains multiple currencies, avoiding a mixed USD/IQD axis.',
            ),
          ),
        ),
      );
    }
    final maxValue = report.monthlyPoints.fold<double>(1, (max, point) {
      final pointMax = [
        point.sales,
        point.purchases,
        point.expenses,
      ].reduce((a, b) => a > b ? a : b);
      return pointMax > max ? pointMax : max;
    });

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppText(
              'أداء آخر ستة أشهر',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const AppText(
              'الأسود: المبيعات، الرمادي الداكن: المشتريات، الرمادي الفاتح: المصاريف',
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 250,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: report.monthlyPoints.map((point) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _bar(point.sales / maxValue, Colors.black),
                                _bar(
                                  point.purchases / maxValue,
                                  Colors.grey.shade700,
                                ),
                                _bar(
                                  point.expenses / maxValue,
                                  Colors.grey.shade300,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          AppText(
                            point.label,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(double ratio, Color color) => Container(
    width: 16,
    height: 190 * ratio.clamp(0.02, 1),
    margin: const EdgeInsets.symmetric(horizontal: 2),
    decoration: BoxDecoration(
      color: color,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
    ),
  );

  Widget _buildOperationalSummary(ReportModel report) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppText(
            'حالة أسطول السيارات',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 16,
            children: [
              _status('الإجمالي', report.totalCars, Icons.directions_car),
              _status(
                'المتاحة',
                report.availableCars,
                Icons.check_circle_outline,
              ),
              _status(
                'قيد البيع',
                report.reservedCars,
                Icons.event_available_outlined,
              ),
              _status('المباعة', report.soldCars, Icons.task_alt),
              _status('العملاء', report.totalCustomers, Icons.people_outline),
              _status(
                'الموردون',
                report.totalSuppliers,
                Icons.local_shipping_outlined,
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _metric(double width, String title, Object value, IconData icon) =>
      SizedBox(
        width: width,
        child: Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  child: Icon(icon),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        title,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                      const SizedBox(height: 5),
                      AppText(
                        _displayValue(value),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
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

  Widget _infoPanel(double width, String title, List<Widget> rows) => SizedBox(
    width: width,
    child: Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppText(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),
            ...rows,
          ],
        ),
      ),
    ),
  );

  Widget _row(String label, Object value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(child: AppText(label)),
        AppText(
          _displayValue(value),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );

  Widget _textRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(child: AppText(label)),
        AppText(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    ),
  );

  Widget _status(String title, int value, IconData icon) => Container(
    width: 150,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(title),
              AppText(
                '$value',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  String _displayValue(Object value) =>
      value is num ? _money(value.toDouble()) : value.toString();

  String _money(double value) => NumberFormat('#,##0.00').format(value);
}
