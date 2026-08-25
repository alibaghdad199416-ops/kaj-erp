import 'dart:async';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quality_line_erp/design_system/kaj_inventory_stage4_components.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/printing/warehouse_transfer_pdf_service.dart';
import 'package:quality_line_erp/features/inventory/controllers/inventory_controller.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/features/inventory/pages/transfer_stock_page.dart';
import 'package:quality_line_erp/design_system/kaj_inventory_components.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';

class ProductWarehouseTransfersPage extends StatefulWidget {
  const ProductWarehouseTransfersPage({super.key});

  @override
  State<ProductWarehouseTransfersPage> createState() =>
      _ProductWarehouseTransfersPageState();
}

class _ProductWarehouseTransfersPageState
    extends State<ProductWarehouseTransfersPage> {
  bool _loading = true;
  String? _busyId;
  List<Map<String, Object?>> _rows = const [];

  bool get _ar => context.l10n.isArabic;
  String _t(String ar, String en) => _ar ? ar : en;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final controller = context.read<InventoryController>();
      if (controller.items.isEmpty || controller.allWarehouses.isEmpty) {
        await controller.loadInventory(force: true);
      }
      final rows = await controller.getProductWarehouseTransfers();
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(error);
    }
  }

  String _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text.toLowerCase() == 'null' ? '—' : text;
  }

  num _number(Object? value) =>
      value is num ? value : num.tryParse(value?.toString() ?? '') ?? 0;

  int _lineCount(Map<String, Object?> row) {
    final value = row['lineCount'];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? _items(row).length;
  }

  List<Map<String, Object?>> _items(Map<String, Object?> row) {
    final raw = row['items'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList(growable: false);
  }

  WarehouseModel? _warehouse(String? id) {
    if (id == null) return null;
    for (final warehouse in context.read<InventoryController>().allWarehouses) {
      if (warehouse.id == id) return warehouse;
    }
    return null;
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red,
        content: AppText(
          userFacingError(
            error,
            isArabic: _ar,
            arabicFallback: 'تعذر تنفيذ عملية سند النقل.',
            englishFallback: 'Unable to process the warehouse transfer.',
          ),
        ),
      ),
    );
  }

  Future<void> _createTransfer() async {
    final access = context.read<AccessController>();
    if (!access.canEditField(
      'inventory',
      'transferItem',
      viewPermission: 'inventory.view',
      writePermission: 'inventory.transfer',
    ))
      return;

    if (!await PermissionAction.require(context, 'inventory.transfer')) return;
    if (!mounted) return;
    final changed = await showAppWorkspaceDialog<bool>(
      context: context,
      child: const TransferStockPage(initialAssetType: 'product'),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _delete(Map<String, Object?> row) async {
    if (!await PermissionAction.require(context, 'inventory.transfer.delete')) {
      return;
    }
    if (!mounted) return;
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(_t('حذف سند نقل المنتجات', 'Delete product transfer')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppText(
              _t(
                'سيُعكس أثر المستند الواحد على مخزن المصدر والوجهة، ثم تُحذف حركات المخزون والقيود المرتبطة به.',
                'The single document effect will be reversed for both warehouses, then linked movements and journals will be retired.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _t('سبب الحذف', 'Deletion reason'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: AppText(_t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: AppText(_t('حذف وعكس النقل', 'Delete and reverse')),
          ),
        ],
      ),
    );
    final value = reason.text.trim();
    reason.dispose();
    if (confirmed != true || !mounted) return;
    if (value.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            _t('سبب الحذف مطلوب.', 'Deletion reason is required.'),
          ),
        ),
      );
      return;
    }

    final id = _text(row['id']);
    setState(() => _busyId = id);
    try {
      await context.read<InventoryController>().deleteProductWarehouseTransfer(
        id,
        reason: value,
      );
      await _load();
    } catch (error) {
      if (mounted) _showError(error);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _edit(Map<String, Object?> row) async {
    final fieldAccess = context.read<AccessController>();
    if (!fieldAccess.canEditField(
      'inventory',
      'transferItem',
      viewPermission: 'inventory.view',
      writePermission: 'inventory.transfer',
    ))
      return;
    if (!await PermissionAction.require(context, 'inventory.transfer')) return;
    if (!mounted) return;
    if (_text(row['status']).toLowerCase() == 'reversed') return;

    final inventory = context.read<InventoryController>();
    await inventory.loadInventory(force: true);
    if (!mounted) return;
    final warehouses = inventory.allWarehouses
        .where((warehouse) => warehouse.isActive)
        .toList(growable: false);
    final products = inventory.items
        .where((item) => item.isActive && item.isStockItem)
        .toList(growable: false);
    if (warehouses.length < 2 || products.isEmpty) {
      _showError(StateError('warehouse_transfer_edit_catalog_empty'));
      return;
    }

    String fromId = _text(row['fromWarehouseId']);
    String toId = _text(row['toWarehouseId']);
    String status = _text(row['status']).toLowerCase() == 'draft'
        ? 'draft'
        : 'completed';
    if (!warehouses.any((warehouse) => warehouse.id == fromId)) {
      fromId = warehouses.first.id;
    }
    if (!warehouses.any(
      (warehouse) => warehouse.id == toId && warehouse.id != fromId,
    )) {
      toId = warehouses.firstWhere((warehouse) => warehouse.id != fromId).id;
    }
    final notes = TextEditingController(
      text: _text(row['notes']) == '—' ? '' : _text(row['notes']),
    );
    final lines = _items(row)
        .map(
          (item) => _EditableTransferLine(
            productId: _text(item['productId']),
            quantity: _number(item['quantity']).toInt().toString(),
            unitCost: _number(item['unitCost']).toDouble(),
          ),
        )
        .where((line) => products.any((item) => item.id == line.productId))
        .toList(growable: true);
    if (lines.isEmpty) {
      lines.add(
        _EditableTransferLine(
          productId: products.first.id,
          quantity: '1',
          unitCost: products.first.unitCost,
        ),
      );
    }

    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: AppText(
            _t('تعديل سند النقل الموحد', 'Edit unified transfer document'),
          ),
          content: SizedBox(
            width: AppResponsive.dialogWidth(context, 760),
            height: AppResponsive.dialogHeight(context, 590),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppText(
                  _t(
                    'المصدر والوجهة وبنود النقل محفوظة في مستند واحد. عند الحفظ يُعكس الأثر القديم وتُعاد الحركات والارتباطات بالحالة الجديدة داخل معاملة واحدة.',
                    'Source, destination, and lines are stored in one document. Saving reverses the old effect and rebuilds movements and links atomically.',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: ValueKey('transfer-source-$fromId'),
                        initialValue: fromId,
                        decoration: InputDecoration(
                          labelText: _t('المخزن المصدر', 'Source warehouse'),
                          border: const OutlineInputBorder(),
                        ),
                        items: warehouses
                            .map(
                              (warehouse) => DropdownMenuItem(
                                value: warehouse.id,
                                child: AppText(
                                  '${warehouse.code} — ${warehouse.name}',
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            fromId = value;
                            if (toId == fromId) {
                              toId = warehouses
                                  .firstWhere(
                                    (warehouse) => warehouse.id != fromId,
                                  )
                                  .id;
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: ValueKey('transfer-target-$toId-$fromId'),
                        initialValue: toId,
                        decoration: InputDecoration(
                          labelText: _t(
                            'المخزن المستلم',
                            'Receiving warehouse',
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        items: warehouses
                            .where((warehouse) => warehouse.id != fromId)
                            .map(
                              (warehouse) => DropdownMenuItem(
                                value: warehouse.id,
                                child: AppText(
                                  '${warehouse.code} — ${warehouse.name}',
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) setDialogState(() => toId = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: status,
                  decoration: InputDecoration(
                    labelText: _t('حالة سند النقل', 'Transfer document status'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'draft',
                      child: AppText(
                        _t('مسودة بلا أثر مخزني', 'Draft without stock effect'),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'completed',
                      child: AppText(
                        _t(
                          'مكتمل ومؤثر مخزنياً',
                          'Completed with stock effect',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => status = value);
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: lines.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final line = lines[index];
                      return Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  initialValue: line.productId,
                                  decoration: InputDecoration(
                                    labelText: _t('المنتج', 'Product'),
                                    border: const OutlineInputBorder(),
                                  ),
                                  items: products
                                      .where(
                                        (item) =>
                                            item.id == line.productId ||
                                            !lines.any(
                                              (other) =>
                                                  other != line &&
                                                  other.productId == item.id,
                                            ),
                                      )
                                      .map(
                                        (item) => DropdownMenuItem(
                                          value: item.id,
                                          child: AppText(
                                            '${item.code} — ${item.name}',
                                          ),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setDialogState(() {
                                      line.productId = value;
                                      line.unitCost = products
                                          .firstWhere(
                                            (item) => item.id == value,
                                          )
                                          .unitCost;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 125,
                                child: TextFormField(
                                  controller: line.quantity,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: <TextInputFormatter>[
                                    ThousandsInputFormatter(decimalDigits: 0),
                                  ],
                                  decoration: InputDecoration(
                                    labelText: _t('الكمية', 'Quantity'),
                                    border: const OutlineInputBorder(),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                tooltip: _t('حذف البند', 'Remove line'),
                                onPressed: lines.length == 1
                                    ? null
                                    : () => setDialogState(() {
                                        lines.removeAt(index).dispose();
                                      }),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: lines.length >= products.length
                          ? null
                          : () => setDialogState(() {
                              final product = products.firstWhere(
                                (item) => !lines.any(
                                  (line) => line.productId == item.id,
                                ),
                              );
                              lines.add(
                                _EditableTransferLine(
                                  productId: product.id,
                                  quantity: '1',
                                  unitCost: product.unitCost,
                                ),
                              );
                            }),
                      icon: const Icon(Icons.add),
                      label: AppText(_t('إضافة منتج', 'Add product')),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: notes,
                        decoration: InputDecoration(
                          labelText: _t('الملاحظات', 'Notes'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: AppText(_t('إلغاء', 'Cancel')),
            ),
            FilledButton.icon(
              onPressed: () {
                final valid =
                    fromId != toId &&
                    lines.every(
                      (line) =>
                          line.productId.isNotEmpty &&
                          (int.tryParse(line.quantity.text.trim()) ?? 0) > 0,
                    );
                if (!valid) return;
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.sync_rounded),
              label: AppText(_t('حفظ وتحديث الارتباطات', 'Save and relink')),
            ),
          ],
        ),
      ),
    );

    if (accepted == true && mounted) {
      final id = _text(row['id']);
      setState(() => _busyId = id);
      try {
        await inventory.updateProductWarehouseTransfer(
          transferId: id,
          fromWarehouseId: fromId,
          toWarehouseId: toId,
          items: lines
              .map(
                (line) => <String, Object?>{
                  'productId': line.productId,
                  'quantity': int.parse(line.quantity.text.trim()),
                  'unitCost': line.unitCost,
                },
              )
              .toList(growable: false),
          notes: notes.text.trim(),
          status: status,
        );
        await _load();
      } catch (error) {
        if (mounted) _showError(error);
      } finally {
        if (mounted) setState(() => _busyId = null);
      }
    }
    notes.dispose();
    for (final line in lines) {
      line.dispose();
    }
  }

  Future<void> _print(Map<String, Object?> row) async {
    final source = _warehouse(_text(row['fromWarehouseId']));
    final destination = _warehouse(_text(row['toWarehouseId']));
    await const WarehouseTransferPdfService().printDocument(
      language: _ar ? 'ar' : 'en',
      documentNumber: _text(row['transferNumber']),
      transferDate: _text(row['transferDate']),
      sourceWarehouse:
          source?.toMap() ??
          <String, Object?>{
            'id': row['fromWarehouseId'],
            'code': row['fromWarehouseCode'],
            'name': row['fromWarehouseName'],
            'address': row['fromWarehouseAddress'],
          },
      destinationWarehouse:
          destination?.toMap() ??
          <String, Object?>{
            'id': row['toWarehouseId'],
            'code': row['toWarehouseCode'],
            'name': row['toWarehouseName'],
            'address': row['toWarehouseAddress'],
          },
      notes: _text(row['notes']) == '—' ? null : _text(row['notes']),
      items: _items(row)
          .map(
            (item) => <String, Object?>{
              'code': _text(item['productCode']),
              'name': _text(item['productName']),
              'details': _text(item['category']),
              'quantity': _number(item['quantity']),
              'unit': _text(item['unit']),
              'cost': _number(item['unitCost']).toStringAsFixed(2),
              'currency': _text(item['currency']),
            },
          )
          .toList(growable: false),
    );
  }

  Future<void> _details(Map<String, Object?> row) async {
    final items = _items(row);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: AppText(
          '${_t('سند النقل الموحد', 'Unified transfer')} ${_text(row['transferNumber'])}',
        ),
        content: SizedBox(
          width: AppResponsive.dialogWidth(context, 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppText(
                '${_text(row['fromWarehouseName'])}  →  ${_text(row['toWarehouseName'])}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: items.isEmpty
                    ? Center(child: AppText(_t('لا توجد بنود.', 'No items.')))
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(height: 18),
                        itemBuilder: (_, index) {
                          final item = items[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.inventory_2_outlined),
                            title: AppText(
                              '${_text(item['productCode'])} — ${_text(item['productName'])}',
                            ),
                            subtitle: AppText(
                              '${_t('الكمية', 'Quantity')}: ${_text(item['quantity'])} • ${_t('كلفة الوحدة', 'Unit cost')}: ${_text(item['unitCost'])}',
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => unawaited(_print(row)),
            icon: const Icon(Icons.print_outlined),
            label: AppText(_t('طباعة', 'Print')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: AppText(_t('إغلاق', 'Close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessController>();
    if (!access.canViewField(
      'inventory',
      'transferItem',
      viewPermission: 'inventory.view',
    ))
      return const SizedBox.shrink();
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            KajInventoryActionBar(
              title: _t(
                'سندات نقل المنتجات الموحدة',
                'Unified product warehouse transfers',
              ),
              subtitle: _t(
                'مستند واحد يحدّث مخزن المصدر والوجهة ويحافظ على أثر الحركة والقيود المرتبطة.',
                'One controlled document updates source and destination warehouses with linked movement and journal traceability.',
              ),
              icon: Icons.swap_horiz_rounded,
              actions: <Widget>[
                FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : () => unawaited(_createTransfer()),
                  icon: const Icon(Icons.add_rounded),
                  label: AppText(_t('سند نقل جديد', 'New transfer document')),
                ),
                IconButton(
                  onPressed: _loading ? null : () => unawaited(_load()),
                  tooltip: _t('تحديث', 'Refresh'),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
              metrics: <Widget>[
                KajInventoryMetricPill(
                  label: _t('إجمالي السندات', 'Total documents'),
                  value: '${_rows.length}',
                  icon: Icons.receipt_long_outlined,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _loading
                  ? const KajInventoryLoadingState()
                  : _rows.isEmpty
                  ? Center(
                      child: AppText(
                        _t(
                          'لا توجد سندات نقل منتجات.',
                          'No product transfers.',
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _rows.length,
                      itemBuilder: (_, index) {
                        final row = _rows[index];
                        final id = _text(row['id']);
                        final busy = _busyId == id;
                        final reversed =
                            _text(row['status']).toLowerCase() == 'reversed';
                        return Card(
                          child: ListTile(
                            onTap: busy ? null : () => unawaited(_details(row)),
                            leading: CircleAvatar(
                              child: busy
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.swap_horiz_rounded),
                            ),
                            title: AppText(
                              '${_text(row['transferNumber'])} — ${_text(row['fromWarehouseName'])} → ${_text(row['toWarehouseName'])}',
                            ),
                            subtitle: AppText(
                              '${_t('مستند واحد للمصدر والمستلم', 'One document for source and receiver')}\n${_t('التاريخ', 'Date')}: ${_text(row['transferDate'])} • ${_t('البنود', 'Lines')}: ${_lineCount(row)} • ${_t('الحالة', 'Status')}: ${_text(row['status'])}',
                            ),
                            isThreeLine: true,
                            trailing: Wrap(
                              spacing: 2,
                              children: [
                                IconButton(
                                  tooltip: _t('التفاصيل', 'Details'),
                                  onPressed: busy
                                      ? null
                                      : () => unawaited(_details(row)),
                                  icon: const Icon(Icons.visibility_outlined),
                                ),
                                IconButton(
                                  tooltip: _t('طباعة السند', 'Print document'),
                                  onPressed: busy
                                      ? null
                                      : () => unawaited(_print(row)),
                                  icon: const Icon(Icons.print_outlined),
                                ),
                                if (!reversed)
                                  IconButton(
                                    tooltip: _t(
                                      'تعديل وتحديث الارتباطات',
                                      'Edit and relink',
                                    ),
                                    onPressed: busy
                                        ? null
                                        : () => unawaited(_edit(row)),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                IconButton(
                                  tooltip: _t(
                                    'حذف وعكس النقل',
                                    'Delete and reverse',
                                  ),
                                  onPressed: busy
                                      ? null
                                      : () => unawaited(_delete(row)),
                                  icon: Icon(
                                    Icons.delete_forever_outlined,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableTransferLine {
  _EditableTransferLine({
    required this.productId,
    required String quantity,
    required this.unitCost,
  }) : quantity = TextEditingController(text: quantity);

  String productId;
  final TextEditingController quantity;
  double unitCost;

  void dispose() => quantity.dispose();
}
