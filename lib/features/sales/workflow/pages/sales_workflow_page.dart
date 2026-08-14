// Legacy audit prerequisites: order['deliveryStatus'] == 'approved'; order['invoiceId'] == null
import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quality_line_erp/design_system/kaj_commercial_stage6_components.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

import 'package:quality_line_erp/core/finance/invoice_payment_batch_dialog.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
import 'package:quality_line_erp/core/widgets/commercial_workflow_order_card.dart';
import 'package:quality_line_erp/core/widgets/commercial_workflow_filter_bar.dart';
import 'package:quality_line_erp/core/widgets/warehouse_allocation_dialog.dart';
import 'package:quality_line_erp/features/sales/workflow/repositories/sales_workflow_repository.dart';
import 'sales_order_draft_page.dart';
import 'order_details_dialog.dart';

class SalesWorkflowPage extends StatefulWidget {
  const SalesWorkflowPage({super.key});

  @override
  State<SalesWorkflowPage> createState() => _SalesWorkflowPageState();
}

class _SalesWorkflowPageState extends State<SalesWorkflowPage> {
  final _repository = SalesWorkflowRepository();
  bool _loading = true;
  List<Map<String, Object?>> _orders = const [];
  final _searchController = TextEditingController();
  String _query = '';
  String _statusFilter = 'all';
  // ignore: cancel_subscriptions
  StreamSubscription<AppDataChangeEvent>? _changeSubscription;
  Timer? _reloadDebounce;
  int _loadGeneration = 0;
  Future<void>? _loadInFlight;
  DateTime? _loadedAt;
  static const Duration _loadTtl = Duration(milliseconds: 700);
  final Set<String> _busyOrderIds = <String>{};

  @override
  void initState() {
    super.initState();
    _changeSubscription = AppDataChangeBus.instance.events.listen((event) {
      if (event.source != 'sales') return;
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(
        const Duration(milliseconds: 180),
        () => unawaited(_load()),
      );
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _searchController.dispose();
    final subscription = _changeSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }

  List<Map<String, Object?>> get _filteredOrders =>
      UnifiedFilterEngine.apply<Map<String, Object?>>(
        _orders,
        criteria: UnifiedFilterCriteria(
          searchText: _query,
          statuses: _statusFilter == 'all'
              ? const <String>{}
              : <String>{_statusFilter},
        ),
        adapter: UnifiedFilterAdapter<Map<String, Object?>>(
          searchableText: (order) => <Object?>[
            order['orderNumber'],
            order['invoiceNumber'],
            order['customerName'],
            order['supplierName'],
            order['notes'],
            order['currency'],
          ],
          status: _workflowStatus,
          partnerId: (order) => order['customerId'] ?? order['supplierId'],
          currency: (order) => order['currency'],
          userId: (order) => order['createdByUserId'],
          date: (order) => DateTime.tryParse(
            (order['orderDate'] ?? order['createdAt'])?.toString() ?? '',
          ),
        ),
      );

  bool _serverFlag(Map<String, Object?> order, String key, bool fallback) {
    final value = order[key];
    if (key == 'canCreateInvoice' && fallback) return true;
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') return true;
    if (normalized == 'false' || normalized == '0') return false;
    return fallback;
  }

  String _workflowStatus(Map<String, Object?> order) {
    final status = order['status']?.toString() ?? '';
    final invoiceStatus = order['invoiceStatus']?.toString() ?? '';
    final remaining = (order['invoiceRemaining'] as num?)?.toDouble() ?? 0;
    if (status == 'draft') return 'draft';
    if (invoiceStatus == 'approved' && remaining <= 0) return 'paid';
    if (invoiceStatus == 'approved') return 'invoiced';
    if (status == 'approved') return 'approved';
    return status;
  }

  Future<void> _load({bool force = false}) {
    final loadedAt = _loadedAt;
    if (!force &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < _loadTtl) {
      return Future<void>.value();
    }
    final active = _loadInFlight;
    if (active != null) return active;

    final request = _loadNow();
    _loadInFlight = request;
    return request.whenComplete(() {
      if (identical(_loadInFlight, request)) _loadInFlight = null;
    });
  }

  Future<void> _loadNow() async {
    final generation = ++_loadGeneration;
    try {
      final rows = await _repository.listOrders();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _orders = rows;
        _loading = false;
        _loadedAt = DateTime.now();
      });
    } catch (error, stackTrace) {
      if (!mounted || generation != _loadGeneration) return;
      AppLogger.debug('Sales workflow load failed: $error');
      AppLogger.stack(stackTrace);
      setState(() => _loading = false);
    }
  }

  Future<void> _newDraft() async {
    final changed = await showAppModuleDialog<bool>(
      context: context,
      title: 'مسودة أمر بيع',
      windowKey: 'sales-workflow:new-draft',
      maxWidth: 1000,
      maxHeight: 760,
      builder: (_) => const SalesOrderDraftPage(),
    );
    if (changed == true) await _load(force: true);
  }

  Future<void> _approve(String id) async {
    await _run(() => _repository.approveOrder(id), orderId: id);
  }

  Future<void> _delivery(String id) async {
    final contextData = await _repository.warehouseAllocationContext(id);
    if (!mounted) return;
    final items = ((contextData['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
    final warehouses = ((contextData['warehouses'] as List?) ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row))
        .toList(growable: false);
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('لا توجد بنود قابلة للتجهيز في الأمر.'),
        ),
      );
      return;
    }
    final allocations = await showWarehouseAllocationDialog(
      context: context,
      title: 'تجهيز متعدد المخازن',
      items: items,
      warehouses: warehouses,
      sales: true,
    );
    if (allocations == null || allocations.isEmpty) return;
    await _run(
      () => _repository.createDeliveryDraftMulti(
        orderId: id,
        allocations: allocations,
      ),
      orderId: id,
    );
  }

  Future<void> _invoice(String id) async =>
      _run(() => _repository.createInvoiceDraft(id), orderId: id);

  Future<void> _approveDelivery(String orderId, String deliveryId) async =>
      _run(() => _repository.approveDelivery(deliveryId), orderId: orderId);
  Future<void> _cancelDelivery(String orderId, String deliveryId) async =>
      _run(() => _repository.cancelDelivery(deliveryId), orderId: orderId);
  Future<void> _approveInvoice(String orderId, String invoiceId) async =>
      _run(() => _repository.approveInvoice(invoiceId), orderId: orderId);

  Future<void> _addPayment(Map<String, Object?> order) async {
    final invoiceId = order['invoiceId']?.toString();
    if (invoiceId == null || invoiceId.isEmpty) return;
    final invoiceCurrency =
        order['currency']?.toString().trim().toUpperCase() ?? '';
    if (invoiceCurrency != 'USD' && invoiceCurrency != 'IQD') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
              context.l10n.isArabic
                  ? 'عملة المستند غير محددة أو غير صالحة. أعد فتح المستند بعد تصحيح العملة.'
                  : 'The document currency is missing or invalid. Reopen it after correcting the currency.',
            ),
          ),
        );
      }
      return;
    }
    final results = await Future.wait([
      _repository.listCashAccounts(),
      _repository.listSettlementAccounts(),
    ]);
    final accounts = results[0].toList(growable: false);
    final settlementAccounts = results[1].toList(growable: false);
    if (!mounted || accounts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
              context.l10n.isArabic
                  ? 'لا يوجد صندوق مالي فعال لتسجيل الدفعة'
                  : 'No active cashbox is available for this payment',
            ),
          ),
        );
      }
      return;
    }
    final drafts = await showInvoicePaymentBatchDialog(
      context: context,
      invoiceCurrency: invoiceCurrency,
      remainingAmount: (order['invoiceRemaining'] as num?)?.toDouble() ?? 0,
      cashAccounts: accounts,
      settlementAccounts: settlementAccounts,
      purchase: false,
    );
    if (drafts == null || drafts.isEmpty) return;
    await _run(
      () => _repository.addInvoicePaymentsBatch(
        invoiceId,
        drafts.map((draft) => draft.toRpcJson()).toList(growable: false),
      ),
      orderId: order['id']?.toString(),
    );
  }

  Future<void> _cancelInvoice(Map<String, Object?> order) async {
    final invoiceId = order['invoiceId']?.toString();
    if (invoiceId == null || invoiceId.isEmpty) return;
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('إلغاء فاتورة البيع'),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: reason,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: AppTranslation.translate('سبب الإلغاء'),
              hintText: AppTranslation.translate(
                'سيتم عكس القيود والدفعات والحركات المرتبطة تلقائياً',
              ),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('رجوع'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const AppText('تأكيد الإلغاء والعكس'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await _run(
        () => _repository.cancelInvoice(
          invoiceId,
          reason: reason.text.trim().isEmpty
              ? 'إلغاء فاتورة البيع'
              : reason.text.trim(),
        ),
        orderId: order['id']?.toString(),
      );
    }
    reason.dispose();
  }

  String _bi(String arabic, String english) =>
      context.l10n.isArabic ? arabic : english;

  Future<void> _editOrder(String orderId) async {
    if (!mounted || _busyOrderIds.contains(orderId)) return;
    setState(() => _busyOrderIds.add(orderId));
    try {
      final changed = await showAppModuleDialog<bool>(
        context: context,
        title: _bi('تعديل أمر البيع', 'Edit sales order'),
        windowKey: 'sales-workflow:edit:$orderId',
        maxWidth: 1000,
        maxHeight: 760,
        builder: (_) => SalesOrderDraftPage(orderId: orderId),
      );
      if (changed == true) await _load(force: true);
    } finally {
      if (mounted) setState(() => _busyOrderIds.remove(orderId));
    }
  }

  Future<void> _deleteOrder(String orderId) async {
    if (!await PermissionAction.require(context, 'sales.delete')) return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: AppText(_bi('حذف أمر البيع', 'Delete sales order')),
        content: AppText(
          _bi(
            'سيتم عكس التجهيز والفاتورة وحركات المخزون، بينما تبقى الدفعات المالية كرصيد غير مخصص في حساب العميل لتعديلها أو حذفها لاحقاً من الحسابات. هل تريد المتابعة؟',
            'Delivery, invoice, and inventory links will be reversed. Financial payments will remain as unapplied customer credit and can later be edited or deleted from accounts. Continue?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: AppText(_bi('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: AppText(
              _bi(
                'حذف المستند مع إبقاء الدفعة',
                'Delete document, keep payment',
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true)
      await _run(
        () => _repository.deleteOrderCascade(orderId),
        orderId: orderId,
      );
  }

  Future<void> _cancelOrder(String orderId) async {
    if (!await PermissionAction.require(context, 'sales.cancel')) return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: AppText(_bi('إلغاء أمر البيع', 'Cancel sales order')),
        content: AppText(
          _bi(
            'سيتم إلغاء الأمر وعكس آثار التسليم والفاتورة والمخزون. تبقى الدفعات الحقيقية رصيدًا غير مخصص للعميل.',
            'The order and its delivery, invoice, and inventory effects will be reversed. Real payments remain as unapplied customer credit.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: AppText(_bi('رجوع', 'Back')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: AppText(
              _bi('إلغاء الأمر وعكس الآثار', 'Cancel and reverse effects'),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(() => _repository.cancelOrder(orderId), orderId: orderId);
    }
  }

  Future<void> _openDetails(String orderId) async {
    await showAppModuleDialog<bool>(
      context: context,
      title: context.l10n.isArabic ? 'تفاصيل أمر البيع' : 'Sales order details',
      windowKey: 'sales-workflow:details:$orderId',
      maxWidth: 1120,
      maxHeight: 820,
      builder: (_) => OrderDetailsDialog(orderId: orderId, purchase: false),
    );
    await _load(force: true);
  }

  Future<void> _run(
    Future<Object?> Function() operation, {
    String? orderId,
  }) async {
    final normalizedId = orderId?.trim();
    if (normalizedId != null &&
        normalizedId.isNotEmpty &&
        _busyOrderIds.contains(normalizedId)) {
      return;
    }
    if (mounted && normalizedId != null && normalizedId.isNotEmpty) {
      setState(() => _busyOrderIds.add(normalizedId));
    }
    try {
      await operation();
      await _load(force: true);
    } catch (error) {
      AppLogger.debug('Sales workflow action failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
              userFacingError(error, isArabic: context.l10n.isArabic),
            ),
          ),
        );
      }
    } finally {
      if (mounted && normalizedId != null && normalizedId.isNotEmpty) {
        setState(() => _busyOrderIds.remove(normalizedId));
      }
    }
  }

  @override
  Widget build(BuildContext context) => _loading
      ? const Center(child: KajCommercialLoadingState())
      : Column(
          children: [
            CommercialWorkflowFilterBar(
              searchController: _searchController,
              status: _statusFilter,
              onSearchChanged: (value) => setState(() => _query = value),
              onStatusChanged: (value) => setState(() => _statusFilter = value),
              onCreate: _newDraft,
              createLabel: _bi('مسودة بيع جديدة', 'New sales order'),
              resultCount: _filteredOrders.length,
            ),
            Expanded(
              child: _filteredOrders.isEmpty
                  ? Center(
                      child: KajCommercialEmptyState(
                        title: AppTranslation.translate('لا توجد أوامر بيع'),
                        message: AppTranslation.translate(
                          'ابدأ بإنشاء مسودة بيع جديدة ثم تابع الاعتماد والتجهيز والفوترة والتحصيل.',
                        ),
                        actionLabel: AppTranslation.translate(
                          'مسودة بيع جديدة',
                        ),
                        onAction: _newDraft,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        12,
                        6,
                        12,
                        12,
                      ),
                      itemCount: _filteredOrders.length,
                      itemBuilder: (context, index) {
                        final order = _filteredOrders[index];
                        final status = order['status']?.toString() ?? 'draft';
                        final actions = <CommercialWorkflowAction>[
                          if (status == 'draft' || status == 'cancelled')
                            CommercialWorkflowAction(
                              label: _bi(
                                'تصديق أمر البيع',
                                'Approve sales order',
                              ),
                              icon: Icons.verified_outlined,
                              primary: true,
                              onPressed: () => _approve(order['id'].toString()),
                            ),
                          if (_serverFlag(
                            order,
                            'canCreateDelivery',
                            status == 'approved' && order['deliveryId'] == null,
                          ))
                            CommercialWorkflowAction(
                              label: _bi(
                                'إنشاء إذن تجهيز مخزني',
                                'Create warehouse delivery',
                              ),
                              icon: Icons.local_shipping_outlined,
                              primary: true,
                              onPressed: () =>
                                  _delivery(order['id'].toString()),
                            ),
                          if (_serverFlag(
                            order,
                            'canApproveDelivery',
                            order['deliveryStatus'] == 'draft',
                          ))
                            CommercialWorkflowAction(
                              label: _bi(
                                'تصديق إذن التجهيز',
                                'Approve warehouse delivery',
                              ),
                              icon: Icons.inventory_rounded,
                              onPressed: () => _approveDelivery(
                                order['id'].toString(),
                                order['deliveryId'].toString(),
                              ),
                            ),
                          if (_serverFlag(
                            order,
                            'canCancelDelivery',
                            const <String>{
                              'draft',
                              'approved',
                            }.contains(order['deliveryStatus']?.toString()),
                          ))
                            CommercialWorkflowAction(
                              label: _bi(
                                'حذف أو عكس إذن التجهيز',
                                'Reverse warehouse delivery',
                              ),
                              icon: Icons.undo_rounded,
                              onPressed: () => _cancelDelivery(
                                order['id'].toString(),
                                order['deliveryId'].toString(),
                              ),
                            ),
                          if (_serverFlag(
                            order,
                            'canCreateInvoice',
                            const <String>{
                                  'approved',
                                  'partially_executed',
                                }.contains(status) &&
                                const <String>{
                                  'approved',
                                  'posted',
                                  'completed',
                                  'confirmed',
                                }.contains(
                                  order['deliveryStatus']
                                      ?.toString()
                                      .trim()
                                      .toLowerCase(),
                                ) &&
                                (order['invoiceId']
                                        ?.toString()
                                        .trim()
                                        .isEmpty ??
                                    true),
                          ))
                            CommercialWorkflowAction(
                              label: _bi(
                                'إنشاء فاتورة بيع',
                                'Create sales invoice',
                              ),
                              icon: Icons.request_quote_outlined,
                              onPressed: () => _invoice(order['id'].toString()),
                            ),
                          if (_serverFlag(
                            order,
                            'canApproveInvoice',
                            order['invoiceStatus'] == 'draft',
                          ))
                            CommercialWorkflowAction(
                              label: _bi(
                                'تصديق فاتورة البيع',
                                'Approve sales invoice',
                              ),
                              icon: Icons.fact_check_outlined,
                              onPressed: () => _approveInvoice(
                                order['id'].toString(),
                                order['invoiceId'].toString(),
                              ),
                            ),
                          if (_serverFlag(
                            order,
                            'canRecordPayment',
                            order['invoiceStatus'] == 'approved' &&
                                ((order['invoiceRemaining'] as num?)
                                            ?.toDouble() ??
                                        0) >
                                    0,
                          ))
                            CommercialWorkflowAction(
                              label: _bi(
                                'الدفعات متعددة العملات',
                                'Multi-currency payments',
                              ),
                              icon: Icons.payments_outlined,
                              primary: true,
                              onPressed: () => _addPayment(order),
                            ),
                          if (_serverFlag(
                            order,
                            'canCancelInvoice',
                            const <String>{
                              'draft',
                              'approved',
                            }.contains(order['invoiceStatus']?.toString()),
                          ))
                            CommercialWorkflowAction(
                              label: _bi(
                                'حذف أو عكس فاتورة البيع',
                                'Reverse sales invoice',
                              ),
                              icon: Icons.settings_backup_restore_rounded,
                              onPressed: () => _cancelInvoice(order),
                            ),
                          CommercialWorkflowAction(
                            label: _bi(
                              'تعديل الأمر والارتباطات',
                              'Edit order and links',
                            ),
                            icon: Icons.edit_outlined,
                            onPressed: () => _editOrder(order['id'].toString()),
                          ),
                          if (status == 'draft' || status == 'cancelled')
                            CommercialWorkflowAction(
                              label: status == 'cancelled'
                                  ? _bi(
                                      'حذف الأمر الملغى',
                                      'Delete cancelled order',
                                    )
                                  : _bi('حذف المسودة', 'Delete draft'),
                              icon: Icons.delete_forever_outlined,
                              destructive: true,
                              onPressed: () =>
                                  _deleteOrder(order['id'].toString()),
                            ),
                          if (status != 'draft' && status != 'cancelled')
                            CommercialWorkflowAction(
                              label: _bi('إلغاء الأمر', 'Cancel order'),
                              icon: Icons.undo_rounded,
                              destructive: true,
                              onPressed: () =>
                                  _cancelOrder(order['id'].toString()),
                            ),
                        ];
                        return CommercialWorkflowOrderCard(
                          order: order,
                          purchase: false,
                          partnerLabel: _bi('العميل', 'Customer'),
                          partnerName:
                              order['customerName']?.toString() ??
                              _bi('غير محدد', 'Not specified'),
                          actions: actions,
                          busy: _busyOrderIds.contains(order['id'].toString()),
                          onDetails: () => _openDetails(order['id'].toString()),
                        );
                      },
                    ),
            ),
          ],
        );
}
