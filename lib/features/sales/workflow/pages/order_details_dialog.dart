import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:quality_line_erp/app/route_names.dart';
import 'package:quality_line_erp/core/documents/document_nomenclature.dart';
import 'package:quality_line_erp/core/exporting/binary_download_service.dart';
import 'package:quality_line_erp/core/documents/models/document_models.dart';
import 'package:quality_line_erp/core/documents/repositories/document_management_repository.dart';
import 'package:quality_line_erp/core/documents/repositories/document_storage_repository.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/finance/invoice_payment_batch_dialog.dart';
import 'package:quality_line_erp/core/widgets/warehouse_allocation_dialog.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:quality_line_erp/core/printing/enterprise_document_pdf_service.dart';
import 'package:quality_line_erp/core/widgets/app_module_action_icon.dart';
import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
import 'package:quality_line_erp/core/widgets/app_top_navigation.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/features/purchases/pages/purchase_order_draft_page.dart';
import 'package:quality_line_erp/features/purchases/repositories/purchase_workflow_repository.dart';
import 'package:quality_line_erp/features/sales/workflow/pages/sales_order_draft_page.dart';
import 'package:quality_line_erp/features/sales/workflow/models/commercial_order_details.dart';
import 'package:quality_line_erp/features/sales/workflow/repositories/commercial_order_details_repository.dart';
import 'package:quality_line_erp/features/sales/workflow/repositories/sales_workflow_repository.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

class OrderDetailsDialog extends StatefulWidget {
  const OrderDetailsDialog({
    super.key,
    required this.orderId,
    required this.purchase,
  });

  final String orderId;
  final bool purchase;

  @override
  State<OrderDetailsDialog> createState() => _OrderDetailsDialogState();
}

class _OrderDetailsDialogState extends State<OrderDetailsDialog> {
  String get _permissionResource => widget.purchase ? 'purchases' : 'sales';
  String get _viewPermission =>
      widget.purchase ? 'purchases.view' : 'sales.view';
  String get _updatePermission =>
      widget.purchase ? 'purchases.update' : 'sales.update';

  Widget _fieldView(String field, Widget child) => FieldPermissionVisibility(
    resource: _permissionResource,
    field: field,
    viewPermission: _viewPermission,
    child: child,
  );

  Widget _fieldAction(String field, Widget child, {String? writePermission}) =>
      FieldPermissionControl(
        resource: _permissionResource,
        field: field,
        viewPermission: _viewPermission,
        writePermission: writePermission ?? _updatePermission,
        child: child,
      );

  final _money = NumberFormat('#,##0.##');
  final _detailsRepository = CommercialOrderDetailsRepository();
  final _documentRepository = DocumentManagementRepository();
  final _documentStorage = DocumentStorageRepository();
  final _pdfService = const EnterpriseDocumentPdfService();
  bool _printing = false;
  bool _exportingPdf = false;
  bool _loading = true;
  String? _loadError;
  Map<String, Object?>? _order;
  List<Map<String, Object?>> _items = const [];
  List<Map<String, Object?>> _logistics = const [];
  List<Map<String, Object?>> _invoices = const [];
  List<Map<String, Object?>> _payments = const [];
  List<Map<String, Object?>> _movements = const [];
  List<Map<String, Object?>> _journalEntries = const [];
  List<Map<String, Object?>> _auditTrail = const [];
  List<Map<String, Object?>> _documents = const [];
  bool _uploadingDocument = false;
  bool _documentsLoaded = false;
  bool _mutatingOrder = false;
  String? _mutatingComponentId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final firstLoad = _order == null;
    if (mounted) {
      setState(() {
        _loading = firstLoad;
        _loadError = null;
      });
    }
    try {
      final documentsFuture = _documentsLoaded
          ? Future<Object?>.value(_documents)
          : _documentRepository
                .search(
                  entityType: _orderEntityType,
                  entityId: widget.orderId,
                  limit: 200,
                )
                .catchError((Object error) {
                  AppLogger.debug(
                    'Order attachments could not be loaded: $error',
                  );
                  return <Map<String, Object?>>[];
                });
      final results = await Future.wait<Object?>(<Future<Object?>>[
        _detailsRepository.loadComplete(
          orderId: widget.orderId,
          purchase: widget.purchase,
        ),
        documentsFuture,
      ]);
      final details = results[0] as CommercialOrderDetails;
      final documents = (results[1] as List)
          .whereType<Map>()
          .map((row) => Map<String, Object?>.from(row))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _order = details.order;
        _items = details.items;
        _logistics = details.logistics;
        _invoices = details.invoices;
        _payments = details.payments;
        _movements = details.movements;
        _journalEntries = details.journalEntries;
        _auditTrail = _sortAuditTrail(details.auditTrail);
        _documents = documents;
        _documentsLoaded = true;
        _loading = false;
      });
    } catch (error) {
      AppLogger.debug('Order details could not be loaded: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = userFacingError(
          error,
          isArabic: context.l10n.isArabic,
          arabicFallback: 'تعذر تحميل تفاصيل الأمر.',
          englishFallback: 'Unable to load order details.',
        );
      });
    }
  }

  String _bi(String arabic, String english) =>
      context.l10n.isArabic ? arabic : english;

  Future<void> _editOrder() async {
    if (_mutatingOrder) return;
    final changed = await showAppModuleDialog<bool>(
      context: context,
      title: _bi(
        widget.purchase ? 'تعديل أمر الشراء' : 'تعديل أمر البيع',
        widget.purchase ? 'Edit purchase order' : 'Edit sales order',
      ),
      windowKey:
          '${widget.purchase ? 'purchase' : 'sales'}-order:edit:${widget.orderId}',
      maxWidth: 1040,
      maxHeight: 790,
      builder: (_) => widget.purchase
          ? PurchaseOrderDraftPage(orderId: widget.orderId)
          : SalesOrderDraftPage(orderId: widget.orderId),
    );
    if (changed != true || !mounted) return;
    setState(() {
      _mutatingOrder = true;
      _loading = true;
    });
    try {
      await _load();
      if (!mounted || _loadError != null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            _bi(
              'تم حفظ التعديل وتحديث جميع الارتباطات بنجاح.',
              'Changes saved and all linked records were refreshed.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _mutatingOrder = false);
    }
  }

  Future<void> _deleteOrder() async {
    if (_mutatingOrder) return;
    final permission = widget.purchase ? 'purchases.delete' : 'sales.delete';
    if (!await PermissionAction.require(context, permission)) return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(
          _bi(
            widget.purchase ? 'حذف أمر الشراء' : 'حذف أمر البيع',
            widget.purchase ? 'Delete purchase order' : 'Delete sales order',
          ),
        ),
        content: AppText(
          _bi(
            'سيتم عكس الفاتورة والحركة المخزنية ثم حذف الأمر وبنوده، دون إنشاء قيود تشغيلية إضافية تلقائيًا. تبقى الدفعات المالية في حساب العميل أو المورد كرصيد غير مخصص، وتُحتسب تلقائيًا عند تصديق فاتورة لاحقة للطرف نفسه وبالعملة نفسها، ولا تُحذف إلا من الصندوق.',
            'Invoice and inventory links will be reversed before deleting the order and lines; no additional operational journals are created automatically. Financial payments remain as an unapplied partner balance, are automatically considered for a later approved invoice of the same party and currency, and are deleted only from the cashbox.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: AppText(_bi('إلغاء', 'Cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_forever_outlined),
            label: AppText(
              _bi('حذف الأمر وارتباطاته', 'Delete order and links'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _mutatingOrder = true);
    try {
      if (widget.purchase) {
        await PurchaseWorkflowRepository().deleteOrderCascade(widget.orderId);
      } else {
        await SalesWorkflowRepository().deleteOrderCascade(widget.orderId);
      }
      if (!mounted) return;
      AppWorkspaceWindowScope.closeCurrent(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(
              error,
              isArabic: context.l10n.isArabic,
              arabicFallback: 'تعذر حذف الأمر لوجود بيانات مرتبطة به.',
              englishFallback:
                  'Unable to delete the order because linked records exist.',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _mutatingOrder = false);
    }
  }

  Map<String, Object?>? _activeDocument(List<Map<String, Object?>> documents) {
    for (final document in documents) {
      final status = document['status']?.toString().trim().toLowerCase() ?? '';
      final deleted =
          document['isDeleted'] == true ||
          document['is_deleted'] == true ||
          document['deletedAt'] != null ||
          document['deleted_at'] != null;
      if (!deleted &&
          !const <String>{
            'cancelled',
            'canceled',
            'voided',
            'deleted',
          }.contains(status)) {
        return document;
      }
    }
    return null;
  }

  double _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  Future<void> _runWorkflowOperation(Future<Object?> Function() task) async {
    if (_mutatingOrder || _mutatingComponentId != null) return;
    setState(() => _mutatingOrder = true);
    try {
      await task();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            _bi(
              'تم تنفيذ المرحلة وتحديث الأمر والارتباطات.',
              'The stage completed and all order links were refreshed.',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: AppText(
            userFacingError(
              error,
              isArabic: context.l10n.isArabic,
              arabicFallback:
                  'تعذر تنفيذ المرحلة. حدّث الأمر وتحقق من المستند المخزني ثم أعد المحاولة.',
              englishFallback:
                  'Unable to complete the stage. Refresh the order, verify the warehouse document, and try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _mutatingOrder = false);
    }
  }

  Future<void> _createLogisticsDraft() async {
    final contextData = widget.purchase
        ? await PurchaseWorkflowRepository().warehouseAllocationContext(
            widget.orderId,
          )
        : await SalesWorkflowRepository().warehouseAllocationContext(
            widget.orderId,
          );
    if (!mounted) return;
    final items = ((contextData['items'] as List?) ?? const <Object?>[])
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
    final warehouses =
        ((contextData['warehouses'] as List?) ?? const <Object?>[])
            .whereType<Map>()
            .map((row) => Map<String, Object?>.from(row))
            .toList(growable: false);
    if (items.isEmpty || warehouses.isEmpty) {
      throw StateError(
        _bi(
          'لا توجد بنود أو مخازن فعالة لإكمال المستند المخزني.',
          'No active items or warehouses are available for the warehouse document.',
        ),
      );
    }
    final allocations = await showWarehouseAllocationDialog(
      context: context,
      title: _bi(
        widget.purchase ? 'استلام متعدد المخازن' : 'تجهيز متعدد المخازن',
        widget.purchase
            ? 'Multi-warehouse receipt'
            : 'Multi-warehouse delivery',
      ),
      items: items,
      warehouses: warehouses,
      sales: !widget.purchase,
    );
    if (allocations == null || allocations.isEmpty || !mounted) return;
    await _runWorkflowOperation(
      () => widget.purchase
          ? PurchaseWorkflowRepository().createReceiptDraftMulti(
              orderId: widget.orderId,
              allocations: allocations,
            )
          : SalesWorkflowRepository().createDeliveryDraftMulti(
              orderId: widget.orderId,
              allocations: allocations,
            ),
    );
  }

  Future<void> _approveLogistics(String documentId) => _runWorkflowOperation(
    () => widget.purchase
        ? PurchaseWorkflowRepository().approveReceipt(documentId)
        : SalesWorkflowRepository().approveDelivery(documentId),
  );

  Future<void> _createInvoiceDraft() => _runWorkflowOperation(
    () => widget.purchase
        ? PurchaseWorkflowRepository().createInvoiceDraft(widget.orderId)
        : SalesWorkflowRepository().createInvoiceDraft(widget.orderId),
  );

  Future<void> _approveInvoice(String invoiceId) => _runWorkflowOperation(
    () => widget.purchase
        ? PurchaseWorkflowRepository().approveInvoice(invoiceId)
        : SalesWorkflowRepository().approveInvoice(invoiceId),
  );

  Future<void> _recordPayment(
    Map<String, Object?> order,
    Map<String, Object?> invoice,
  ) async {
    final invoiceId = invoice['id']?.toString().trim() ?? '';
    final currency = (order['currency']?.toString() ?? '').toUpperCase();
    final remaining = _number(
      invoice['remainingAmount'] ??
          invoice['invoiceRemaining'] ??
          (_number(invoice['total']) - _number(invoice['paidAmount'])),
    );
    if (invoiceId.isEmpty || currency.isEmpty || remaining <= .01) return;
    final results = widget.purchase
        ? await Future.wait([
            PurchaseWorkflowRepository().listCashAccounts(),
            PurchaseWorkflowRepository().listSettlementAccounts(),
          ])
        : await Future.wait([
            SalesWorkflowRepository().listCashAccounts(),
            SalesWorkflowRepository().listSettlementAccounts(),
          ]);
    final cashAccounts = results[0].toList(growable: false);
    final settlementAccounts = results[1].toList(growable: false);
    if (!mounted) return;
    if (cashAccounts.isEmpty) {
      throw StateError(
        _bi(
          'لا يوجد صندوق مالي فعال لتسجيل الدفعة.',
          'No active cashbox is available for this payment.',
        ),
      );
    }
    final drafts = await showInvoicePaymentBatchDialog(
      context: context,
      invoiceCurrency: currency,
      remainingAmount: remaining,
      cashAccounts: cashAccounts,
      settlementAccounts: settlementAccounts,
      purchase: widget.purchase,
    );
    if (drafts == null || drafts.isEmpty || !mounted) return;
    await _runWorkflowOperation(
      () => widget.purchase
          ? PurchaseWorkflowRepository().addInvoicePaymentsBatch(
              invoiceId,
              drafts.map((draft) => draft.toRpcJson()).toList(growable: false),
            )
          : SalesWorkflowRepository().addInvoicePaymentsBatch(
              invoiceId,
              drafts.map((draft) => draft.toRpcJson()).toList(growable: false),
            ),
    );
  }

  List<Widget> _workflowActionIcons(Map<String, Object?> order) {
    final orderStatus = order['status']?.toString().trim().toLowerCase() ?? '';
    final logistics = _activeDocument(_logistics);
    final invoice = _activeDocument(_invoices);
    final logisticsStatus =
        logistics?['status']?.toString().trim().toLowerCase() ?? '';
    final invoiceStatus =
        invoice?['status']?.toString().trim().toLowerCase() ?? '';
    final busy = _mutatingOrder || _mutatingComponentId != null;
    final actions = <Widget>[];

    if (const <String>{'draft', 'pending_approval'}.contains(orderStatus)) {
      actions.add(
        _fieldAction(
          'status',
          AppModuleActionIcon(
            tooltip: _bi(
              widget.purchase ? 'تصديق أمر الشراء' : 'تصديق أمر البيع',
              widget.purchase
                  ? 'Approve purchase order'
                  : 'Approve sales order',
            ),
            icon: Icons.verified_outlined,
            busy: busy,
            onPressed: busy ? null : _approveOrderComponent,
          ),
          writePermission: widget.purchase
              ? 'purchases.approve'
              : 'sales.approve',
        ),
      );
    } else if (orderStatus == 'approved' && logistics == null) {
      actions.add(
        _fieldAction(
          widget.purchase ? 'receipt' : 'delivery',
          AppModuleActionIcon(
            tooltip: _bi(
              widget.purchase
                  ? 'إنشاء إشعار الاستلام المخزني'
                  : 'إنشاء إذن التجهيز المخزني',
              widget.purchase
                  ? 'Create warehouse receipt'
                  : 'Create warehouse delivery',
            ),
            icon: widget.purchase
                ? Icons.call_received_rounded
                : Icons.local_shipping_outlined,
            busy: busy,
            onPressed: busy ? null : _createLogisticsDraft,
          ),
          writePermission: widget.purchase
              ? 'purchases.approve'
              : 'sales.approve',
        ),
      );
    } else if (logistics != null &&
        const <String>{'draft', 'pending_approval'}.contains(logisticsStatus)) {
      final documentId = logistics['id']?.toString() ?? '';
      actions.add(
        _fieldAction(
          widget.purchase ? 'receipt' : 'delivery',
          AppModuleActionIcon(
            tooltip: _bi(
              widget.purchase
                  ? 'تصديق الاستلام المخزني'
                  : 'تصديق التجهيز المخزني',
              widget.purchase
                  ? 'Approve warehouse receipt'
                  : 'Approve warehouse delivery',
            ),
            icon: Icons.inventory_rounded,
            busy: busy,
            onPressed: busy || documentId.isEmpty
                ? null
                : () => _approveLogistics(documentId),
          ),
          writePermission: widget.purchase
              ? 'purchases.approve'
              : 'sales.approve',
        ),
      );
    } else if (const <String>{
          'approved',
          'posted',
          'completed',
          'confirmed',
        }.contains(logisticsStatus) &&
        invoice == null) {
      actions.add(
        _fieldAction(
          'invoice',
          AppModuleActionIcon(
            tooltip: _bi(
              widget.purchase
                  ? 'إنشاء مسودة فاتورة شراء'
                  : 'إنشاء مسودة فاتورة بيع',
              widget.purchase
                  ? 'Create purchase invoice draft'
                  : 'Create sales invoice draft',
            ),
            icon: Icons.request_quote_outlined,
            busy: busy,
            onPressed: busy ? null : _createInvoiceDraft,
          ),
          writePermission: widget.purchase
              ? 'purchases.approve'
              : 'sales.approve',
        ),
      );
    } else if (invoice != null &&
        const <String>{'draft', 'pending_approval'}.contains(invoiceStatus)) {
      final invoiceId = invoice['id']?.toString() ?? '';
      actions.addAll(<Widget>[
        _fieldAction(
          'invoice',
          AppModuleActionIcon(
            tooltip: _bi(
              widget.purchase ? 'تصديق فاتورة الشراء' : 'تصديق فاتورة البيع',
              widget.purchase
                  ? 'Approve purchase invoice'
                  : 'Approve sales invoice',
            ),
            icon: Icons.fact_check_outlined,
            busy: busy,
            onPressed: busy || invoiceId.isEmpty
                ? null
                : () => _approveInvoice(invoiceId),
          ),
          writePermission: widget.purchase
              ? 'purchases.approve'
              : 'sales.approve',
        ),
        _fieldAction(
          'invoice',
          AppModuleActionIcon(
            tooltip: _bi(
              widget.purchase
                  ? 'حذف مسودة فاتورة الشراء'
                  : 'حذف مسودة فاتورة البيع',
              widget.purchase
                  ? 'Delete purchase invoice draft'
                  : 'Delete sales invoice draft',
            ),
            icon: Icons.delete_outline_rounded,
            busy: busy,
            onPressed: busy || invoiceId.isEmpty
                ? null
                : () => _manageComponent(
                    invoice,
                    componentType: 'invoice',
                    action: 'delete',
                  ),
          ),
          writePermission: _updatePermission,
        ),
      ]);
    } else if (invoice != null && invoiceStatus == 'approved') {
      final remaining = _number(
        invoice['remainingAmount'] ??
            (_number(invoice['total']) - _number(invoice['paidAmount'])),
      );
      if (remaining > .01) {
        actions.add(
          _fieldAction(
            'payments',
            AppModuleActionIcon(
              tooltip: _bi(
                widget.purchase ? 'تسجيل دفعة مورد' : 'تسجيل دفعة عميل',
                widget.purchase
                    ? 'Record supplier payment'
                    : 'Record customer payment',
              ),
              icon: Icons.payments_outlined,
              busy: busy,
              onPressed: busy ? null : () => _recordPayment(order, invoice),
            ),
            writePermission: 'cashbox.receipt',
          ),
        );
      }
    }
    return actions;
  }

  Future<void> _approveOrderComponent() async {
    final order = _order;
    if (order == null || _mutatingOrder) return;
    final status = order['status']?.toString().toLowerCase() ?? '';
    if (!const {'draft', 'pending_approval'}.contains(status)) return;
    await _manageComponent(
      <String, Object?>{'id': widget.orderId, 'status': status},
      componentType: 'order',
      action: 'approve',
    );
  }

  Future<void> _manageComponent(
    Map<String, Object?> row, {
    required String componentType,
    required String action,
  }) async {
    final id = row['id']?.toString().trim() ?? '';
    if (id.isEmpty || _mutatingComponentId != null) return;

    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: AppText(_bi('حذف مكوّن الأمر', 'Delete order component')),
          content: AppText(
            _bi(
              componentType == 'invoice'
                  ? 'سيتم حذف الفاتورة وعكس ارتباطاتها التشغيلية فقط. تبقى الدفعات كرصيد غير مخصص للطرف نفسه، ويُعاد احتساب الفرق المالي تلقائيًا عند تصديق فاتورة لاحقة بالعملة نفسها.'
                  : 'سيتم عكس الحركة المخزنية وحذف مستند التجهيز فقط، ثم إعادة احتساب حالة الأمر.',
              componentType == 'invoice'
                  ? 'Only the invoice and its accounting posting will be reversed. Payments remain as an unapplied balance for the same party and are automatically applied to a later approved invoice in the same currency.'
                  : 'Only this warehouse document will be reversed and deleted, then the order status will be recalculated.',
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
              label: AppText(_bi('حذف وعكس الارتباطات', 'Delete and reverse')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _mutatingComponentId = id);
    try {
      if (widget.purchase) {
        await PurchaseWorkflowRepository().manageOrderComponent(
          orderId: widget.orderId,
          componentType: componentType,
          componentId: id,
          action: action,
          reason: 'Order details component action',
        );
      } else {
        await SalesWorkflowRepository().manageOrderComponent(
          orderId: widget.orderId,
          componentType: componentType,
          componentId: id,
          action: action,
          reason: 'Order details component action',
        );
      }
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            _bi(
              action == 'approve'
                  ? 'تم تصديق الوحدة وتحديث جميع الارتباطات.'
                  : 'تم حذف الوحدة وعكس ارتباطاتها وتحديث حالة الأمر.',
              action == 'approve'
                  ? 'The component was approved and every link was refreshed.'
                  : 'The component was deleted, its links reversed, and the order status refreshed.',
            ),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: AppText(
            userFacingError(
              error,
              isArabic: context.l10n.isArabic,
              arabicFallback:
                  'تعذر تنفيذ العملية. احذف الوحدات اللاحقة أولًا أو حدّث الأمر ثم أعد المحاولة.',
              englishFallback:
                  'Unable to complete the action. Remove later components first or refresh the order and try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _mutatingComponentId = null);
    }
  }

  Widget _componentActions(
    Map<String, Object?> row, {
    required String componentType,
  }) {
    final id = row['id']?.toString() ?? '';
    final status = row['status']?.toString().toLowerCase() ?? '';
    final busy = _mutatingComponentId == id;
    final canApprove = const {'draft', 'pending_approval'}.contains(status);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: <Widget>[
        if (canApprove)
          _InlineComponentButton(
            label: _bi('تصديق', 'Approve'),
            icon: Icons.verified_outlined,
            busy: busy,
            onPressed: () => _manageComponent(
              row,
              componentType: componentType,
              action: 'approve',
            ),
          ),
        _InlineComponentButton(
          label: _bi('حذف', 'Delete'),
          icon: Icons.delete_outline_rounded,
          busy: busy,
          onPressed: () => _manageComponent(
            row,
            componentType: componentType,
            action: 'delete',
          ),
        ),
      ],
    );
  }

  Widget _paymentCashboxAction() => _InlineComponentButton(
    label: _bi('الحذف من الصندوق', 'Delete from cashbox'),
    icon: Icons.account_balance_wallet_outlined,
    onPressed: () =>
        AppModuleNavigation.open(context, AppRouteNames.accounting),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final loadError = _loadError;
    if (loadError != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 42),
                  const SizedBox(height: 12),
                  AppText(
                    _bi(
                      'تعذر تحميل تفاصيل الأمر والارتباطات.',
                      'Unable to load the order and linked records.',
                    ),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  AppSelectableText(loadError, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: AppText(_bi('إعادة المحاولة', 'Retry')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final order = _order;
    if (order == null) {
      return Center(child: AppText(_bi('الأمر غير موجود', 'Order not found')));
    }
    final unitField = widget.purchase ? 'unitCost' : 'unitPrice';
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: AppText(
            '${DocumentNomenclature.commercialOrder(purchase: widget.purchase, arabic: context.l10n.isArabic)} ${order['orderNumber']}',
          ),
          actions: <Widget>[
            ..._workflowActionIcons(order),
            AppModuleActionIcon(
              tooltip: _bi(
                'تعديل الأمر وحفظ الارتباطات',
                'Edit order and refresh links',
              ),
              icon: Icons.edit_outlined,
              onPressed: _mutatingOrder ? null : _editOrder,
            ),
            AppModuleActionIcon(
              tooltip: _bi(
                'حذف الأمر مع عكس الارتباطات',
                'Delete order and reverse links',
              ),
              icon: Icons.delete_outline_rounded,
              destructive: true,
              onPressed: _mutatingOrder ? null : _deleteOrder,
            ),
            AppModuleActionIcon(
              tooltip: _bi('تنزيل PDF', 'Download PDF'),
              icon: Icons.download_for_offline_outlined,
              busy: _exportingPdf,
              onPressed: _exportingPdf ? null : _exportPdf,
            ),
            AppModuleActionIcon(
              tooltip: _bi('تصدير وطباعة PDF', 'Export and print PDF'),
              icon: Icons.picture_as_pdf_outlined,
              busy: _printing,
              onPressed: _printing ? null : _printPdf,
            ),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: _bi('البيانات والبنود', 'Details & items')),
              Tab(
                text: DocumentNomenclature.warehouseStage(
                  purchase: widget.purchase,
                  arabic: context.l10n.isArabic,
                ),
              ),
              Tab(
                text: DocumentNomenclature.invoice(
                  purchase: widget.purchase,
                  arabic: context.l10n.isArabic,
                ),
              ),
              Tab(
                text: DocumentNomenclature.partnerPayment(
                  purchase: widget.purchase,
                  arabic: context.l10n.isArabic,
                ),
              ),
              Tab(text: _bi('الحركات', 'Movements')),
              Tab(text: _bi('سجل التدقيق', 'Audit trail')),
              Tab(text: _bi('المرفقات', 'Attachments')),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _summary(order),
                const SizedBox(height: 12),
                AppText(
                  _bi('البنود', 'Items'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ..._items.map(
                  (item) => Card(
                    child: ExpansionTile(
                      leading: Icon(
                        item['itemType'] == 'car'
                            ? Icons.directions_car
                            : Icons.inventory_2,
                      ),
                      title: AppText(item['description']?.toString() ?? '-'),
                      subtitle: AppText(
                        _bi(
                          'النوع: ${item['itemType']} • الكمية: ${item['quantity']} • السعر: ${_money.format((item[unitField] as num?)?.toDouble() ?? 0)} • الإجمالي: ${_money.format((item['lineTotal'] as num?)?.toDouble() ?? 0)} ${order['currency']}',
                          'Type: ${item['itemType']} • Quantity: ${item['quantity']} • Price: ${_money.format((item[unitField] as num?)?.toDouble() ?? 0)} • Total: ${_money.format((item['lineTotal'] as num?)?.toDouble() ?? 0)} ${order['currency']}',
                        ),
                      ),
                      children: [_itemDetails(item)],
                    ),
                  ),
                ),
              ],
            ),
            _fieldView(
              widget.purchase ? 'receipt' : 'delivery',
              _records(
                _logistics,
                (row) =>
                    '${row['receiptNumber'] ?? row['deliveryNumber']} — ${row['warehouseName'] ?? _bi('بدون مخزن', 'No warehouse')}',
                (row) => _bi(
                  'الحالة: ${row['status']} • التاريخ: ${row['receiptDate'] ?? row['deliveryDate']}',
                  'Status: ${row['status']} • Date: ${row['receiptDate'] ?? row['deliveryDate']}',
                ),
                trailing: (row) =>
                    _componentActions(row, componentType: 'logistics'),
              ),
            ),
            _fieldView(
              'invoice',
              _records(
                _invoices,
                (row) =>
                    '${row['invoiceNumber']} — ${_money.format((row['total'] as num?)?.toDouble() ?? 0)} ${row['currency']}',
                (row) => _bi(
                  'الحالة: ${row['status']} • المدفوع: ${_money.format((row['paidAmount'] as num?)?.toDouble() ?? 0)} • المتبقي: ${_money.format((row['remainingAmount'] as num?)?.toDouble() ?? 0)}',
                  'Status: ${row['status']} • Paid: ${_money.format((row['paidAmount'] as num?)?.toDouble() ?? 0)} • Remaining: ${_money.format((row['remainingAmount'] as num?)?.toDouble() ?? 0)}',
                ),
                trailing: (row) =>
                    _componentActions(row, componentType: 'invoice'),
              ),
            ),
            _fieldView(
              'payments',
              _records(
                _payments,
                (row) =>
                    '${row['cashAccountName'] ?? _bi('صندوق', 'Cash account')} — ${_money.format((row['cashAmount'] as num?)?.toDouble() ?? 0)} ${row['paymentCurrency']}',
                (row) {
                  final settlementMode = row['settlementMode']?.toString();
                  final mode = switch (settlementMode) {
                    'settlement' => _bi(
                      'دفعة تسوية محاسبية',
                      'Accounting settlement payment',
                    ),
                    'full' || 'full_fx' => _bi('دفعة كلية', 'Full payment'),
                    _ => _bi('دفعة جزئية', 'Partial payment'),
                  };
                  final difference =
                      (row['exchangeDifference'] as num?)?.toDouble() ?? 0;
                  final differenceText = difference.abs() <= 0.01
                      ? _bi('بدون فرق صرف', 'No exchange difference')
                      : difference > 0
                      ? _bi(
                          'فرق صرف دائن: ${_money.format(difference)}',
                          'Credit exchange difference: ${_money.format(difference)}',
                        )
                      : _bi(
                          'فرق صرف مدين: ${_money.format(difference.abs())}',
                          'Debit exchange difference: ${_money.format(difference.abs())}',
                        );
                  return _bi(
                    'مبلغ الفاتورة: ${_money.format((row['invoiceAmount'] as num?)?.toDouble() ?? 0)} • $mode • $differenceText • التاريخ: ${row['paymentDate']}',
                    'Invoice amount: ${_money.format((row['invoiceAmount'] as num?)?.toDouble() ?? 0)} • $mode • $differenceText • Date: ${row['paymentDate']}',
                  );
                },
                trailing: (_) => _paymentCashboxAction(),
              ),
            ),
            _fieldView(
              'accounting',
              _records(
                _movements,
                (row) =>
                    '${row['movementNumber']} — ${row['productName'] ?? row['referenceType']}',
                (row) => _bi(
                  'المخزن: ${row['warehouseName'] ?? '-'} • الكمية: ${row['quantity']} • النوع: ${row['movementType']}',
                  'Warehouse: ${row['warehouseName'] ?? '-'} • Quantity: ${row['quantity']} • Type: ${row['movementType']}',
                ),
              ),
            ),
            _records(
              _auditTrail,
              (row) =>
                  '${row['documentNumber'] ?? '-'} — ${_actionLabel(row['action']?.toString())}',
              (row) => _bi(
                'الحالة: ${_statusLabel(row['fromStatus']?.toString())} ← ${_statusLabel(row['toStatus']?.toString())} • المنفذ: ${row['performedBy'] ?? 'النظام'} • التاريخ: ${row['performedAt'] ?? '-'}${row['reason'] == null ? '' : ' • السبب: ${row['reason']}'}',
                'Status: ${_statusLabel(row['fromStatus']?.toString())} → ${_statusLabel(row['toStatus']?.toString())} • Performed by: ${row['performedBy'] ?? 'System'} • Date: ${row['performedAt'] ?? '-'}${row['reason'] == null ? '' : ' • Reason: ${row['reason']}'}',
              ),
            ),
            _attachmentsTab(_orderEntityType),
          ],
        ),
      ),
    );
  }

  Future<void> _exportPdf() async {
    final order = _order;
    if (order == null || _exportingPdf) return;
    setState(() => _exportingPdf = true);
    try {
      final bytes = await _pdfService.build(
        purchase: widget.purchase,
        language: Localizations.localeOf(context).languageCode,
        order: order,
        items: _items,
        logistics: _logistics,
        invoices: _invoices,
        payments: _payments,
        movements: _movements,
        journalEntries: _journalEntries,
        auditTrail: _auditTrail,
      );
      final rawNumber = (order['orderNumber'] ?? 'document').toString();
      final safeNumber = rawNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      await BinaryDownloadService.save(
        fileName: '${widget.purchase ? 'purchase' : 'sales'}_$safeNumber.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            context.l10n.isArabic
                ? 'تم تصدير ملف PDF بنجاح.'
                : 'PDF exported successfully.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(
              error,
              isArabic: context.l10n.isArabic,
              arabicFallback: 'تعذر تصدير ملف PDF.',
              englishFallback: 'Unable to export PDF.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _printPdf() async {
    final order = _order;
    if (order == null || _printing) return;
    setState(() => _printing = true);
    try {
      await _pdfService.printDocument(
        purchase: widget.purchase,
        language: Localizations.localeOf(context).languageCode,
        order: order,
        items: _items,
        logistics: _logistics,
        invoices: _invoices,
        payments: _payments,
        movements: _movements,
        journalEntries: _journalEntries,
        auditTrail: _auditTrail,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(
              error,
              isArabic: context.l10n.isArabic,
              arabicFallback: 'تعذر إنشاء ملف PDF.',
              englishFallback: 'Unable to generate PDF.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  String get _orderEntityType =>
      widget.purchase ? 'purchase_orders_cloud' : 'sales_orders_cloud';

  Widget _attachmentsTab(String orderTable) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: AppText(
                  _bi(
                    'المرفقات المرتبطة بالأمر (${_documents.length})',
                    'Order attachments (${_documents.length})',
                  ),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _uploadingDocument
                    ? null
                    : () => _uploadDocument(orderTable),
                icon: _uploadingDocument
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.attach_file),
                label: AppText(_bi('إضافة مرفق', 'Add attachment')),
              ),
            ],
          ),
        ),
        Expanded(
          child: _documents.isEmpty
              ? Center(
                  child: AppText(
                    _bi(
                      'لا توجد مرفقات مرتبطة بهذا الأمر',
                      'No attachments are linked to this order',
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: _documents.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final document = _documents[index];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.description_outlined),
                        ),
                        title: AppText(
                          '${document['documentNumber'] ?? '-'} • ${document['titleAr'] ?? document['fileName'] ?? 'مرفق'}',
                        ),
                        subtitle: AppText(
                          _bi(
                            '${document['fileName'] ?? '-'} • الإصدار ${document['currentVersion'] ?? 1} • ${_formatBytes((document['fileSize'] as num?)?.toInt() ?? 0)}',
                            '${document['fileName'] ?? '-'} • Version ${document['currentVersion'] ?? 1} • ${_formatBytes((document['fileSize'] as num?)?.toInt() ?? 0)}',
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: AppTranslation.translate('تنزيل'),
                          onPressed: () => _downloadDocument(document),
                          icon: const Icon(Icons.download_outlined),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _uploadDocument(String orderTable) async {
    if (!await PermissionAction.require(context, _updatePermission)) return;
    if (!mounted) return;
    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.single.bytes == null) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            _bi(
              'تعذر قراءة الملف المحدد.',
              'Unable to read the selected file.',
            ),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _uploadingDocument = true);
    try {
      final documentId = await _documentRepository.createDocument(
        EnterpriseDocumentCreateInput(
          documentNumber: 'ATT-${DateTime.now().millisecondsSinceEpoch}',
          titleAr: file.name,
          fileName: file.name,
          mimeType: _mimeType(file.extension),
          storagePath: 'database://document_blobs',
          checksumSha256: sha256.convert(bytes).toString(),
          fileSize: bytes.length,
          createdBy: 'current-user',
          metadata: {
            'sourceTable': orderTable,
            'sourceId': widget.orderId,
            'sourceType': widget.purchase ? 'purchase_order' : 'sales_order',
          },
        ),
      );
      final document = await _documentRepository.getDocument(documentId);
      if (document == null || document['versionId'] == null) {
        throw StateError(
          _bi(
            'تعذر إنشاء إصدار المرفق.',
            'Unable to create the attachment version.',
          ),
        );
      }
      await _documentStorage.store(
        documentId: documentId,
        versionId:
            document['versionId']?.toString() ??
            (throw StateError(
              _bi(
                'إصدار المرفق غير متاح.',
                'The attachment version is unavailable.',
              ),
            )),
        bytes: bytes,
      );
      await _documentRepository.linkEntity(
        documentId: documentId,
        entityType: orderTable,
        entityId: widget.orderId,
        relationshipType: 'attachment',
        metadata: {'orderType': widget.purchase ? 'purchase' : 'sales'},
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(
              error,
              isArabic: context.l10n.isArabic,
              arabicFallback: 'تعذر إضافة المرفق.',
              englishFallback: 'Unable to add attachment.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingDocument = false);
    }
  }

  Future<void> _downloadDocument(Map<String, Object?> document) async {
    final documentId = document['id']?.toString();
    if (documentId == null) return;
    final bytes = await _documentStorage.readCurrent(documentId);
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            _bi('بيانات الملف غير متوفرة.', 'File data is unavailable.'),
          ),
        ),
      );
      return;
    }
    final fileName = (document['fileName'] ?? 'attachment').toString();
    final dot = fileName.lastIndexOf('.');
    await FileSaver.instance.saveFile(
      name: dot > 0 ? fileName.substring(0, dot) : fileName,
      bytes: Uint8List.fromList(bytes),
      ext: dot > 0 ? fileName.substring(dot + 1) : 'bin',
      mimeType: MimeType.other,
    );
  }

  String _mimeType(String? extension) => switch ((extension ?? '')
      .toLowerCase()) {
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'txt' => 'text/plain',
    'csv' => 'text/csv',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    _ => 'application/octet-stream',
  };

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  List<Map<String, Object?>> _sortAuditTrail(List<Map<String, Object?>> rows) {
    final sorted = List<Map<String, Object?>>.of(rows);
    sorted.sort((a, b) {
      final aDate = DateTime.tryParse(a['performedAt']?.toString() ?? '');
      final bDate = DateTime.tryParse(b['performedAt']?.toString() ?? '');
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return aDate.compareTo(bDate);
    });
    return sorted;
  }

  String _actionLabel(String? action) => switch (action) {
    'create' => _bi('إنشاء', 'Create'),
    'approve_sales_order' ||
    'approve_purchase_order' => _bi('تصديق الأمر', 'Approve order'),
    'approve_sales_delivery' => _bi(
      'تصديق إذن التجهيز',
      'Approve delivery note',
    ),
    'approve_purchase_receipt' => _bi(
      'تصديق إشعار الاستلام',
      'Approve goods receipt',
    ),
    'approve_sales_invoice' ||
    'approve_purchase_invoice' => _bi('تصديق الفاتورة', 'Approve invoice'),
    'cancel_sales_invoice' ||
    'cancel_purchase_invoice' => _bi('إلغاء الفاتورة', 'Cancel invoice'),
    'cancel_sales_delivery' || 'cancel_purchase_receipt' => _bi(
      'إلغاء الحركة المخزنية',
      'Cancel inventory posting',
    ),
    'update_with_links' || 'edit_order_with_links' => _bi(
      'تعديل مع تحديث الارتباطات',
      'Edit and refresh links',
    ),
    'delete_with_links' || 'delete_order_cascade' => _bi(
      'حذف مع عكس الارتباطات',
      'Delete and reverse links',
    ),
    _ => action ?? '-',
  };

  String _statusLabel(String? status) => switch (status) {
    null || '' => _bi('بداية', 'Start'),
    'draft' => _bi('مسودة', 'Draft'),
    'pending_approval' => _bi('بانتظار التصديق', 'Pending approval'),
    'approved' => _bi('مصدق', 'Approved'),
    'posted' => _bi('مرحل', 'Posted'),
    'confirmed' => _bi('مؤكد', 'Confirmed'),
    'partially_executed' => _bi('منفذ جزئيًا', 'Partially executed'),
    'completed' => _bi('مكتمل', 'Completed'),
    'cancelled' => _bi('ملغي', 'Cancelled'),
    'reversed' => _bi('معكوس', 'Reversed'),
    'closed' => _bi('مغلق', 'Closed'),
    _ => status,
  };

  Widget _itemDetails(Map<String, Object?> item) {
    final isCar = item['itemType'] == 'car';
    final details = isCar
        ? <(String, Object?)>[
            (_bi('الماركة', 'Brand'), item['detail_brand']),
            (_bi('الموديل', 'Model'), item['detail_model']),
            (_bi('سنة الصنع', 'Model year'), item['detail_year']),
            (_bi('اللون', 'Color'), item['detail_color']),
            (_bi('رقم الشاصي', 'Chassis number'), item['detail_chassis']),
            (_bi('رقم اللوحة', 'Plate number'), item['detail_plateNumber']),
            (_bi('الحالة', 'Status'), item['detail_status']),
            (
              _bi('المخزن الحالي', 'Current warehouse'),
              item['detail_warehouseName'],
            ),
            (_bi('سعر الشراء', 'Purchase price'), item['detail_purchasePrice']),
            (_bi('سعر البيع', 'Sale price'), item['detail_salePrice']),
            (
              _bi('تكلفة الصيانة', 'Maintenance cost'),
              item['detail_maintenanceCost'],
            ),
          ]
        : <(String, Object?)>[
            (_bi('الرمز', 'Code'), item['detail_code']),
            (_bi('الاسم', 'Name'), item['detail_name']),
            (_bi('الوحدة', 'Unit'), item['detail_unit']),
            (_bi('المجموعة', 'Category'), item['detail_category']),
            (_bi('المخزن', 'Warehouse'), item['detail_warehouseName']),
            (
              _bi('الكمية المتوفرة', 'Available quantity'),
              item['detail_availableQuantity'],
            ),
            (_bi('الكلفة', 'Cost'), item['detail_averageUnitCost']),
            (_bi('سعر البيع', 'Sale price'), item['detail_salePrice']),
            (
              _bi('الحد الأدنى', 'Minimum quantity'),
              item['detail_minimumQuantity'],
            ),
          ];
    final raw = item['details'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final key = entry.key.toString();
        if (details.any((field) => field.$1 == key)) continue;
        details.add((_humanize(key), entry.value));
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Wrap(
        spacing: 24,
        runSpacing: 10,
        children: details
            .where(
              (detail) =>
                  detail.$2 != null && detail.$2.toString().trim().isNotEmpty,
            )
            .map((detail) {
              final warehouseLabel =
                  detail.$1 == _bi('المخزن الحالي', 'Current warehouse') ||
                  detail.$1 == _bi('المخزن', 'Warehouse');
              return _fieldView(
                warehouseLabel ? 'itemWarehouse' : 'items',
                _premiumField(detail.$1, detail.$2 ?? '-'),
              );
            })
            .toList(),
      ),
    );
  }

  Widget _summary(Map<String, Object?> order) {
    final partnerField = widget.purchase ? 'supplierName' : 'customerName';
    final fields = <(String, String, Object?)>[
      (
        partnerField,
        _bi('الطرف التجاري', 'Business partner'),
        order['partnerName'],
      ),
      (
        'status',
        _bi('الحالة', 'Status'),
        _statusLabel(order['status']?.toString()),
      ),
      ('currencyCode', _bi('العملة', 'Currency'), order['currency']),
      (
        'subtotal',
        _bi('المجموع الفرعي', 'Subtotal'),
        _money.format((order['subtotal'] as num?)?.toDouble() ?? 0),
      ),
      (
        'discount',
        _bi('الخصم', 'Discount'),
        _money.format((order['discount'] as num?)?.toDouble() ?? 0),
      ),
      (
        'total',
        _bi('الإجمالي', 'Total'),
        _money.format((order['total'] as num?)?.toDouble() ?? 0),
      ),
      (
        'operationalDate',
        _bi('التاريخ والوقت التشغيلي', 'Operational date and time'),
        order['effectiveAt'] ?? order['operationalDateTime'] ?? '-',
      ),
      ('createdAt', _bi('تاريخ الإنشاء', 'Created at'), order['createdAt']),
      if ((order['updatedAt'] ?? '').toString().trim().isNotEmpty)
        ('updatedAt', _bi('تاريخ آخر تحديث', 'Updated at'), order['updatedAt']),
      (
        'status',
        _bi('تاريخ التصديق', 'Approved at'),
        order['approvedAt'] ?? '-',
      ),
      ('notes', _bi('الملاحظات', 'Notes'), order['notes'] ?? '-'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1040
            ? 3
            : constraints.maxWidth >= 680
            ? 2
            : 1;
        final spacing = 12.0;
        final fieldWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - spacing * (columns - 1)) / columns;
        final brightness = Theme.of(context).brightness;
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: KajDesignTokens.surfaceGradient(brightness),
            borderRadius: BorderRadius.circular(KajDesignTokens.radiusLg),
            border: Border.all(color: KajDesignTokens.border(brightness)),
            boxShadow: KajDesignTokens.softShadow(brightness),
          ),
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: fields
                .map(
                  (field) => _fieldView(
                    field.$1,
                    SizedBox(
                      width: fieldWidth,
                      child: _premiumField(field.$2, field.$3),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
    );
  }

  String _detailLabel(String key) => switch (key) {
    'id' => _bi('المعرف', 'ID'),
    'status' => _bi('الحالة', 'Status'),
    'documentNumber' => _bi('رقم المستند', 'Document number'),
    'warehouseName' => _bi('المخزن', 'Warehouse'),
    'sourceName' => _bi('من', 'From'),
    'destinationName' => _bi('إلى', 'To'),
    'performedBy' => _bi('المنفذ', 'Performed by'),
    'approvedBy' => _bi('المصدق', 'Approved by'),
    'approvedAt' => _bi('وقت التصديق', 'Approved at'),
    'createdAt' => _bi('تاريخ الإنشاء', 'Created at'),
    'updatedAt' => _bi('آخر تحديث', 'Updated at'),
    'effectiveAt' => _bi('التاريخ التشغيلي', 'Operational date'),
    'transactionDate' => _bi('تاريخ الحركة', 'Transaction date'),
    'quantity' => _bi('الكمية', 'Quantity'),
    'amount' => _bi('المبلغ', 'Amount'),
    'currency' => _bi('العملة', 'Currency'),
    'voucherNumber' => _bi('رقم السند', 'Voucher number'),
    'cashAccountName' => _bi('الصندوق', 'Cashbox'),
    'referenceDocumentNumber' => _bi('المرجع', 'Reference'),
    _ => _humanize(key),
  };

  String _humanize(String value) {
    final spaced = value
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll('_', ' ')
        .trim();
    if (spaced.isEmpty) return value;
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  Widget _premiumField(String label, Object? value) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(KajDesignTokens.radiusMd),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          AppText(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          AppSelectableText(
            _displayValue(value),
            maxLines: 2,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  String _displayValue(Object? value) {
    if (value == null) return '-';
    if (value is Map || value is List) {
      return _bi('بيانات مرتبطة', 'Linked data');
    }
    return value.toString();
  }

  Widget _recordDetails(Map<String, Object?> row) {
    final flattened = <(String, Object?)>[];
    const hiddenTechnicalKeys = <String>{
      'rawData',
      'raw_data',
      'recordMeta',
      'invoiceRawData',
      'inventorySnapshot',
      'sourceSnapshot',
    };

    void addMap(Map source, {String prefix = ''}) {
      for (final entry in source.entries) {
        final key = entry.key.toString();
        if (hiddenTechnicalKeys.contains(key)) continue;
        final value = entry.value;
        if (value == null || value.toString().trim().isEmpty) continue;
        final current = _detailLabel(key);
        final label = prefix.isEmpty ? current : '$prefix / $current';

        if (value is Map) {
          addMap(
            value,
            prefix: key == 'payload' || key == 'invoicePayload'
                ? prefix
                : label,
          );
          continue;
        }
        if (value is List) {
          if (value.isEmpty) continue;
          final text = value
              .map((element) {
                if (element is! Map) return element.toString();
                return element.entries
                    .where(
                      (entry) =>
                          !hiddenTechnicalKeys.contains(entry.key.toString()),
                    )
                    .map(
                      (entry) =>
                          '${_detailLabel(entry.key.toString())}: ${entry.value}',
                    )
                    .join(' • ');
              })
              .where((text) => text.trim().isNotEmpty)
              .join(' | ');
          if (text.isNotEmpty) flattened.add((label, text));
          continue;
        }
        flattened.add((label, value));
      }
    }

    addMap(row);
    if (flattened.isEmpty) {
      return AppText(_bi('لا توجد تفاصيل إضافية.', 'No additional details.'));
    }
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: flattened
          .map(
            (entry) => ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 180, maxWidth: 360),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: .35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AppText(
                        entry.$1,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 3),
                      AppSelectableText(
                        _displayValue(entry.$2),
                        maxLines: 5,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  Widget _records(
    List<Map<String, Object?>> rows,
    String Function(Map<String, Object?>) title,
    String Function(Map<String, Object?>) subtitle, {
    Widget Function(Map<String, Object?>)? trailing,
  }) {
    if (rows.isEmpty) {
      return Center(
        child: AppText(_bi('لا توجد بيانات مرتبطة', 'No linked data')),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      itemBuilder: (_, index) {
        final row = rows[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 2,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            title: AppText(
              title(row),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: AppText(
              subtitle(row),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: trailing == null
                ? null
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 250),
                    child: trailing(row),
                  ),
            children: <Widget>[_recordDetails(row)],
          ),
        );
      },
    );
  }
}

class _InlineComponentButton extends StatelessWidget {
  const _InlineComponentButton({
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
