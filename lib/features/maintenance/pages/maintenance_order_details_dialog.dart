import 'dart:async';

import 'package:flutter/material.dart';

import 'package:quality_line_erp/app/route_names.dart';
import 'package:quality_line_erp/core/documents/document_nomenclature.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/printing/maintenance_document_pdf_service.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:quality_line_erp/core/widgets/app_module_action_icon.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
import 'package:quality_line_erp/core/widgets/app_top_navigation.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_phase3_components.dart';
import 'package:quality_line_erp/design_system/kaj_relationship_stage5_components.dart';
import 'package:quality_line_erp/features/maintenance/data/maintenance_repository.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_cost_reconciliation.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

class MaintenanceOrderDetailsDialog extends StatefulWidget {
  const MaintenanceOrderDetailsDialog({
    super.key,
    required this.order,
    this.onPrint,
    this.onEdit,
    this.onDelete,
    this.onCancel,
    this.onPayment,
    this.initialLines,
  });

  final MaintenanceOrderModel order;
  final Future<void> Function()? onPrint;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onDelete;
  final Future<void> Function()? onCancel;
  final Future<void> Function()? onPayment;
  final List<MaintenanceLineModel>? initialLines;

  @override
  State<MaintenanceOrderDetailsDialog> createState() =>
      _MaintenanceOrderDetailsDialogState();
}

class _MaintenanceOrderDetailsDialogState
    extends State<MaintenanceOrderDetailsDialog> {
  Widget _fieldView(String field, Widget child) => FieldPermissionVisibility(
    resource: 'maintenance',
    field: field,
    viewPermission: 'maintenance.view',
    child: child,
  );

  Widget _fieldAction(String field, Widget child) => FieldPermissionControl(
    resource: 'maintenance',
    field: field,
    viewPermission: 'maintenance.view',
    writePermission: 'maintenance.update',
    child: child,
  );

  final MaintenanceRepository _repository = MaintenanceRepository();
  late MaintenanceOrderModel _order;
  List<MaintenanceLineModel> _lines = const <MaintenanceLineModel>[];
  MaintenanceCostReconciliation? _costs;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  bool get _arabic => context.l10n.isArabic;
  String _bi(String arabic, String english) => _arabic ? arabic : english;

  static const List<String> _stages = <String>[
    'order_draft',
    'order_approved',
    'stock_issue_draft',
    'stock_issue_approved',
    'invoice_draft',
    'invoice_approved',
    'paid',
    'completed',
  ];

  int get _stageIndex {
    final index = _stages.indexOf(_order.workflowStage);
    return index < 0 ? 0 : index;
  }

  Map<String, Object?>? _reconciliationLine(String lineId) {
    for (final line in _costs?.lines ?? const <Map<String, Object?>>[]) {
      if (line['lineId']?.toString() == lineId) return line;
    }
    return null;
  }

  num _lineQuantity(String lineId, String field, num fallback) =>
      (_reconciliationLine(lineId)?[field] as num?) ?? fallback;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    final initialLines = widget.initialLines;
    if (initialLines != null) {
      _lines = List<MaintenanceLineModel>.unmodifiable(initialLines);
      _loading = false;
      return;
    }
    // Normal entry points load the authoritative bounded reconciliation RPC.
    // Callers that already resolved core lines (for example the historical
    // vehicle service card) remain fully renderable without another backend
    // round trip; optional analytics must never blank persisted details.
    unawaited(_loadDetails());
  }

  Future<void> _loadDetails() async {
    try {
      final snapshot = await _repository.getOrderSnapshot(_order.id);
      if (!mounted) return;
      setState(() {
        _order = snapshot.order;
        _lines = snapshot.lines;
        _costs = snapshot.reconciliation;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userFacingError(
          error,
          isArabic: _arabic,
          arabicFallback: 'تعذر تحميل لقطة أمر الصيانة.',
          englishFallback: 'Unable to load the maintenance order snapshot.',
        );
      });
    }
  }

  Future<void> _exportPdf() async {
    if (_busy || _loading) return;
    setState(() => _busy = true);
    try {
      var costs = _costs;
      var exportLines = _lines;
      if (costs == null || exportLines.isEmpty) {
        final snapshot = await _repository.getOrderSnapshot(_order.id);
        costs = snapshot.reconciliation;
        exportLines = snapshot.lines;
        if (mounted) {
          setState(() {
            _order = snapshot.order;
            _lines = snapshot.lines;
            _costs = snapshot.reconciliation;
          });
        }
      }
      final externalPrint = widget.onPrint;
      if (externalPrint != null) {
        await externalPrint();
      } else {
        await const MaintenanceDocumentPdfService().print(
          order: _order,
          lines: exportLines,
          issueEvents: costs.issueEvents,
          authoritativeIssuedQuantity: costs.lines
              .where((line) => line['lineType']?.toString() != 'service')
              .fold<double>(
                0,
                (total, line) =>
                    total + ((line['issuedQuantity'] as num?)?.toDouble() ?? 0),
              ),
          arabic: _arabic,
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFacingError(
              error,
              isArabic: _arabic,
              arabicFallback: 'تعذر تصدير ملف PDF.',
              englishFallback: 'Unable to export the PDF file.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _issueMaterial(Map<String, Object?> line) async {
    if (_busy) return;
    final partId = line['lineId']?.toString() ?? '';
    final remaining = (line['remainingQuantity'] as num?)?.toDouble() ?? 0;
    if (partId.isEmpty || remaining <= 0) return;
    setState(() => _busy = true);
    try {
      final options = await _repository.getIssueWarehouseOptions(partId);
      if (!mounted) return;
      if (options.isEmpty)
        throw StateError('maintenance_issue_no_available_warehouse');
      var warehouseId = options.first['warehouse_id']?.toString() ?? '';
      final quantity = TextEditingController(text: remaining.toString());
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: AppText(
              _bi('صرف مواد الصيانة', 'Issue maintenance material'),
            ),
            content: SizedBox(
              width: 430,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: warehouseId,
                    decoration: InputDecoration(
                      labelText: _bi('المخزن', 'Warehouse'),
                    ),
                    items: options
                        .map(
                          (row) => DropdownMenuItem<String>(
                            value: row['warehouse_id']?.toString(),
                            child: AppText(
                              '${row['warehouse_name']} (${row['available_quantity']})',
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) =>
                        setDialogState(() => warehouseId = value ?? ''),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _bi(
                        'الكمية (المتبقي $remaining)',
                        'Quantity (remaining $remaining)',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: AppText(_bi('إلغاء', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: AppText(_bi('تنفيذ الصرف', 'Execute issue')),
              ),
            ],
          ),
        ),
      );
      if (accepted != true) return;
      final amount = double.tryParse(quantity.text.trim()) ?? 0;
      await _repository.issueMaterial(
        orderId: _order.id,
        partId: partId,
        warehouseId: warehouseId,
        quantity: amount,
      );
      await _loadDetails();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
              _bi(
                'تم صرف الكمية وتحديث FIFO.',
                'Quantity issued and FIFO updated.',
              ),
            ),
          ),
        );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Theme.of(context).colorScheme.error,
            content: AppText(
              userFacingError(
                error,
                isArabic: _arabic,
                arabicFallback: 'تعذر صرف مادة الصيانة.',
                englishFallback: 'Unable to issue maintenance material.',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reverseIssue(Map<String, Object?> event) async {
    final issueId = event['issueId']?.toString() ?? '';
    if (_busy || issueId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: AppText(_bi('عكس عملية الصرف', 'Reverse material issue')),
        content: AppText(
          _bi(
            'ستُعاد الكمية إلى المخزن نفسه مع عكس FIFO لهذه العملية فقط.',
            'Stock returns to the same warehouse and only this issue FIFO is reversed.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: AppText(_bi('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: AppText(_bi('عكس', 'Reverse')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _repository.reverseMaterialIssue(
        issueId,
        reason: 'Maintenance issue reversal',
      );
      await _loadDetails();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run({
    required String componentType,
    required String action,
    required String successAr,
    required String successEn,
  }) async {
    if (_busy) return;
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: AppText(_bi('تأكيد حذف الوحدة', 'Confirm component deletion')),
          content: AppText(
            _bi(
              componentType == 'invoice'
                  ? 'ستُعكس الفاتورة وارتباطاتها التشغيلية فقط. تبقى الدفعات كرصيد غير مخصص للعميل، وتُحتسب تلقائيًا عند تصديق فاتورة صيانة أو بيع لاحقة للعميل نفسه وبالعملة نفسها.'
                  : 'ستُعكس هذه الوحدة فقط وتُعاد حالة أمر الصيانة إلى المرحلة السابقة.',
              componentType == 'invoice'
                  ? 'Only the invoice and its operational links will be reversed. Payments remain as unapplied customer credit and are automatically considered for a later approved maintenance or sales invoice in the same currency.'
                  : 'Only this component will be reversed and the maintenance order will return to its previous stage.',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: AppText(_bi('إلغاء', 'Cancel')),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD74747),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.delete_forever_outlined),
              label: AppText(_bi('حذف وعكس', 'Delete and reverse')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      await _repository.manageOrderComponent(
        orderId: _order.id,
        componentType: componentType,
        action: action,
        reason: 'Maintenance order internal component action',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: AppText(_bi(successAr, successEn))));
      AppWorkspaceWindowScope.closeCurrent(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: AppText(
            userFacingError(
              error,
              isArabic: _arabic,
              arabicFallback:
                  'تعذر تنفيذ العملية. احذف المرحلة اللاحقة أولًا أو حدّث أمر الصيانة ثم أعد المحاولة.',
              englishFallback:
                  'Unable to complete the action. Remove the later stage first or refresh the maintenance order and try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canAdvance =>
      !_order.isCancelled &&
      const <String>{
        'order_draft',
        'order_approved',
        'stock_issue_draft',
        'stock_issue_approved',
        'invoice_draft',
      }.contains(_order.workflowStage);

  String get _nextActionLabel => switch (_order.workflowStage) {
    'order_draft' => _bi('تصديق أمر الصيانة', 'Approve maintenance order'),
    'order_approved' => _bi('إنشاء مسودة التجهيز', 'Create stock issue draft'),
    'stock_issue_draft' => _bi('تصديق التجهيز المخزني', 'Approve stock issue'),
    'stock_issue_approved' =>
      _order.pricingType == 'paid'
          ? _bi('إنشاء مسودة الفاتورة', 'Create invoice draft')
          : _bi('إكمال الصيانة', 'Complete maintenance'),
    'invoice_draft' => _bi(
      'تصديق فاتورة الصيانة',
      'Approve maintenance invoice',
    ),
    _ => '',
  };

  IconData get _nextActionIcon => switch (_order.workflowStage) {
    'order_draft' => Icons.verified_outlined,
    'order_approved' => Icons.inventory_2_outlined,
    'stock_issue_draft' => Icons.fact_check_outlined,
    'stock_issue_approved' =>
      _order.pricingType == 'paid'
          ? Icons.receipt_long_outlined
          : Icons.task_alt_rounded,
    'invoice_draft' => Icons.verified_user_outlined,
    _ => Icons.arrow_forward_rounded,
  };

  Future<void> _advanceWorkflow() async {
    if (_busy || !_canAdvance) return;
    setState(() => _busy = true);
    try {
      await _repository.advanceWorkflow(_order.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            _bi(
              'تم تنفيذ المرحلة وتحديث أمر الصيانة.',
              'The stage completed and the maintenance order was refreshed.',
            ),
          ),
        ),
      );
      AppWorkspaceWindowScope.closeCurrent(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: AppText(
            userFacingError(
              error,
              isArabic: _arabic,
              arabicFallback:
                  'تعذر تنفيذ مرحلة الصيانة. تحقق من المخزون والفاتورة ثم أعد المحاولة.',
              englishFallback:
                  'Unable to complete the maintenance stage. Verify stock and invoice data, then try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: AppText(
          '${DocumentNomenclature.maintenanceOrder(arabic: _arabic)} ${order.orderNumber}',
        ),
        actions: <Widget>[
          if (_canAdvance)
            AppModuleActionIcon(
              tooltip: _nextActionLabel,
              icon: _nextActionIcon,
              busy: _busy,
              onPressed: _busy ? null : _advanceWorkflow,
            ),
          if (widget.onPayment != null)
            AppModuleActionIcon(
              tooltip: _bi('تسجيل دفعة الصيانة', 'Record maintenance payment'),
              icon: Icons.payments_outlined,
              busy: _busy,
              onPressed: _busy
                  ? null
                  : () async {
                      await widget.onPayment?.call();
                      await _loadDetails();
                    },
            ),
          if (widget.onEdit != null)
            AppModuleActionIcon(
              tooltip: _bi('تعديل الأمر', 'Edit order'),
              icon: Icons.edit_outlined,
              onPressed: _busy
                  ? null
                  : () async {
                      await widget.onEdit?.call();
                      await _loadDetails();
                    },
            ),
          if (widget.onDelete != null)
            AppModuleActionIcon(
              tooltip: _order.isCancelled
                  ? _bi('حذف الأمر الملغى', 'Delete cancelled order')
                  : _bi('حذف المسودة', 'Delete draft'),
              icon: Icons.delete_forever_outlined,
              destructive: true,
              onPressed: _busy
                  ? null
                  : () async {
                      await widget.onDelete?.call();
                      if (context.mounted) Navigator.pop(context, true);
                    },
            ),
          if (widget.onCancel != null)
            AppModuleActionIcon(
              tooltip: _bi(
                'إلغاء الأمر وعكس الآثار المرتبطة',
                'Cancel order and reverse downstream effects',
              ),
              icon: Icons.undo_rounded,
              destructive: true,
              busy: _busy,
              onPressed: _busy
                  ? null
                  : () async {
                      await widget.onCancel?.call();
                      await _loadDetails();
                    },
            ),
          AppModuleActionIcon(
            tooltip: _bi('تصدير وطباعة PDF', 'Export and print PDF'),
            icon: Icons.picture_as_pdf_outlined,
            busy: _busy,
            onPressed: _busy || _loading ? null : _exportPdf,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? KajRelationshipState.loading(
              label: context.relationshipText(
                'جارٍ تحميل البيانات...',
                'Loading data...',
              ),
            )
          : _error != null
          ? Center(child: AppSelectableText(_error ?? ''))
          : ListView(
              padding: const EdgeInsets.all(18),
              children: <Widget>[
                KajRelationshipHero(
                  eyebrow: _bi(
                    'ملف صيانة متكامل',
                    'INTEGRATED SERVICE DOSSIER',
                  ),
                  title: '${order.orderNumber} — ${order.carName}',
                  subtitle: _bi(
                    'نظرة موحدة على العميل والمركبة والمواد والكلفة والفاتورة والتحصيل وتسلسل التنفيذ.',
                    'A unified view of customer, vehicle, materials, cost, invoice, collection, and execution history.',
                  ),
                  icon: Icons.fact_check_outlined,
                  trailing: KajStatusBadge(
                    label: order.workflowLabel(_arabic),
                    color: order.isCancelled
                        ? KajDesignTokens.danger
                        : KajDesignTokens.success,
                    icon: order.isCancelled
                        ? Icons.cancel_outlined
                        : Icons.verified_outlined,
                  ),
                ),
                const SizedBox(height: 12),
                KajWorkflowStepper(
                  currentIndex: _stageIndex,
                  compact: MediaQuery.sizeOf(context).width < 1100,
                  steps: <String>[
                    _bi('المسودة', 'Draft'),
                    _bi('التصديق', 'Approval'),
                    _bi('مسودة التجهيز', 'Stock draft'),
                    _bi('تصديق التجهيز', 'Stock approval'),
                    _bi('مسودة الفاتورة', 'Invoice draft'),
                    _bi('تصديق الفاتورة', 'Invoice approval'),
                    _bi('التحصيل', 'Paid'),
                    _bi('مكتمل', 'Completed'),
                  ],
                ),
                const SizedBox(height: 16),
                _summary(order),
                const SizedBox(height: 16),
                _costReconciliation(order),
                const SizedBox(height: 16),
                AppText(
                  _bi('وحدات أمر الصيانة', 'Maintenance order components'),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                _componentCard(
                  index: 0,
                  title: DocumentNomenclature.maintenanceOrder(arabic: _arabic),
                  subtitle: _bi(
                    'مسودة الأمر والتصديق الأساسي',
                    'Order draft and primary approval',
                  ),
                  icon: Icons.assignment_outlined,
                  color: const Color(0xFF2876C8),
                  componentType: 'order_approval',
                ),
                _fieldView(
                  'stockIssue',
                  _componentCard(
                    index: 2,
                    title: _bi('التجهيز المخزني', 'Warehouse issue'),
                    subtitle:
                        order.stockIssueNumber ??
                        _bi('لم يُنشأ إذن الصرف بعد', 'No stock issue yet'),
                    icon: Icons.inventory_2_outlined,
                    color: const Color(0xFFB87818),
                    componentType: 'stock',
                  ),
                ),
                _fieldView(
                  'invoice',
                  _componentCard(
                    index: 4,
                    title: DocumentNomenclature.maintenanceInvoice(
                      arabic: _arabic,
                    ),
                    subtitle:
                        order.invoiceNumber ??
                        _bi('لم تُنشأ الفاتورة بعد', 'No invoice yet'),
                    icon: Icons.receipt_long_outlined,
                    color: const Color(0xFF7A4EC2),
                    componentType: 'invoice',
                  ),
                ),
                _fieldView('payments', _paymentCard(order)),
                const SizedBox(height: 18),
                AppText(
                  _bi('بنود الصيانة', 'Maintenance lines'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                ..._lines.map((line) {
                  final issued = _lineQuantity(line.id, 'issuedQuantity', 0);
                  final invoiced = _lineQuantity(
                    line.id,
                    'invoicedQuantity',
                    0,
                  );
                  final remaining = _lineQuantity(
                    line.id,
                    'remainingQuantity',
                    line.quantity - issued,
                  );
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        line.isService
                            ? Icons.design_services_outlined
                            : Icons.inventory_2_outlined,
                      ),
                      title: AppText(line.productName),
                      subtitle: AppText(
                        line.isService
                            ? _bi(
                                'عمل/خدمة منفصلة • السعر: ${MoneyFormatter.withCurrency(line.unitPrice, order.currencyCode)}',
                                'Separate labor/service • Price: ${MoneyFormatter.withCurrency(line.unitPrice, order.currencyCode)}',
                              )
                            : _bi(
                                'المطلوب: ${line.quantity} • المصروف: $issued • المفوتر: $invoiced • المتبقي للصرف: $remaining • المخزن: ${line.warehouseName ?? '—'}',
                                'Requested: ${line.quantity} • Issued: $issued • Invoiced: $invoiced • To issue: $remaining • Warehouse: ${line.warehouseName ?? '—'}',
                              ),
                      ),
                      trailing: line.isService
                          ? null
                          : Chip(
                              label: AppText(
                                remaining <= 0 && invoiced >= line.quantity
                                    ? _bi('مطابق', 'Reconciled')
                                    : remaining <= 0
                                    ? _bi('بانتظار الفوترة', 'Awaiting invoice')
                                    : issued > 0
                                    ? _bi('صرف جزئي', 'Partially issued')
                                    : _bi('بانتظار الصرف', 'Awaiting issue'),
                              ),
                            ),
                    ),
                  );
                }),
              ],
            ),
    );
  }

  Widget _summary(MaintenanceOrderModel order) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 24,
        runSpacing: 12,
        children: <Widget>[
          _value(_bi('السيارة', 'Vehicle'), order.carName),
          _value(_bi('العميل', 'Customer'), order.customerName ?? '—'),
          _value(_bi('الحالة', 'Status'), order.workflowLabel(_arabic)),
          _value(
            _bi('التاريخ والوقت التشغيلي', 'Operational date and time'),
            order.maintenanceDate.isEmpty ? '—' : order.maintenanceDate,
          ),
          _value(
            _bi('الكلفة', 'Cost'),
            MoneyFormatter.withCurrency(order.totalCost, order.currencyCode),
          ),
          _value(
            _bi('السعر', 'Price'),
            MoneyFormatter.withCurrency(order.salePrice, order.currencyCode),
          ),
          _value(
            _bi('المدفوع', 'Paid'),
            MoneyFormatter.withCurrency(order.paidAmount, order.currencyCode),
          ),
        ],
      ),
    ),
  );

  Widget _costReconciliation(MaintenanceOrderModel order) {
    final costs = _costs;
    if (costs == null) return const SizedBox.shrink();
    String money(double value) =>
        MoneyFormatter.withCurrency(value, costs.currency);
    final unavailable = _bi('غير مسجل في مستند الصيانة', 'Not recorded');
    Widget group(String title, List<(String, String)> values) => Container(
      constraints: const BoxConstraints(minWidth: 250),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppText(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: AppText(value.$1)),
                  const SizedBox(width: 8),
                  AppText(
                    value.$2,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    final discrepancy = costs.materialDiscrepancy || costs.laborDiscrepancy;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.account_balance_wallet_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: AppText(
                    _bi(
                      'مطابقة الكلفة والفوترة',
                      'Cost and billing reconciliation',
                    ),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                KajStatusBadge(
                  label: discrepancy
                      ? _bi('توجد فروقات', 'Discrepancy')
                      : _bi('متطابق', 'Reconciled'),
                  color: discrepancy
                      ? KajDesignTokens.warning
                      : KajDesignTokens.success,
                  icon: discrepancy
                      ? Icons.warning_amber_rounded
                      : Icons.verified_outlined,
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 900;
                Widget slot(Widget child) =>
                    narrow ? child : Expanded(child: child);
                return Flex(
                  direction: narrow ? Axis.vertical : Axis.horizontal,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    slot(
                      group(
                        _bi('تشغيلي / كلفة', 'Operational / Cost'),
                        <(String, String)>[
                          (
                            _bi(
                              'كلفة المواد المطلوبة',
                              'Requested materials cost',
                            ),
                            costs.requestedCostAvailable &&
                                    costs.requestedMaterialsCost != null
                                ? money(costs.requestedMaterialsCost!)
                                : unavailable,
                          ),
                          (
                            _bi(
                              'الكلفة الفعلية للمواد المصروفة',
                              'Issued materials actual cost',
                            ),
                            money(costs.issuedMaterialsActualCost),
                          ),
                          (_bi('العمل', 'Labor'), money(costs.laborCost)),
                          (
                            _bi('الخدمات الإضافية', 'Additional services'),
                            money(costs.additionalServicesCost),
                          ),
                          (
                            _bi(
                              'إجمالي الكلفة التشغيلية',
                              'Total operational cost',
                            ),
                            money(costs.totalOperationalCost),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: constraints.maxWidth < 900 ? 0 : 10,
                      height: constraints.maxWidth < 900 ? 10 : 0,
                    ),
                    slot(
                      group(_bi('الفوترة', 'Billing'), <(String, String)>[
                        (
                          _bi('المواد المفوترة', 'Materials invoiced'),
                          money(costs.materialsInvoiced),
                        ),
                        (
                          _bi('العمل المفوتر', 'Labor invoiced'),
                          money(costs.laborInvoiced),
                        ),
                        (
                          _bi('الخدمات المفوترة', 'Services invoiced'),
                          money(costs.servicesInvoiced),
                        ),
                        (
                          _bi('الخصم', 'Discount'),
                          costs.discount == null
                              ? unavailable
                              : money(costs.discount!),
                        ),
                        (
                          _bi('الضريبة', 'Tax'),
                          costs.tax == null ? unavailable : money(costs.tax!),
                        ),
                        (
                          _bi('إجمالي المفوتر', 'Total invoiced'),
                          money(costs.totalInvoiced),
                        ),
                      ]),
                    ),
                    SizedBox(
                      width: constraints.maxWidth < 900 ? 0 : 10,
                      height: constraints.maxWidth < 900 ? 10 : 0,
                    ),
                    slot(
                      group(
                        _bi('التسوية والفروقات', 'Settlement & Discrepancy'),
                        <(String, String)>[
                          (_bi('المدفوع', 'Paid'), money(costs.paid)),
                          (
                            _bi('المتبقي', 'Outstanding'),
                            money(costs.outstanding),
                          ),
                          (
                            _bi('مصروف غير مفوتر', 'Issued not invoiced'),
                            money(costs.issuedNotInvoicedCost),
                          ),
                          (
                            _bi('مفوتر غير مصروف', 'Invoiced not issued'),
                            money(costs.invoicedNotIssuedValue),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            if (costs.warehouses.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              AppText(
                _bi('مساهمة المخازن', 'Warehouse cost contribution'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: costs.warehouses
                    .map(
                      (row) => Chip(
                        label: AppText(
                          '${row['warehouseName'] ?? '-'}: ${money((row['issuedActualCost'] as num?)?.toDouble() ?? 0)}',
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
            const SizedBox(height: 14),
            AppText(
              _bi('مطابقة الكميات', 'Quantity reconciliation'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            for (final line in costs.lines)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: AppText(line['description']?.toString() ?? '-'),
                subtitle: AppText(
                  _bi(
                    'مطلوب: ${line['requestedQuantity']} • مصروف: ${line['issuedQuantity']} • متبقي: ${line['remainingQuantity']} • مفوتر: ${line['invoicedQuantity']}',
                    'Requested: ${line['requestedQuantity']} • Issued: ${line['issuedQuantity']} • Remaining: ${line['remainingQuantity']} • Invoiced: ${line['invoicedQuantity']}',
                  ),
                ),
                trailing:
                    _order.workflowStage == 'stock_issue_draft' &&
                        ((line['remainingQuantity'] as num?)?.toDouble() ?? 0) >
                            0
                    ? FilledButton.tonalIcon(
                        onPressed: _busy ? null : () => _issueMaterial(line),
                        icon: const Icon(Icons.output_rounded),
                        label: AppText(_bi('صرف', 'Issue')),
                      )
                    : null,
              ),
            if (costs.issueEvents.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              AppText(
                _bi('سجل عمليات الصرف', 'Material issue events'),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              for (final event in costs.issueEvents)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: AppText(
                    '${event['warehouseName']} • ${event['quantity']}',
                  ),
                  subtitle: AppText(event['status']?.toString() ?? ''),
                  trailing:
                      event['status'] == 'executed' &&
                          !<String>{
                            'invoice_approved',
                            'paid',
                            'completed',
                          }.contains(_order.workflowStage)
                      ? IconButton(
                          tooltip: _bi('عكس عملية الصرف', 'Reverse issue'),
                          onPressed: _busy ? null : () => _reverseIssue(event),
                          icon: const Icon(Icons.undo_rounded),
                        )
                      : null,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _value(String label, String value) => SizedBox(
    width: 230,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppText(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        AppText(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    ),
  );

  Widget _componentCard({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String componentType,
  }) {
    final stage = _stageIndex;
    final exists = stage >= index;
    final approved = stage > index;
    final canAdvance = stage == index || (index > 0 && stage == index - 1);
    final creatingDraft = index > 0 && stage == index - 1;
    final canDelete = exists && !_order.isCancelled;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: .35)),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppText(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  AppText(
                    subtitle,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            _StatusChip(
              label: approved
                  ? _bi('مصدق', 'Approved')
                  : exists
                  ? _bi('مسودة', 'Draft')
                  : _bi('غير منشأ', 'Not created'),
              color: approved
                  ? const Color(0xFF178A65)
                  : exists
                  ? const Color(0xFFB87818)
                  : const Color(0xFF68737D),
            ),
            const SizedBox(width: 10),
            if (canAdvance)
              _fieldAction(
                componentType == 'stock'
                    ? 'stockIssue'
                    : componentType == 'invoice'
                    ? 'invoice'
                    : 'status',
                _StageAction(
                  label: creatingDraft
                      ? _bi('إنشاء المسودة', 'Create draft')
                      : _bi('تصديق', 'Approve'),
                  icon: Icons.verified_outlined,
                  busy: _busy,
                  onPressed: () => _run(
                    componentType: componentType,
                    action: 'approve',
                    successAr: 'تم تصديق المرحلة وتحديث الارتباطات.',
                    successEn:
                        'The stage was approved and links were refreshed.',
                  ),
                ),
              ),
            if (canDelete) ...<Widget>[
              const SizedBox(width: 6),
              _StageAction(
                label: _bi('حذف', 'Delete'),
                icon: Icons.delete_outline_rounded,
                busy: _busy,
                onPressed: () => _run(
                  componentType: componentType,
                  action: 'delete',
                  successAr: 'تم حذف المرحلة وعكس ارتباطاتها.',
                  successEn:
                      'The stage was deleted and its links were reversed.',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _paymentCard(MaintenanceOrderModel order) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF178A65).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.account_balance_wallet_outlined,
              color: Color(0xFF178A65),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppText(
                  _bi('الدفعة المالية', 'Payment'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                AppText(
                  _bi(
                    'المدفوع المخصص للأمر: ${MoneyFormatter.withCurrency(order.paidAmount, order.currencyCode)}. عند حذف الفاتورة أو الأمر تبقى الدفعة رصيدًا للعميل، وتُستخدم تلقائيًا في أمر لاحق؛ حذفها النهائي يتم من الصندوق.',
                    'Allocated to this order: ${MoneyFormatter.withCurrency(order.paidAmount, order.currencyCode)}. If the invoice or order is deleted, the payment remains as customer credit and is reused automatically; final deletion is from the cashbox.',
                  ),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (widget.onPayment != null &&
              order.workflowStage == 'invoice_approved') ...<Widget>[
            _fieldAction(
              'payments',
              _StageAction(
                label: _bi('تسجيل دفعة', 'Record payment'),
                icon: Icons.add_card_rounded,
                busy: _busy,
                onPressed: () async {
                  await widget.onPayment?.call();
                  await _loadDetails();
                },
              ),
            ),
            const SizedBox(width: 6),
          ],
          _StageAction(
            label: _bi('فتح الصندوق', 'Open cashbox'),
            icon: Icons.open_in_new_rounded,
            onPressed: () =>
                AppModuleNavigation.open(context, AppRouteNames.accounting),
          ),
        ],
      ),
    ),
  );
}

class _StageAction extends StatelessWidget {
  const _StageAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => AppModuleActionIcon(
    tooltip: label,
    icon: icon,
    busy: busy,
    onPressed: busy ? null : onPressed,
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: color.withValues(alpha: .30)),
    ),
    child: AppText(
      label,
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
    ),
  );
}
