import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';

/// Opens a warehouse allocation editor for a commercial order.
///
/// Each product line may be split across multiple warehouses. Vehicle lines
/// remain quantity one and, for sales, stay bound to their current warehouse.
Future<List<Map<String, Object?>>?> showWarehouseAllocationDialog({
  required BuildContext context,
  required String title,
  required List<Map<String, Object?>> items,
  required List<Map<String, Object?>> warehouses,
  required bool sales,
}) => showAppWorkspaceDialogBuilder<List<Map<String, Object?>>>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _WarehouseAllocationDialog(
    title: title,
    items: items,
    warehouses: warehouses,
    sales: sales,
  ),
);

class _WarehouseAllocationDialog extends StatefulWidget {
  const _WarehouseAllocationDialog({
    required this.title,
    required this.items,
    required this.warehouses,
    required this.sales,
  });

  final String title;
  final List<Map<String, Object?>> items;
  final List<Map<String, Object?>> warehouses;
  final bool sales;

  @override
  State<_WarehouseAllocationDialog> createState() =>
      _WarehouseAllocationDialogState();
}

class _WarehouseAllocationDialogState
    extends State<_WarehouseAllocationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final List<_AllocationRow> _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    final warehouseIds = widget.warehouses
        .map((row) => row['id']?.toString() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet();
    final fallback = warehouseIds.isEmpty ? null : warehouseIds.first;
    _rows = widget.items
        .map((item) {
          final suggestion = item['suggestedWarehouseId']?.toString();
          final warehouseId =
              suggestion != null && warehouseIds.contains(suggestion)
              ? suggestion
              : fallback;
          return _AllocationRow(
            item: item,
            warehouseId: warehouseId,
            quantity: _integer(item['quantity'], fallback: 1),
          );
        })
        .toList(growable: true);
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<_AllocationRow>>{};
    for (final row in _rows) {
      grouped.putIfAbsent(row.itemKey, () => []).add(row);
    }
    return AlertDialog(
      title: AppText(widget.title),
      content: SizedBox(
        width: AppResponsive.dialogWidth(context, 900),
        height: MediaQuery.sizeOf(context).height * .68,
        child: widget.warehouses.isEmpty
            ? const Center(
                child: AppText('لا توجد مخازن فعالة لإكمال العملية.'),
              )
            : Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppText(
                      widget.sales
                          ? 'وزّع بنود التجهيز على المخازن. يجب أن يساوي مجموع كل بند كمية أمر البيع.'
                          : 'وزّع بنود الاستلام على المخازن. يمكن تقسيم المنتج الواحد على أكثر من مخزن.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Material(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: AppText(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onErrorContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.separated(
                        itemCount: grouped.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final entries = grouped.entries.elementAt(index);
                          return _itemSection(entries.value);
                        },
                      ),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const AppText('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: widget.warehouses.isEmpty ? null : _submit,
          icon: const Icon(Icons.check_rounded),
          label: const AppText('اعتماد التوزيع'),
        ),
      ],
    );
  }

  Widget _itemSection(List<_AllocationRow> rows) {
    final first = rows.first;
    final item = first.item;
    final itemType = item['itemType']?.toString() ?? 'product';
    final isCar = itemType == 'car';
    final requiredQuantity = _integer(item['quantity'], fallback: 1);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isCar
                      ? Icons.directions_car_filled_outlined
                      : Icons.inventory_2_outlined,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppText(
                    item['description']?.toString() ?? '-',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                AppText(
                  '${AppTranslation.translate('الكمية')}: $requiredQuantity',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (!isCar && requiredQuantity > 1) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _split(first),
                    icon: const Icon(Icons.call_split_rounded, size: 16),
                    label: const AppText('تقسيم'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            ...rows.map(
              (row) => Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: row.warehouseId,
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate('المخزن'),
                          prefixIcon: const Icon(Icons.warehouse_outlined),
                        ),
                        items: _warehouseItems(row),
                        onChanged: isCar && widget.sales
                            ? null
                            : (value) =>
                                  setState(() => row.warehouseId = value),
                        validator: (value) => value == null || value.isEmpty
                            ? AppTranslation.translate('يجب اختيار المخزن')
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 150,
                      child: TextFormField(
                        controller: row.quantityController,
                        enabled: !isCar,
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          ThousandsInputFormatter(decimalDigits: 0),
                        ],
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate('الكمية'),
                        ),
                        validator: (value) {
                          final quantity = int.tryParse(value?.trim() ?? '');
                          if (quantity == null || quantity <= 0) {
                            return AppTranslation.translate(
                              'الكمية يجب أن تكون أكبر من صفر',
                            );
                          }
                          return null;
                        },
                      ),
                    ),
                    if (rows.length > 1) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: AppTranslation.translate('حذف'),
                        onPressed: () => _remove(row),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.sales && !isCar) ...[
              const SizedBox(height: 7),
              AppText(
                _availabilitySummary(item),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<DropdownMenuItem<String>> _warehouseItems(_AllocationRow row) {
    final balances = _balances(row.item);
    return widget.warehouses
        .map((warehouse) {
          final id = warehouse['id']?.toString() ?? '';
          final name = warehouse['name']?.toString() ?? id;
          final available = balances[id];
          return DropdownMenuItem<String>(
            value: id,
            child: AppText(
              available == null || !widget.sales
                  ? name
                  : '$name — ${AppTranslation.translate('المتاح')}: $available',
            ),
          );
        })
        .toList(growable: false);
  }

  void _split(_AllocationRow source) {
    final current =
        int.tryParse(source.quantityController.text.replaceAll(',', '')) ?? 0;
    if (current <= 1) {
      setState(
        () => _error = AppTranslation.translate(
          'خفّض كمية سطر آخر أو ارفعها قبل إضافة تقسيم جديد.',
        ),
      );
      return;
    }
    source.quantityController.text = '${current - 1}';
    setState(() {
      _error = null;
      _rows.add(
        _AllocationRow(
          item: source.item,
          warehouseId: _nextWarehouse(source.itemKey, source.warehouseId),
          quantity: 1,
        ),
      );
    });
  }

  String? _nextWarehouse(String itemKey, String? current) {
    final used = _rows
        .where((row) => row.itemKey == itemKey)
        .map((row) => row.warehouseId)
        .whereType<String>()
        .toSet();
    for (final warehouse in widget.warehouses) {
      final id = warehouse['id']?.toString();
      if (id != null && id.isNotEmpty && !used.contains(id)) return id;
    }
    return current ?? widget.warehouses.first['id']?.toString();
  }

  void _remove(_AllocationRow row) {
    row.dispose();
    setState(() {
      _rows.remove(row);
      _error = null;
    });
  }

  void _submit() {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final required = <String, int>{};
    final sums = <String, int>{};
    final warehouseSums = <String, int>{};
    for (final row in _rows) {
      required[row.itemKey] = _integer(row.item['quantity'], fallback: 1);
      final quantity = int.parse(row.quantityController.text.trim());
      sums[row.itemKey] = (sums[row.itemKey] ?? 0) + quantity;
      final warehouseKey = '${row.itemKey}:${row.warehouseId}';
      warehouseSums[warehouseKey] =
          (warehouseSums[warehouseKey] ?? 0) + quantity;
    }
    for (final entry in required.entries) {
      if (sums[entry.key] != entry.value) {
        setState(
          () => _error =
              '${AppTranslation.translate('مجموع توزيع البند يجب أن يساوي')} '
              '${entry.value}، ${AppTranslation.translate('والقيمة الحالية')} '
              '${sums[entry.key] ?? 0}.',
        );
        return;
      }
    }

    if (widget.sales) {
      for (final row in _rows) {
        if (row.item['itemType']?.toString() == 'car') {
          final requiredWarehouse = row.item['suggestedWarehouseId']
              ?.toString();
          if (requiredWarehouse != null &&
              requiredWarehouse.isNotEmpty &&
              row.warehouseId != requiredWarehouse) {
            setState(
              () => _error = AppTranslation.translate(
                'يجب تجهيز السيارة من مخزنها الحالي أو نقلها أولًا إلى مخزن آخر.',
              ),
            );
            return;
          }
          continue;
        }
        final available = _balances(row.item)[row.warehouseId];
        final requested =
            warehouseSums['${row.itemKey}:${row.warehouseId}'] ?? 0;
        if (available != null && requested > available) {
          setState(
            () => _error =
                '${AppTranslation.translate('الرصيد المتاح في أحد المخازن لا يكفي للتوزيع المطلوب')} '
                '($requested ${AppTranslation.translate('من')} $available).',
          );
          return;
        }
      }
    }

    Navigator.pop(
      context,
      _rows
          .map(
            (row) => <String, Object?>{
              'itemType': row.item['itemType']?.toString() ?? 'product',
              'itemId': row.item['itemId']?.toString() ?? '',
              'description': row.item['description']?.toString() ?? '',
              'warehouseId': row.warehouseId,
              'quantity': int.parse(row.quantityController.text.trim()),
            },
          )
          .toList(growable: false),
    );
  }

  Map<String, int> _balances(Map<String, Object?> item) {
    final result = <String, int>{};
    final raw = item['warehouseBalances'];
    if (raw is List) {
      for (final value in raw.whereType<Map>()) {
        final id = value['warehouseId']?.toString() ?? '';
        if (id.isEmpty) continue;
        result[id] = _integer(value['availableQuantity']);
      }
    }
    return result;
  }

  String _availabilitySummary(Map<String, Object?> item) {
    final balances = _balances(item);
    if (balances.isEmpty) {
      return AppTranslation.translate('لا توجد أرصدة متاحة لهذا المنتج.');
    }
    final names = {
      for (final warehouse in widget.warehouses)
        warehouse['id']?.toString() ?? '': warehouse['name']?.toString() ?? '',
    };
    return balances.entries
        .map((entry) => '${names[entry.key] ?? entry.key}: ${entry.value}')
        .join(' • ');
  }
}

class _AllocationRow {
  _AllocationRow({
    required this.item,
    required this.warehouseId,
    required int quantity,
  }) : quantityController = TextEditingController(text: '$quantity');

  final Map<String, Object?> item;
  String? warehouseId;
  final TextEditingController quantityController;

  String get itemKey =>
      '${item['itemType']?.toString() ?? 'product'}:${item['itemId']?.toString() ?? ''}';

  void dispose() => quantityController.dispose();
}

int _integer(Object? value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}
