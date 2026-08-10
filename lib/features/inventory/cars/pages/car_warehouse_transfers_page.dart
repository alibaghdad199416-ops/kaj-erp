import 'dart:async';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:quality_line_erp/design_system/kaj_inventory_stage4_components.dart';
import 'package:quality_line_erp/core/printing/warehouse_transfer_pdf_service.dart';

import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/core/widgets/unified_document_details_dialog.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/inventory/cars/data/car_warehouse_transfer_repository.dart';
import 'package:quality_line_erp/features/inventory/cars/data/car_repository.dart';
import 'package:quality_line_erp/features/inventory/data/inventory_repository.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_model.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_model.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';

class CarWarehouseTransfersPage extends StatefulWidget {
  const CarWarehouseTransfersPage({super.key});
  @override
  State<CarWarehouseTransfersPage> createState() =>
      _CarWarehouseTransfersPageState();
}

class _CarWarehouseTransfersPageState extends State<CarWarehouseTransfersPage> {
  final _repo = CarWarehouseTransferRepository();
  final _carsRepo = CarRepository();
  final _inventoryRepo = InventoryRepository();
  bool _loading = true;
  List<Map<String, Object?>> _rows = const [];

  String _displayValue(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text.toLowerCase() == 'null'
        ? '—'
        : text;
  }

  double _number(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '') ?? 0;

  Future<void> _showCarDetails(CarModel car, String warehouseName) =>
      showUnifiedDocumentDetails(
        context: context,
        title: 'بطاقة السيارة',
        documentNumber: car.carNumber.isEmpty ? car.id : car.carNumber,
        status: car.status,
        icon: Icons.directions_car_outlined,
        sections: [
          UnifiedDocumentSection(
            title: 'البيانات الأساسية',
            fields: [
              UnifiedDocumentField('الشركة', car.brand),
              UnifiedDocumentField('الموديل', car.model),
              UnifiedDocumentField('السنة', car.year),
              UnifiedDocumentField('اللون', car.color),
              UnifiedDocumentField('نوع السيارة', car.vehicleType),
              UnifiedDocumentField('رقم الهيكل', car.chassis),
              UnifiedDocumentField('رقم المحرك', car.engineNumber),
              UnifiedDocumentField('رقم اللوحة', car.plateNumber),
              UnifiedDocumentField('رقم السيارة', car.carNumber),
            ],
          ),
          UnifiedDocumentSection(
            title: 'المخزون والقيمة',
            fields: [
              UnifiedDocumentField('المخزن الحالي', warehouseName),
              UnifiedDocumentField('الحالة', car.status),
              UnifiedDocumentField('التكلفة', car.totalCost),
              UnifiedDocumentField('القيمة الدفترية', car.totalCost),
              UnifiedDocumentField('العملة', car.costCurrency ?? car.currency),
            ],
          ),
        ],
      );

  Widget _transferCarCard({
    required CarModel car,
    required String warehouseName,
    required bool selected,
    required ValueChanged<bool?> onSelected,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      onTap: () => _showCarDetails(car, warehouseName),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: selected, onChanged: onSelected),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    '${car.brand} ${car.model} • ${car.year} • ${car.color}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  AppText(
                    'رقم الهيكل: ${_displayValue(car.chassis)} • رقم المحرك: ${_displayValue(car.engineNumber)}\n'
                    'اللوحة: ${_displayValue(car.plateNumber)} • المخزن الحالي: $warehouseName\n'
                    'الحالة: ${car.status} • التكلفة: ${MoneyFormatter.withCurrency(car.totalCost, car.costCurrency ?? car.currency)} • القيمة الدفترية: ${MoneyFormatter.withCurrency(car.totalCost, car.costCurrency ?? car.currency)}',
                  ),
                ],
              ),
            ),
            const Icon(Icons.open_in_new_rounded, size: 18),
          ],
        ),
      ),
    ),
  );

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final rows = await _repo.listTransfers();
    if (mounted)
      setState(() {
        _rows = rows;
        _loading = false;
      });
  }

  Future<void> _newBatchTransfer() async {
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
    final allCars = await _carsRepo.getCars();
    final warehouses = await _inventoryRepo.getWarehouses();
    final warehouseNames = {
      for (final warehouse in warehouses) warehouse.id: warehouse.name,
    };
    final cars = allCars
        .where(
          (car) =>
              car.statusValue == CarStatus.available &&
              (car.warehouseId?.isNotEmpty ?? false),
        )
        .toList(growable: false);
    final sourceWarehouses = warehouses
        .where(
          (warehouse) => cars.any((car) => car.warehouseId == warehouse.id),
        )
        .toList(growable: false);
    if (!mounted) return;
    if (cars.isEmpty || sourceWarehouses.isEmpty || warehouses.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('يجب توفر سيارات ومخزنين فعالين على الأقل.'),
        ),
      );
      return;
    }

    final selectedIds = <String>{};
    String fromWarehouseId = sourceWarehouses.first.id;
    final initialTargets = warehouses
        .where((warehouse) => warehouse.id != fromWarehouseId)
        .toList(growable: false);
    String? toWarehouseId = initialTargets.isEmpty
        ? null
        : initialTargets.first.id;
    String query = '';
    DateTime effectiveAt = DateTime.now();
    final notes = TextEditingController();
    final accepted = await showAppWorkspaceDialogBuilder<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final normalizedQuery = query.trim().toLowerCase();
          final visible = cars
              .where((car) {
                if (car.warehouseId != fromWarehouseId) return false;
                if (normalizedQuery.isEmpty) return true;
                return '${car.brand} ${car.model} ${car.year} ${car.chassis} ${car.engineNumber} ${car.plateNumber} ${car.carNumber}'
                    .toLowerCase()
                    .contains(normalizedQuery);
              })
              .toList(growable: false);
          final targets = warehouses
              .where((warehouse) => warehouse.id != fromWarehouseId)
              .toList(growable: false);
          if (!targets.any((warehouse) => warehouse.id == toWarehouseId)) {
            toWarehouseId = targets.isEmpty ? null : targets.first.id;
          }

          return AlertDialog(
            title: const AppText('نقل عدة سيارات بين المخازن'),
            content: SizedBox(
              width: AppResponsive.dialogWidth(context, 780),
              height: AppResponsive.dialogHeight(context, 620),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          key: ValueKey('batch-source-$fromWarehouseId'),
                          initialValue: fromWarehouseId,
                          decoration: InputDecoration(
                            labelText: AppTranslation.translate('من المخزن'),
                            border: const OutlineInputBorder(),
                          ),
                          items: sourceWarehouses
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
                            if (value == null || value == fromWarehouseId)
                              return;
                            setDialogState(() {
                              fromWarehouseId = value;
                              selectedIds.clear();
                              final availableTargets = warehouses
                                  .where((warehouse) => warehouse.id != value)
                                  .toList(growable: false);
                              toWarehouseId = availableTargets.isEmpty
                                  ? null
                                  : availableTargets.first.id;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          key: ValueKey(
                            'batch-target-${toWarehouseId ?? ''}-${targets.length}',
                          ),
                          initialValue: toWarehouseId,
                          decoration: InputDecoration(
                            labelText: AppTranslation.translate('إلى المخزن'),
                            border: const OutlineInputBorder(),
                          ),
                          items: targets
                              .map(
                                (warehouse) => DropdownMenuItem(
                                  value: warehouse.id,
                                  child: AppText(
                                    '${warehouse.code} — ${warehouse.name}',
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) =>
                              setDialogState(() => toWarehouseId = value),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: (value) => setDialogState(() => query = value),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      labelText: AppTranslation.translate(
                        'بحث بالماركة أو الموديل أو الشاصي أو اللوحة',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: visible.isEmpty
                        ? const Center(
                            child: AppText(
                              'لا توجد سيارات متوفرة في المخزن المصدر.',
                            ),
                          )
                        : ListView.builder(
                            itemCount: visible.length,
                            itemBuilder: (_, index) {
                              final car = visible[index];
                              final selected = selectedIds.contains(car.id);
                              return _transferCarCard(
                                car: car,
                                warehouseName:
                                    warehouseNames[car.warehouseId] ?? '—',
                                selected: selected,
                                onSelected: (value) => setDialogState(() {
                                  if (value == true) {
                                    selectedIds.add(car.id);
                                  } else {
                                    selectedIds.remove(car.id);
                                  }
                                }),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_outlined),
                    title: const AppText('التاريخ والوقت التشغيلي'),
                    subtitle: AppText(
                      DateFormat('yyyy-MM-dd HH:mm').format(effectiveAt),
                    ),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: dialogContext,
                        initialDate: effectiveAt,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (date == null || !dialogContext.mounted) return;
                      final time = await showTimePicker(
                        context: dialogContext,
                        initialTime: TimeOfDay.fromDateTime(effectiveAt),
                      );
                      if (!dialogContext.mounted) return;
                      final selectedTime =
                          time ?? TimeOfDay.fromDateTime(effectiveAt);
                      setDialogState(() {
                        effectiveAt = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          selectedTime.hour,
                          selectedTime.minute,
                        );
                      });
                    },
                  ),
                  TextField(
                    controller: notes,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate('ملاحظات النقل'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const AppText('إلغاء'),
              ),
              FilledButton.icon(
                onPressed: selectedIds.isEmpty || toWarehouseId == null
                    ? null
                    : () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.print_rounded),
                label: AppText('نقل وطباعة (${selectedIds.length})'),
              ),
            ],
          );
        },
      ),
    );

    try {
      if (accepted == true &&
          selectedIds.isNotEmpty &&
          toWarehouseId != null &&
          mounted) {
        final selectedCars = cars
            .where((car) => selectedIds.contains(car.id))
            .toList(growable: false);
        final source = warehouses.firstWhere(
          (warehouse) => warehouse.id == fromWarehouseId,
        );
        final destination = warehouses.firstWhere(
          (warehouse) => warehouse.id == toWarehouseId,
        );
        final user = context.read<AccessController>().currentUser;
        try {
          final transferLines = selectedCars
              .map(
                (car) => <String, Object?>{
                  'carId': car.id,
                  'notes': notes.text.trim(),
                },
              )
              .toList(growable: false);
          final result = await _repo.createBatch(
            transferLines: transferLines,
            toWarehouseId: destination.id,
            userName: user?.fullName ?? 'النظام',
            effectiveAt: effectiveAt,
            notes: notes.text.trim(),
          );
          if (mounted) {
            await _printBatchTransfer(
              cars: selectedCars,
              source: source,
              destination: destination,
              result: result,
              preparedBy: user?.fullName,
              notes: notes.text.trim(),
              effectiveAt: effectiveAt,
            );
            await _load();
          }
        } catch (error) {
          if (mounted) {
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
    } finally {
      notes.dispose();
    }
  }

  Future<void> _printBatchTransfer({
    required List<CarModel> cars,
    required WarehouseModel source,
    required WarehouseModel destination,
    required Map<String, Object?> result,
    required String? preparedBy,
    required String notes,
    required DateTime effectiveAt,
  }) => const WarehouseTransferPdfService().printDocument(
    language: context.l10n.isArabic ? 'ar' : 'en',
    documentNumber:
        result['batchNumber']?.toString() ??
        result['transferIds']?.toString() ??
        'CTB-${DateTime.now().millisecondsSinceEpoch}',
    transferDate:
        result['transferDate']?.toString() ??
        result['effectiveAt']?.toString() ??
        result['createdAt']?.toString() ??
        effectiveAt.toIso8601String(),
    sourceWarehouse: source.toMap(),
    destinationWarehouse: destination.toMap(),
    preparedBy: preparedBy,
    notes: notes.isEmpty ? null : notes,
    items: cars
        .map(
          (car) => <String, Object?>{
            'code': car.carNumber.isEmpty ? car.id : car.carNumber,
            'name': '${car.brand} ${car.model}',
            'details':
                '${car.year} • ${car.color} • VIN: ${car.chassis} • Engine: ${car.engineNumber} • Plate: ${car.plateNumber}',
            'quantity': 1,
            'unit': context.l10n.isArabic ? 'سيارة' : 'Vehicle',
            'cost': car.totalCost.toStringAsFixed(2),
            'currency': car.costCurrency ?? car.currency,
          },
        )
        .toList(growable: false),
  );

  Future<void> _showTransferDetails(Map<String, Object?> row) {
    final reversed = row['status']?.toString() == 'reversed';
    return showUnifiedDocumentDetails(
      context: context,
      title: 'أمر نقل سيارة مخزني',
      documentNumber: _displayValue(row['transferNumber']),
      status: reversed ? 'مُرجع' : 'منفذ',
      icon: Icons.swap_horiz_rounded,
      sections: [
        UnifiedDocumentSection(
          title: 'بيانات النقل الرئيسية',
          fields: [
            UnifiedDocumentField(
              'من المخزن',
              _displayValue(row['fromWarehouseName']),
            ),
            UnifiedDocumentField(
              'إلى المخزن',
              _displayValue(row['toWarehouseName']),
            ),
            UnifiedDocumentField(
              AppTranslation.translate('تاريخ التنفيذ'),
              _displayValue(
                row['transferDate'] ?? row['effectiveAt'] ?? row['createdAt'],
              ),
            ),
            if (context.read<AccessController>().canViewField(
              'cars',
              'auditMetadata',
              viewPermission: 'cars.view',
            ))
              UnifiedDocumentField(
                'المنفذ',
                _displayValue(row['createdByUserName']),
              ),
          ],
        ),
        UnifiedDocumentSection(
          title: 'بطاقة السيارة',
          fields: [
            UnifiedDocumentField('الماركة', _displayValue(row['brand'])),
            UnifiedDocumentField('الموديل', _displayValue(row['model'])),
            UnifiedDocumentField('السنة', _displayValue(row['year'])),
            UnifiedDocumentField('اللون', _displayValue(row['color'])),
            UnifiedDocumentField(
              'نوع السيارة',
              _displayValue(row['vehicleType']),
            ),
            UnifiedDocumentField('رقم الهيكل', _displayValue(row['chassis'])),
            UnifiedDocumentField(
              'رقم المحرك',
              _displayValue(row['engineNumber']),
            ),
            UnifiedDocumentField(
              'رقم اللوحة',
              _displayValue(row['plateNumber']),
            ),
            UnifiedDocumentField(
              'رقم السيارة',
              _displayValue(row['carNumber']),
            ),
            UnifiedDocumentField(
              'المخزن بعد النقل',
              _displayValue(row['toWarehouseName']),
            ),
            UnifiedDocumentField(
              'المخزن الحالي',
              _displayValue(row['currentWarehouseName']),
            ),
            UnifiedDocumentField(
              'حالة السيارة',
              _displayValue(row['carStatus']),
            ),
            UnifiedDocumentField(
              'التكلفة',
              MoneyFormatter.withCurrency(
                _number(row['purchasePrice']) + _number(row['maintenanceCost']),
                _displayValue(row['currency']),
              ),
            ),
            UnifiedDocumentField(
              'القيمة الدفترية',
              MoneyFormatter.withCurrency(
                _number(row['purchasePrice']) + _number(row['maintenanceCost']),
                _displayValue(row['currency']),
              ),
            ),
          ],
        ),
        UnifiedDocumentSection(
          title: AppTranslation.translate('المراجع والملاحظات'),
          fields: [
            UnifiedDocumentField(
              AppTranslation.translate('السيارة'),
              _displayValue(row['carId']),
            ),
            UnifiedDocumentField('الحالة', reversed ? 'مُرجع' : 'منفذ'),
            UnifiedDocumentField('الملاحظات', _displayValue(row['notes'])),
          ],
        ),
      ],
    );
  }

  Future<void> _printTransfer(Map<String, Object?> row) async {
    final cost =
        _number(row['purchasePrice']) + _number(row['maintenanceCost']);
    await const WarehouseTransferPdfService().printDocument(
      language: context.l10n.isArabic ? 'ar' : 'en',
      documentNumber: _displayValue(row['transferNumber']),
      transferDate: _displayValue(
        row['transferDate'] ?? row['effectiveAt'] ?? row['createdAt'],
      ),
      preparedBy:
          context.read<AccessController>().canViewField(
            'cars',
            'auditMetadata',
            viewPermission: 'cars.view',
          )
          ? _displayValue(row['createdByUserName'])
          : '—',
      notes: _displayValue(row['notes']) == '—'
          ? null
          : _displayValue(row['notes']),
      sourceWarehouse: <String, Object?>{
        'id': row['fromWarehouseId'],
        'code': row['fromWarehouseCode'],
        'name': row['fromWarehouseName'],
        'address': row['fromWarehouseAddress'],
      },
      destinationWarehouse: <String, Object?>{
        'id': row['toWarehouseId'],
        'code': row['toWarehouseCode'],
        'name': row['toWarehouseName'],
        'address': row['toWarehouseAddress'],
      },
      items: [
        <String, Object?>{
          'code': _displayValue(row['carNumber']) == '—'
              ? _displayValue(row['carId'])
              : _displayValue(row['carNumber']),
          'name':
              '${_displayValue(row['brand'])} ${_displayValue(row['model'])}',
          'details':
              '${_displayValue(row['year'])} • ${_displayValue(row['color'])} • VIN: ${_displayValue(row['chassis'])} • Engine: ${_displayValue(row['engineNumber'])} • Plate: ${_displayValue(row['plateNumber'])}',
          'quantity': 1,
          'unit': context.l10n.isArabic ? 'سيارة' : 'Vehicle',
          'cost': cost.toStringAsFixed(2),
          'currency': _displayValue(row['currency']),
        },
      ],
    );
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
    final cars = (await _carsRepo.getCars())
        .where(
          (car) =>
              car.statusValue == CarStatus.available && car.warehouseId != null,
        )
        .toList(growable: false);
    final warehouses = (await _inventoryRepo.getWarehouses())
        .map((warehouse) => warehouse.toMap())
        .toList(growable: false);
    if (!mounted) return;
    String carId = row['carId'].toString();
    String toId = row['toWarehouseId'].toString();
    final notes = TextEditingController(text: row['notes']?.toString() ?? '');
    final ok = await showAppWorkspaceDialogBuilder<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('تعديل سند نقل السيارة'),
        content: SizedBox(
          width: AppResponsive.dialogWidth(context, 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: carId,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('السيارة'),
                  border: const OutlineInputBorder(),
                ),
                items: cars
                    .map(
                      (car) => DropdownMenuItem(
                        value: car.id,
                        child: AppText(
                          '${car.brand} ${car.model} — ${car.chassis}',
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) carId = value;
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: toId,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('المخزن الجديد'),
                  border: OutlineInputBorder(),
                ),
                items: warehouses
                    .where(
                      (w) =>
                          w['id']?.toString() !=
                          row['fromWarehouseId']?.toString(),
                    )
                    .map(
                      (w) => DropdownMenuItem(
                        value: w['id'].toString(),
                        child: AppText(w['name'].toString()),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) toId = v;
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: notes,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('ملاحظات'),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const AppText('حفظ التعديل'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final user = context.read<AccessController>().currentUser;
      try {
        await _repo.update(
          id: row['id'].toString(),
          carId: carId,
          toWarehouseId: toId,
          userId: user?.id ?? 'system',
          userName: user?.fullName ?? 'النظام',
          notes: notes.text.trim(),
        );
        await _load();
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: AppText(
                userFacingError(e, isArabic: context.l10n.isArabic),
              ),
            ),
          );
      }
    }
    notes.dispose();
  }

  Future<void> _reverse(Map<String, Object?> row) async {
    if (!await PermissionAction.require(context, 'inventory.transfer')) return;
    if (!mounted) return;
    final user = context.read<AccessController>().currentUser;
    try {
      await _repo.reverse(
        id: row['id'].toString(),
        userId: user?.id ?? 'system',
        userName: user?.fullName ?? 'النظام',
      );
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
              userFacingError(e, isArabic: context.l10n.isArabic),
            ),
          ),
        );
    }
  }

  Future<void> _delete(Map<String, Object?> row) async {
    if (!await PermissionAction.require(context, 'cars.transfer.delete'))
      return;
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('حذف سند النقل'),
        content: const AppText(
          'سيتم إلغاء أثر النقل وإعادة السيارة إلى مخزن المصدر ثم حذف السند. هل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const AppText('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final user = context.read<AccessController>().currentUser;
    try {
      await _repo.delete(
        id: row['id'].toString(),
        userName: user?.fullName ?? 'النظام',
      );
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
              userFacingError(e, isArabic: context.l10n.isArabic),
            ),
          ),
        );
    }
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
      appBar: AppBar(
        title: const AppText('نقل السيارات بين المخازن'),
        actions: [
          if (PermissionAction.allowed(context, 'inventory.transfer'))
            IconButton(
              onPressed: _newBatchTransfer,
              icon: const Icon(Icons.add),
              tooltip: AppTranslation.translate('نقل جديد'),
            ),
        ],
      ),
      body: _loading
          ? const KajInventoryLoadingState()
          : _rows.isEmpty
          ? const Center(child: AppText('لا توجد حركات نقل سيارات'))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _rows.length,
              itemBuilder: (_, i) {
                final r = _rows[i];
                final reversed = r['status'] == 'reversed';
                return Card(
                  child: ListTile(
                    onTap: () => _showTransferDetails(r),
                    leading: CircleAvatar(
                      child: Icon(
                        reversed
                            ? Icons.undo_rounded
                            : Icons.swap_horiz_rounded,
                      ),
                    ),
                    title: AppText(
                      '${r['transferNumber']} — ${r['brand']} ${r['model']}',
                    ),
                    subtitle: AppText(
                      '${_displayValue(r['fromWarehouseName'])} ← ${_displayValue(r['toWarehouseName'])}\nالمنفذ: ${_displayValue(r['createdByUserName'])} | الحالة: ${reversed ? 'مُرجع' : 'منفذ'}',
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'edit') await _edit(r);
                        if (v == 'reverse') await _reverse(r);
                        if (v == 'delete') await _delete(r);
                        if (v == 'print') await _printTransfer(r);
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'print',
                          child: AppText('طباعة أمر النقل'),
                        ),
                        if (!reversed &&
                            PermissionAction.allowed(
                              context,
                              'inventory.transfer',
                            ))
                          const PopupMenuItem(
                            value: 'edit',
                            child: AppText('تعديل النقل'),
                          ),
                        if (!reversed &&
                            PermissionAction.allowed(
                              context,
                              'inventory.transfer',
                            ))
                          const PopupMenuItem(
                            value: 'reverse',
                            child: AppText('إرجاع النقل'),
                          ),
                        if (PermissionAction.allowed(
                          context,
                          'cars.transfer.delete',
                        ))
                          const PopupMenuItem(
                            value: 'delete',
                            child: AppText('حذف السند'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
