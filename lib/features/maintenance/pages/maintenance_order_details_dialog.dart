import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/app/route_names.dart';
import 'package:quality_line_erp/core/documents/document_nomenclature.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/operations/operational_lifecycle_table.dart';
import 'package:quality_line_erp/core/printing/maintenance_document_pdf_service.dart';
import 'package:quality_line_erp/core/utils/currency_totals_formatter.dart';
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
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
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
  List<Map<String, Object?>> _payments = const <Map<String, Object?>>[];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _loadWarning;

  bool get _arabic => context.l10n.isArabic;
  String _bi(String arabic, String english) => _arabic ? arabic : english;

  bool _canAction(String action, {String legacy = 'maintenance.approve'}) =>
      context.read<AccessController>().canPerformAction(
        'maintenance',
        action,
        legacyPermission: legacy,
      );

  String? get _nextPermissionAction => switch (_order.workflowStage) {
    'order_draft' => 'order.approve',
    'order_approved' => 'material_issue.create',
    'stock_issue_draft' => 'material_issue.approve',
    'stock_issue_approved' =>
      _order.pricingType == 'paid' ? 'invoice.create' : 'order.approve',
    'invoice_draft' => 'invoice.approve',
    _ => null,
  };

  bool get _canAdvanceWithPermission {
    final action = _nextPermissionAction;
    return _canAdvance && action != null && _canAction(action);
  }

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
    // A persisted order draft has no downstream stock/invoice state yet.
    // Render the authoritative order row immediately and load only its core
    // lines; reconciliation remains a post-draft concern. This prevents an
    // optional downstream snapshot from blanking a valid draft.
    if (_isOrderDraft) {
      _loading = false;
      unawaited(_loadDraftCoreLines());
      return;
    }
    // Later workflow stages load the bounded authoritative snapshot.
    unawaited(_loadDetails());
  }

  bool get _isOrderDraft =>
      const <String>{'draft', 'order_draft'}.contains(_order.workflowStage);

  Future<void> _reloadDetails() =>
      _isOrderDraft ? _loadDraftCoreLines() : _loadDetails();

  Future<void> _loadDraftCoreLines() async {
    try {
      final lines = await _repository.getOrderLines(_order.id);
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _loading = false;
        _error = null;
        _loadWarning = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        // The order row passed from the governed list is already persisted
        // core data. A line-read failure must remain visible and retryable,
        // never replace the whole draft with a blank workspace.
        _loading = false;
        _error = null;
        _loadWarning = userFacingError(
          error,
          isArabic: _arabic,
          arabicFallback:
              'تم فتح مسودة الصيانة، لكن تعذر تحميل بعض البنود. حدّث المسودة لإعادة المحاولة.',
          englishFallback:
              'The maintenance draft was opened, but some lines could not be loaded. Refresh the draft to retry.',
        );
      });
    }
  }

  Future<void> _loadDetails() async {
    try {
      final snapshot = await _repository.getOrderSnapshot(_order.id);
      List<Map<String, Object?>> payments = const <Map<String, Object?>>[];
      try {
        payments = await _repository.getMaintenancePayments(_order.id);
      } catch (_) {
        payments = const <Map<String, Object?>>[];
      }
      if (!mounted) return;
      setState(() {
        _order = snapshot.order;
        _lines = snapshot.lines;
        _costs = snapshot.reconciliation;
        _payments = payments;
        _loading = false;
        _error = null;
        _loadWarning = null;
      });
      return;
    } catch (snapshotError) {
      // A draft is still a valid persisted document even if optional snapshot
      // analytics fail. Fall back to the core lines/reconciliation calls so a
      // nullable relation or analytics RPC can never blank the whole page.
      List<MaintenanceLineModel>? fallbackLines;
      MaintenanceCostReconciliation? fallbackCosts;
      try {
        fallbackLines = await _repository.getOrderLines(_order.id);
      } catch (_) {
        fallbackLines = null;
      }
      try {
        fallbackCosts = await _repository.getCostReconciliation(_order.id);
      } catch (_) {
        fallbackCosts = null;
      }
      if (!mounted) return;
      setState(() {
        if (fallbackLines != null) _lines = fallbackLines;
        if (fallbackCosts != null) _costs = fallbackCosts;
        _loading = false;
        _error = null;
        _loadWarning = userFacingError(
          snapshotError,
          isArabic: _arabic,
          arabicFallback:
              'تم فتح أمر الصيانة بالبيانات الأساسية، لكن تعذر تحميل بعض بيانات التحليل الإضافية.',
          englishFallback:
              'The maintenance order was opened with its core data, but some optional analytics could not be loaded.',
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

  Future<void> _draftMaterial(Map<String, Object?> line) async {
    if (_busy || !_canAction('material_issue.create')) return;
    final partId = line['lineId']?.toString() ?? '';
    final remaining = (line['remainingQuantity'] as num?)?.toDouble() ?? 0;
    final drafted = (line['draftedQuantity'] as num?)?.toDouble() ?? 0;
    final availableToDraft = (remaining - drafted).clamp(0, remaining);
    if (partId.isEmpty || availableToDraft <= 0) return;
    setState(() => _busy = true);
    try {
      final options = await _repository.getIssueWarehouseOptions(partId);
      if (!mounted) return;
      if (options.isEmpty)
        throw StateError('maintenance_issue_no_available_warehouse');
      var warehouseId = options.first['warehouse_id']?.toString() ?? '';
      final quantity = TextEditingController(text: availableToDraft.toString());
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: AppText(
              _bi('إضافة مادة لمسودة الصرف', 'Add material to issue draft'),
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
                        'الكمية المتاحة للمسودة ($availableToDraft)',
                        'Quantity available to draft ($availableToDraft)',
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
                child: AppText(_bi('إضافة إلى المسودة', 'Add to draft')),
              ),
            ],
          ),
        ),
      );
      if (accepted != true) return;
      final amount = double.tryParse(quantity.text.trim()) ?? 0;
      await _repository.saveMaterialIssueDraftLine(
        orderId: _order.id,
        partId: partId,
        warehouseId: warehouseId,
        quantity: amount,
      );
      await _reloadDetails();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
              _bi(
                'تم حفظ الكمية في مسودة الصرف. لم يتغير المخزون؛ سيحدث الصرف عند التصديق فقط.',
                'Quantity saved to the issue draft. Inventory is unchanged and will move only on approval.',
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
                arabicFallback: 'تعذر حفظ مادة في مسودة الصرف.',
                englishFallback:
                    'Unable to save the maintenance issue draft line.',
              ),
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _dateTimeDisplay(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return '—';
    final parsed = DateTime.tryParse(raw)?.toLocal();
    return parsed == null ? raw : DateFormat('yyyy-MM-dd HH:mm').format(parsed);
  }

  Future<void> _deleteDraftIssueLine(Map<String, Object?> row) async {
    if (_busy || !_canAction('material_issue.create')) return;
    final lineId = row['id']?.toString() ?? '';
    if (lineId.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(
          _bi('حذف بند من مسودة الصرف', 'Remove issue draft line'),
        ),
        content: AppText(
          _bi(
            'سيُحذف هذا البند من المسودة فقط. لن يتغير المخزون.',
            'This line will be removed from the draft only. Inventory will not change.',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: AppText(_bi('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: AppText(_bi('حذف من المسودة', 'Remove from draft')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repository.deleteMaterialIssueDraftLine(lineId);
      await _reloadDetails();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: AppText(
            userFacingError(
              error,
              isArabic: _arabic,
              arabicFallback: 'تعذر حذف بند مسودة الصرف.',
              englishFallback: 'Unable to remove the issue draft line.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reverseIssue(Map<String, Object?> event) async {
    if (!_canAction('reverse', legacy: 'maintenance.update')) return;
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
      await _reloadDetails();
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
    if (_busy || !_canAdvanceWithPermission) return;
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
          if (_canAdvanceWithPermission)
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
                      await _reloadDetails();
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
                      await _reloadDetails();
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
                      await _reloadDetails();
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
                if (_loadWarning != null) ...<Widget>[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Icon(Icons.info_outline_rounded),
                          const SizedBox(width: 10),
                          Expanded(child: AppText(_loadWarning ?? '')),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
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
                  _bi('إدارة مراحل الأمر', 'Manage order stages'),
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
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
                      _maintenanceInvoiceTable(order),
                    ],
                  ),
                ),
                _fieldView('payments', _maintenancePaymentsTable(order)),
                const SizedBox(height: 18),
                AppText(
                  _bi('بنود الصيانة', 'Maintenance lines'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                _maintenanceLinesTable(order),
              ],
            ),
    );
  }

  Widget _maintenanceLinesTable(MaintenanceOrderModel _) {
    final reconciliationByLine = <String, Map<String, Object?>>{};
    for (final row in _costs?.lines ?? const <Map<String, Object?>>[]) {
      final lineId = row['lineId']?.toString().trim() ?? '';
      if (lineId.isNotEmpty) reconciliationByLine[lineId] = row;
    }
    final lifecycleRows = _lines
        .map((line) {
          final reconciliation = reconciliationByLine[line.id];
          return <String, Object?>{
            ...?reconciliation,
            'lineId': line.id,
            'itemId': line.productId,
            'productName': line.productName,
            'description': line.description.trim().isNotEmpty
                ? line.description.trim()
                : line.productName,
            'requestedQuantity': line.quantity,
            'lineType': line.lineType,
          };
        })
        .toList(growable: false);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: OperationalLifecycleTable(
        rows: lifecycleRows,
        itemLabel: _bi('المادة / الخدمة', 'Item / Service'),
        descriptionLabel: _bi('الوصف', 'Description'),
        requestedLabel: _bi('المطلوب', 'Requested'),
        logisticsLabel: _bi('المصروف', 'Issue'),
        invoicedLabel: _bi('المفوتر', 'Invoiced'),
        remainingLogisticsLabel: _bi('المتبقي للصرف', 'Remaining logistics'),
        remainingInvoiceLabel: _bi('المتبقي للفوترة', 'Remaining invoice'),
        emptyLabel: _bi(
          'لا توجد بنود في هذا الأمر.',
          'No items in this order.',
        ),
        itemTextBuilder: (line) =>
            line.raw['productName']?.toString() ??
            (line.itemId.isEmpty ? '-' : line.itemId),
        descriptionTextBuilder: (line) =>
            line.description.isEmpty ? '-' : line.description,
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
            CurrencyTotalsFormatter.format(
              order.operationalCostTotalsByCurrency,
            ),
          ),
          _fieldView(
            'materialCost',
            _value(
              _bi('كلفة المواد', 'Material cost'),
              MoneyFormatter.withCurrency(order.partsCost, order.currencyCode),
            ),
          ),
          _fieldView(
            'margin',
            _value(
              _bi('الهامش', 'Margin'),
              MoneyFormatter.withCurrency(order.profit, order.currencyCode),
            ),
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

  Widget _issueDraftSection(MaintenanceCostReconciliation costs) {
    final state = costs.issueDraft;
    if (state.isEmpty) return const SizedBox.shrink();
    final current = state['currentDraft'] is Map
        ? Map<String, Object?>.from(state['currentDraft'] as Map)
        : const <String, Object?>{};
    final draftLines = (state['draftLines'] as List? ?? const <Object?>[])
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
    final history = (state['history'] as List? ?? const <Object?>[])
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
    if (current.isEmpty && draftLines.isEmpty && history.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget table({
      required List<DataColumn> columns,
      required List<DataRow> rows,
    }) => Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 42,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 58,
          columnSpacing: 18,
          columns: columns,
          rows: rows,
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 14),
        AppText(
          _bi('مستند صرف مواد الصيانة', 'Maintenance material issue document'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        if (current.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              Chip(
                avatar: const Icon(Icons.description_outlined, size: 18),
                label: AppText(
                  '${_bi('رقم المسودة', 'Draft number')}: ${current['documentNumber'] ?? '—'}',
                ),
              ),
              Chip(
                avatar: const Icon(Icons.person_outline_rounded, size: 18),
                label: AppText(
                  '${_bi('أنشأ المسودة', 'Draft created by')}: ${current['createdByName'] ?? current['createdBy'] ?? '—'}',
                ),
              ),
              Chip(
                avatar: const Icon(Icons.schedule_rounded, size: 18),
                label: AppText(
                  '${_bi('وقت الإنشاء', 'Created at')}: ${_dateTimeDisplay(current['createdAt'])}',
                ),
              ),
              Chip(
                avatar: const Icon(Icons.info_outline_rounded, size: 18),
                label: AppText(
                  _bi(
                    'مسودة فقط — المخزون لم يتغير',
                    'Draft only — inventory unchanged',
                  ),
                ),
              ),
            ],
          ),
        if (draftLines.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          table(
            columns: <DataColumn>[
              DataColumn(label: AppText(_bi('المادة', 'Item'))),
              DataColumn(label: AppText(_bi('المخزن', 'Warehouse'))),
              DataColumn(label: AppText(_bi('كمية المسودة', 'Draft qty'))),
              DataColumn(label: AppText(_bi('أُدخل بواسطة', 'Entered by'))),
              DataColumn(label: AppText(_bi('التاريخ/الوقت', 'Date / time'))),
              DataColumn(label: AppText(_bi('الإجراء', 'Action'))),
            ],
            rows: draftLines
                .map(
                  (row) => DataRow(
                    cells: <DataCell>[
                      DataCell(
                        AppText(
                          '${row['productName'] ?? row['productId'] ?? '—'}',
                        ),
                      ),
                      DataCell(
                        AppText(
                          '${row['warehouseName'] ?? row['warehouseId'] ?? '—'}',
                        ),
                      ),
                      DataCell(AppText('${row['quantity'] ?? '—'}')),
                      DataCell(
                        AppText(
                          '${row['createdByName'] ?? row['createdBy'] ?? '—'}',
                        ),
                      ),
                      DataCell(AppText(_dateTimeDisplay(row['createdAt']))),
                      DataCell(
                        _order.workflowStage == 'stock_issue_draft' &&
                                _canAction('material_issue.create')
                            ? IconButton(
                                tooltip: _bi(
                                  'حذف من المسودة',
                                  'Remove from draft',
                                ),
                                onPressed: _busy
                                    ? null
                                    : () => _deleteDraftIssueLine(row),
                                icon: const Icon(Icons.delete_outline_rounded),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                )
                .toList(growable: false),
          ),
        ],
        if (history.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          AppText(
            _bi('سجل تصديقات الصرف', 'Issue approval history'),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          table(
            columns: <DataColumn>[
              DataColumn(label: AppText(_bi('رقم الصرف', 'Issue number'))),
              DataColumn(
                label: AppText(_bi('أنشأ المسودة', 'Draft created by')),
              ),
              DataColumn(label: AppText(_bi('صدّق بواسطة', 'Approved by'))),
              DataColumn(label: AppText(_bi('وقت الإنشاء', 'Created at'))),
              DataColumn(label: AppText(_bi('وقت التصديق', 'Approval time'))),
              DataColumn(label: AppText(_bi('الكمية', 'Quantity'))),
              DataColumn(label: AppText(_bi('الحالة', 'Status'))),
            ],
            rows: history
                .map(
                  (row) => DataRow(
                    cells: <DataCell>[
                      DataCell(AppText('${row['documentNumber'] ?? '—'}')),
                      DataCell(
                        AppText(
                          '${row['createdByName'] ?? row['createdBy'] ?? '—'}',
                        ),
                      ),
                      DataCell(
                        AppText(
                          '${row['approvedByName'] ?? row['approvedBy'] ?? '—'}',
                        ),
                      ),
                      DataCell(AppText(_dateTimeDisplay(row['createdAt']))),
                      DataCell(AppText(_dateTimeDisplay(row['approvedAt']))),
                      DataCell(AppText('${row['quantity'] ?? '—'}')),
                      DataCell(AppText('${row['status'] ?? '—'}')),
                    ],
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ],
    );
  }

  Widget _costReconciliation(MaintenanceOrderModel order) {
    final costs = _costs;
    if (costs == null) return const SizedBox.shrink();
    String money(double value) =>
        MoneyFormatter.withCurrency(value, costs.currency);
    String costTotals(Map<String, double> totals) =>
        CurrencyTotalsFormatter.format(totals);
    final operationalTotals = <String, double>{
      ...costs.issuedMaterialsActualCostByCurrency,
    };
    if (costs.laborCost != 0 || costs.additionalServicesCost != 0) {
      operationalTotals.update(
        costs.currency,
        (value) => value + costs.laborCost + costs.additionalServicesCost,
        ifAbsent: () => costs.laborCost + costs.additionalServicesCost,
      );
    }
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
                  label: costs.crossCurrencyMaterials
                      ? _bi('كلفة متعددة العملات', 'Multi-currency cost')
                      : discrepancy
                      ? _bi('توجد فروقات', 'Discrepancy')
                      : _bi('متطابق', 'Reconciled'),
                  color: costs.crossCurrencyMaterials
                      ? KajDesignTokens.electricBlue
                      : discrepancy
                      ? KajDesignTokens.warning
                      : KajDesignTokens.success,
                  icon: costs.crossCurrencyMaterials
                      ? Icons.currency_exchange_rounded
                      : discrepancy
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
                      group(_bi('تشغيلي / كلفة', 'Operational / Cost'), <
                        (String, String)
                      >[
                        (
                          _bi(
                            'كلفة المواد المطلوبة',
                            'Requested materials cost',
                          ),
                          costs.requestedCostAvailable
                              ? costTotals(
                                  costs.requestedMaterialsCostByCurrency,
                                )
                              : unavailable,
                        ),
                        (
                          _bi(
                            'الكلفة الفعلية للمواد المصروفة',
                            'Issued materials actual cost',
                          ),
                          costTotals(costs.issuedMaterialsActualCostByCurrency),
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
                          costTotals(operationalTotals),
                        ),
                      ]),
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
                            costs.crossCurrencyMaterials
                                ? unavailable
                                : money(costs.issuedNotInvoicedCost),
                          ),
                          (
                            _bi('مفوتر غير مصروف', 'Invoiced not issued'),
                            costs.crossCurrencyMaterials
                                ? unavailable
                                : money(costs.invoicedNotIssuedValue),
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
            _issueDraftSection(costs),
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
                    'مطلوب: ${line['requestedQuantity']} • في المسودة: ${line['draftedQuantity'] ?? 0} • مصروف معتمد: ${line['issuedQuantity']} • متبقي: ${line['remainingQuantity']} • مفوتر: ${line['invoicedQuantity']}',
                    'Requested: ${line['requestedQuantity']} • Drafted: ${line['draftedQuantity'] ?? 0} • Approved issued: ${line['issuedQuantity']} • Remaining: ${line['remainingQuantity']} • Invoiced: ${line['invoicedQuantity']}',
                  ),
                ),
                trailing:
                    _order.workflowStage == 'stock_issue_draft' &&
                        _canAction('material_issue.create') &&
                        (((line['remainingQuantity'] as num?)?.toDouble() ??
                                    0) -
                                ((line['draftedQuantity'] as num?)
                                        ?.toDouble() ??
                                    0)) >
                            0
                    ? FilledButton.tonalIcon(
                        onPressed: _busy ? null : () => _draftMaterial(line),
                        icon: const Icon(Icons.output_rounded),
                        label: AppText(_bi('إضافة للمسودة', 'Add to draft')),
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
                  subtitle: AppText(
                    '${event['status'] ?? '—'} • ${_bi('صدّق بواسطة', 'Approved by')}: ${event['approvedByName'] ?? event['approvedBy'] ?? '—'} • ${_dateTimeDisplay(event['approvalTime'] ?? event['effectiveAt'])}',
                  ),
                  trailing:
                      event['status'] == 'executed' &&
                          _canAction('reverse', legacy: 'maintenance.update') &&
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
            if (canAdvance &&
                _nextPermissionAction != null &&
                _canAction(_nextPermissionAction!))
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
            if (canDelete &&
                _canAction(
                  'reverse',
                  legacy: 'maintenance.update',
                )) ...<Widget>[
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

  Map<String, Object?>? _reconciliationLine(String lineId) {
    final normalizedId = lineId.trim();
    if (normalizedId.isEmpty) return null;
    for (final row in _costs?.lines ?? const <Map<String, Object?>>[]) {
      if ((row['lineId']?.toString().trim() ?? '') == normalizedId) {
        return row;
      }
    }
    return null;
  }

  Widget _maintenanceInvoiceTable(MaintenanceOrderModel order) {
    final invoiceNumber = order.invoiceNumber?.trim() ?? '';
    if (invoiceNumber.isEmpty) {
      return const SizedBox.shrink();
    }
    final costs = _costs;
    final rows = <Map<String, Object?>>[];
    for (final line in _lines) {
      final reconciliation = _reconciliationLine(line.id);
      final quantity =
          (reconciliation?['invoicedQuantity'] as num?)?.toDouble() ?? 0;
      if (quantity <= 0) continue;
      final unitPrice =
          (reconciliation?['unitInvoiceValue'] as num?)?.toDouble() ??
          line.unitPrice;
      final lineTotal =
          (reconciliation?['invoicedValue'] as num?)?.toDouble() ??
          (unitPrice * quantity);
      rows.add(<String, Object?>{
        'item': line.productName,
        'description': line.description.trim().isNotEmpty
            ? line.description.trim()
            : (line.isService
                  ? _bi('خدمة صيانة', 'Maintenance service')
                  : _bi('مادة صيانة', 'Maintenance material')),
        'quantity': quantity,
        'unitPrice': unitPrice,
        'lineTotal': lineTotal,
      });
    }
    final laborInvoiced = costs?.laborInvoiced ?? 0;
    if (laborInvoiced > 0) {
      rows.add(<String, Object?>{
        'item': _bi('أجور العمل', 'Labor'),
        'description': _bi(
          'أجور العمل والخدمة لأمر الصيانة',
          'Maintenance labor and service charge',
        ),
        'quantity': 1.0,
        'unitPrice': laborInvoiced,
        'lineTotal': laborInvoiced,
      });
    }
    final invoiceTotal = costs?.totalInvoiced ?? order.salePrice;
    final createdAt = order.invoiceCreatedAt?.toLocal();
    final approvedAt = order.invoiceApprovedAt?.toLocal();
    final invoiceDate = approvedAt ?? createdAt ?? order.updatedAt?.toLocal();
    final dateText = invoiceDate == null
        ? '—'
        : DateFormat('yyyy-MM-dd HH:mm').format(invoiceDate);
    final createdBy = (order.invoiceCreatedBy?.trim().isNotEmpty ?? false)
        ? order.invoiceCreatedBy!
        : (order.createdByName?.trim().isNotEmpty ?? false)
        ? order.createdByName!
        : '—';
    final approvedBy = (order.invoiceApprovedBy?.trim().isNotEmpty ?? false)
        ? order.invoiceApprovedBy!
        : '—';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppText(
              _bi('تفاصيل فاتورة الصيانة', 'Maintenance invoice details'),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            if (rows.isEmpty)
              AppText(
                _bi(
                  'الفاتورة موجودة، لكن لا توجد بنود مفوترة متاحة في نموذج القراءة الحالي.',
                  'The invoice exists, but no invoiced lines are available in the current read model.',
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: <DataColumn>[
                    DataColumn(
                      label: AppText(_bi('رقم الفاتورة', 'Invoice number')),
                    ),
                    DataColumn(
                      label: AppText(_bi('مرجع المستند', 'Document reference')),
                    ),
                    DataColumn(
                      label: AppText(_bi('المادة/الخدمة', 'Item / service')),
                    ),
                    DataColumn(label: AppText(_bi('الوصف', 'Description'))),
                    DataColumn(label: AppText(_bi('الكمية', 'Quantity'))),
                    DataColumn(label: AppText(_bi('سعر الوحدة', 'Unit price'))),
                    DataColumn(label: AppText(_bi('الضريبة', 'Tax'))),
                    DataColumn(label: AppText(_bi('الخصم', 'Discount'))),
                    DataColumn(
                      label: AppText(_bi('إجمالي السطر', 'Line total')),
                    ),
                    DataColumn(label: AppText(_bi('العملة', 'Currency'))),
                    DataColumn(
                      label: AppText(_bi('إجمالي الفاتورة', 'Invoice total')),
                    ),
                    DataColumn(label: AppText(_bi('أنشأها', 'Created by'))),
                    DataColumn(
                      label: AppText(
                        _bi('اعتمد/رحّل بواسطة', 'Approved / posted by'),
                      ),
                    ),
                    DataColumn(
                      label: AppText(_bi('التاريخ/الوقت', 'Date / time')),
                    ),
                  ],
                  rows: rows
                      .map(
                        (row) => DataRow(
                          cells: <DataCell>[
                            DataCell(AppText(invoiceNumber)),
                            DataCell(AppText(order.orderNumber)),
                            DataCell(AppText('${row['item'] ?? '—'}')),
                            DataCell(AppText('${row['description'] ?? '—'}')),
                            DataCell(AppText('${row['quantity'] ?? 0}')),
                            DataCell(
                              AppText(
                                MoneyFormatter.withCurrency(
                                  (row['unitPrice'] as num?)?.toDouble() ?? 0,
                                  order.currencyCode,
                                ),
                              ),
                            ),
                            const DataCell(AppText('—')),
                            const DataCell(AppText('—')),
                            DataCell(
                              AppText(
                                MoneyFormatter.withCurrency(
                                  (row['lineTotal'] as num?)?.toDouble() ?? 0,
                                  order.currencyCode,
                                ),
                              ),
                            ),
                            DataCell(AppText(order.currencyCode)),
                            DataCell(
                              AppText(
                                MoneyFormatter.withCurrency(
                                  invoiceTotal,
                                  order.currencyCode,
                                ),
                              ),
                            ),
                            DataCell(AppText(createdBy)),
                            DataCell(AppText(approvedBy)),
                            DataCell(AppText(dateText)),
                          ],
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            if ((costs?.tax ?? 0) != 0 ||
                (costs?.discount ?? 0) != 0) ...<Widget>[
              const SizedBox(height: 8),
              AppText(
                _bi(
                  'ضريبة المستند: ${MoneyFormatter.withCurrency(costs?.tax ?? 0, order.currencyCode)} • خصم المستند: ${MoneyFormatter.withCurrency(costs?.discount ?? 0, order.currencyCode)}',
                  'Document tax: ${MoneyFormatter.withCurrency(costs?.tax ?? 0, order.currencyCode)} • Document discount: ${MoneyFormatter.withCurrency(costs?.discount ?? 0, order.currencyCode)}',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _maintenancePaymentsTable(MaintenanceOrderModel order) {
    final ar = _arabic;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: AppText(
                    _bi('دفعات أمر الصيانة', 'Maintenance Payments'),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                if (widget.onPayment != null &&
                    order.workflowStage == 'invoice_approved')
                  _fieldAction(
                    'payments',
                    _StageAction(
                      label: _bi('تسجيل دفعة', 'Record payment'),
                      icon: Icons.add_card_rounded,
                      busy: _busy,
                      onPressed: () async {
                        await widget.onPayment?.call();
                        await _reloadDetails();
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_payments.isEmpty)
              AppText(
                _bi(
                  'لا توجد دفعات مخصصة لهذا الأمر. المدفوع الحالي: ${MoneyFormatter.withCurrency(order.paidAmount, order.currencyCode)}',
                  'No payments are allocated to this order. Current paid amount: ${MoneyFormatter.withCurrency(order.paidAmount, order.currencyCode)}',
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: <DataColumn>[
                    DataColumn(
                      label: AppText(_bi('مرجع الدفعة', 'Payment reference')),
                    ),
                    DataColumn(label: AppText(_bi('الصندوق', 'Cashbox'))),
                    DataColumn(label: AppText(_bi('العملة', 'Currency'))),
                    DataColumn(label: AppText(_bi('المبلغ', 'Amount'))),
                    DataColumn(label: AppText(_bi('FX', 'FX details'))),
                    DataColumn(
                      label: AppText(
                        _bi('التاريخ/الوقت', 'Payment date / time'),
                      ),
                    ),
                    DataColumn(label: AppText(_bi('المستخدم', 'User'))),
                    DataColumn(
                      label: AppText(_bi('الفاتورة/الأمر', 'Invoice / order')),
                    ),
                    DataColumn(label: AppText(_bi('الحالة', 'Status'))),
                  ],
                  rows: _payments
                      .map((payment) {
                        final parsed = DateTime.tryParse(
                          '${payment['paymentDate'] ?? ''}',
                        )?.toLocal();
                        final dateText = parsed == null
                            ? '${payment['paymentDate'] ?? '—'}'
                            : DateFormat('yyyy-MM-dd HH:mm').format(parsed);
                        final fx =
                            '${payment['currency'] ?? ''}' ==
                                '${payment['invoiceCurrency'] ?? ''}'
                            ? '—'
                            : '${payment['exchangeRate'] ?? 1} • Δ ${payment['exchangeDifference'] ?? 0}';
                        return DataRow(
                          cells: <DataCell>[
                            DataCell(
                              AppText('${payment['paymentReference'] ?? '—'}'),
                            ),
                            DataCell(
                              AppText(
                                '${payment['cashboxName'] ?? payment['cashboxId'] ?? '—'}',
                              ),
                            ),
                            DataCell(AppText('${payment['currency'] ?? '—'}')),
                            DataCell(AppText('${payment['amount'] ?? 0}')),
                            DataCell(AppText(fx)),
                            DataCell(AppText(dateText)),
                            DataCell(AppText('${payment['userName'] ?? '—'}')),
                            DataCell(
                              AppText(
                                '${payment['relatedInvoice'] ?? '—'} • ${payment['relatedOrder'] ?? '—'}',
                              ),
                            ),
                            DataCell(
                              AppText(
                                ar
                                    ? 'مرحّل'
                                    : '${payment['status'] ?? 'Posted'}',
                              ),
                            ),
                          ],
                        );
                      })
                      .toList(growable: false),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Retained as the compact payment summary contract for alternate layouts.
  // ignore: unused_element
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
                  await _reloadDetails();
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
