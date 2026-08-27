import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/filtering/unified_query_toolbar.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_empty.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';
import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/features/inventory/asset_history/pages/asset_history_page.dart';
import 'package:quality_line_erp/features/inventory/cars/controllers/car_images_controller.dart';
import 'package:quality_line_erp/features/inventory/cars/controllers/cars_controller.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_model.dart';
import 'package:quality_line_erp/features/inventory/cars/widgets/car_card.dart';
import 'package:quality_line_erp/features/inventory/cars/widgets/cars_statistics.dart';
import 'package:quality_line_erp/features/inventory/data/inventory_repository.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_model.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'add_car_page.dart';
import 'car_warehouse_transfers_page.dart';
import 'edit_car_page.dart';

class CarsPage extends StatefulWidget {
  const CarsPage({super.key});

  @override
  State<CarsPage> createState() => _CarsPageState();
}

class _CarsPageState extends State<CarsPage> {
  final UnifiedQueryController _queryController = UnifiedQueryController();
  final InventoryRepository _inventoryRepository = InventoryRepository();
  List<WarehouseModel> _warehouses = const [];
  Map<String, String> _warehouseIdByReference = const <String, String>{};
  Map<String, String> _warehouseLabelById = const <String, String>{};
  bool _loadingWarehouses = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadWarehouses());
      unawaited(_loadCarsAndThumbnails());
    });
  }

  Future<void> _loadCarsAndThumbnails() async {
    final cars = context.read<CarsController>();
    await cars.loadCars();
    if (!mounted) return;
    await context.read<CarImagesController>().loadThumbnails(
      cars.cars.map((car) => car.id),
    );
  }

  Future<void> _loadWarehouses() async {
    try {
      final warehouses = await _inventoryRepository.getWarehouses();
      if (!mounted) return;
      final idByReference = <String, String>{};
      final labelById = <String, String>{};
      for (final warehouse in warehouses) {
        final label = '${warehouse.code} — ${warehouse.name}'.trim();
        labelById[warehouse.id] = label;
        for (final reference in <String>[
          warehouse.id,
          warehouse.code,
          warehouse.name,
          '${warehouse.code} ${warehouse.name}',
          label,
        ]) {
          final normalized = UnifiedFilterEngine.normalize(reference);
          if (normalized.isNotEmpty) idByReference[normalized] = warehouse.id;
        }
      }
      setState(() {
        _warehouses = warehouses;
        _warehouseIdByReference = Map<String, String>.unmodifiable(idByReference);
        _warehouseLabelById = Map<String, String>.unmodifiable(labelById);
        final token = _queryController.state.filters
            .where((item) => item.key == 'warehouse')
            .firstOrNull;
        final selected = token?.value is Iterable
            ? (token!.value as Iterable).map((e) => e.toString()).toSet()
            : <String>{};
        final retained = selected.where(labelById.containsKey).toSet();
        if (retained.length != selected.length) {
          if (retained.isEmpty) {
            _queryController.removeFilterKey('warehouse');
          } else {
            _queryController.addFilter(
              UnifiedFilterToken(
                key: 'warehouse',
                label: 'المخازن',
                value: retained,
                valueLabel: 'المخازن المحددة (${retained.length})',
              ),
            );
          }
        }
        _loadingWarehouses = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingWarehouses = false);
    }
  }

  Set<String> _selectedWarehouseIds(UnifiedQueryState state) {
    final token = state.filters.where((item) => item.key == 'warehouse').firstOrNull;
    final value = token?.value;
    if (value is Iterable) return value.map((e) => e.toString()).toSet();
    return const <String>{};
  }

  String? _selectedStatus(UnifiedQueryState state) {
    final token = state.filters.where((item) => item.key == 'status').firstOrNull;
    return token?.value.toString();
  }

  void _setStatus(String? value) {
    if (value == null || value.isEmpty) {
      _queryController.removeFilterKey('status');
      return;
    }
    final status = CarStatusCodec.parse(value);
    _queryController.addFilter(
      UnifiedFilterToken(
        key: 'status',
        label: 'الحالة',
        value: status.name,
        valueLabel: _statusLabel(status),
      ),
    );
  }

  String _statusLabel(CarStatus status) {
    switch (status) {
      case CarStatus.defined:
        return 'معرفة';
      case CarStatus.available:
        return 'متاحة';
      case CarStatus.purchasing:
        return 'قيد الشراء';
      case CarStatus.selling:
        return 'قيد البيع';
      case CarStatus.sold:
        return 'مباعة';
      case CarStatus.damaged:
        return 'تالفة';
    }
  }

  Future<void> _selectWarehouses() async {
    final selected = Set<String>.from(_selectedWarehouseIds(_queryController.state));
    final accepted = await showAppWorkspaceDialogBuilder<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const AppText('فلترة السيارات حسب المخازن'),
          content: SizedBox(
            width: 460,
            child: ListView(
              shrinkWrap: true,
              children: _warehouses.map((warehouse) {
                final checked = selected.contains(warehouse.id);
                return CheckboxListTile(
                  value: checked,
                  title: AppText('${warehouse.code} — ${warehouse.name}'),
                  onChanged: (value) => setDialogState(() {
                    if (value == true) {
                      selected.add(warehouse.id);
                    } else {
                      selected.remove(warehouse.id);
                    }
                  }),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                selected.clear();
                setDialogState(() {});
              },
              child: const AppText('كل المخازن'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const AppText('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const AppText('تطبيق'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || accepted != true) return;
    if (selected.isEmpty) {
      _queryController.removeFilterKey('warehouse');
    } else {
      final labels = selected
          .map((id) => _warehouseLabelById[id])
          .whereType<String>()
          .toList();
      _queryController.addFilter(
        UnifiedFilterToken(
          key: 'warehouse',
          label: 'المخازن',
          value: Set<String>.unmodifiable(selected),
          valueLabel: labels.length <= 2
              ? labels.join('، ')
              : 'المخازن المحددة (${labels.length})',
        ),
      );
    }
  }

  List<UnifiedSortCriterion<CarModel>> _sorts(UnifiedQueryState state) {
    return state.sorts.map((rule) {
      final direction = rule.descending
          ? UnifiedSortDirection.descending
          : UnifiedSortDirection.ascending;
      switch (rule.field) {
        case 'date':
          return UnifiedSortCriterion<CarModel>(
            key: rule.field,
            direction: direction,
            value: (car) => DateTime.tryParse(car.purchaseDate ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
          );
        case 'number':
          return UnifiedSortCriterion<CarModel>(
            key: rule.field,
            direction: direction,
            value: (car) => car.carNumber,
          );
        case 'plate':
          return UnifiedSortCriterion<CarModel>(
            key: rule.field,
            direction: direction,
            value: (car) => car.plateNumber,
          );
        case 'cost':
          return UnifiedSortCriterion<CarModel>(
            key: rule.field,
            direction: direction,
            value: (car) => car.totalCost,
          );
        default:
          return UnifiedSortCriterion<CarModel>(
            key: rule.field,
            direction: direction,
            value: (car) => '${car.brand} ${car.model}',
          );
      }
    }).toList(growable: false);
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cars = context.watch<CarsController>().cars;
    final canCreate = PermissionAction.allowed(context, 'cars.create');
    final access = context.watch<AccessController>();
    final canViewPurchaseCost = access.canViewField(
      'cars',
      'purchasePrice',
      viewPermission: 'cars.view',
    );
    final canViewMaintenanceCost = access.canViewField(
      'cars',
      'maintenanceCost',
      viewPermission: 'cars.view',
    );
    final canViewInventoryValue = canViewPurchaseCost && canViewMaintenanceCost;
    final availableCars = cars.where((car) => car.statusValue == CarStatus.available).length;
    final purchasingCars = cars.where((car) => car.statusValue == CarStatus.purchasing).length;
    final sellingCars = cars.where((car) => car.statusValue == CarStatus.selling).length;
    final soldCars = cars.where((car) => car.statusValue == CarStatus.sold).length;
    final totalValueByCurrency = <String, double>{};
    for (final car in cars.where(
      (car) =>
          car.statusValue != CarStatus.sold &&
          car.warehouseId != null &&
          car.warehouseId!.trim().isNotEmpty,
    )) {
      final currency = (car.costCurrency ?? car.currency).trim().toUpperCase();
      if (currency.isEmpty) continue;
      totalValueByCurrency.update(
        currency,
        (value) => value + car.totalCost,
        ifAbsent: () => car.totalCost,
      );
    }

    return AnimatedBuilder(
      animation: _queryController,
      builder: (context, _) {
        final state = _queryController.state;
        final selectedWarehouseIds = _selectedWarehouseIds(state);
        final selectedStatus = _selectedStatus(state);
        final warehouseLabels = _warehouseLabelById;

        String? canonicalWarehouseId(CarModel car) {
          final raw = car.warehouseId?.trim() ?? '';
          if (raw.isEmpty) return null;
          return _warehouseIdByReference[UnifiedFilterEngine.normalize(raw)] ?? raw;
        }

        String? warehouseLabel(CarModel car) {
          final id = canonicalWarehouseId(car);
          if (id == null) return null;
          return warehouseLabels[id] ?? car.warehouseId;
        }

        final filteredCars = UnifiedFilterEngine.apply<CarModel>(
          cars,
          criteria: UnifiedFilterCriteria(
            searchText: state.search,
            warehouseIds: selectedWarehouseIds,
            statuses: selectedStatus == null ? const <String>{} : <String>{selectedStatus},
          ),
          adapter: UnifiedFilterAdapter<CarModel>(
            searchableText: (car) => <Object?>[
              car.brand,
              car.model,
              car.year,
              car.color,
              car.plateNumber,
              car.chassis,
              car.carNumber,
              car.vehicleType,
              car.supplierName,
              warehouseLabel(car),
            ],
            warehouseId: canonicalWarehouseId,
            status: (car) => car.statusValue.name,
            type: (car) => car.vehicleType,
            currency: (car) => car.costCurrency ?? car.currency,
          ),
          sorts: _sorts(state),
        );

        final statusOptions = CarStatus.values.map(
          (status) => DropdownMenuItem<String>(
            value: status.name,
            child: Text(_statusLabel(status)),
          ),
        ).toList();

        final sortOptions = <UnifiedQuerySortOption>[
          const UnifiedQuerySortOption(
            rule: UnifiedSortRule(field: 'date', label: 'التاريخ', descending: true),
            icon: Icons.calendar_today_outlined,
          ),
          const UnifiedQuerySortOption(
            rule: UnifiedSortRule(field: 'number', label: 'رقم السيارة'),
            icon: Icons.tag,
          ),
          const UnifiedQuerySortOption(
            rule: UnifiedSortRule(field: 'plate', label: 'رقم اللوحة'),
            icon: Icons.confirmation_number_outlined,
          ),
          const UnifiedQuerySortOption(
            rule: UnifiedSortRule(field: 'cost', label: 'التكلفة', descending: true),
            icon: Icons.payments_outlined,
          ),
        ];

        return AppEntityPage(
          hideHeader: true,
          title: context.l10n.isArabic ? 'إدارة السيارات' : 'Vehicle management',
          subtitle: context.l10n.isArabic
              ? 'إدارة بيانات السيارات ومتابعة حالاتها وقيمها وحركتها المخزنية.'
              : 'Manage vehicle records, availability, valuation and warehouse movement.',
          leading: const Icon(Icons.directions_car_outlined, size: 20),
          showBackButton: false,
          actions: [
            OutlinedButton.icon(
              onPressed: _openTransfers,
              icon: const Icon(Icons.swap_horiz),
              label: AppText(context.l10n.isArabic ? 'نقل بين المخازن' : 'Warehouse transfers'),
            ),
            if (canCreate)
              FilledButton.icon(
                onPressed: _openAddCar,
                icon: const Icon(Icons.add_rounded, size: 17),
                label: AppText(context.l10n.isArabic ? 'إضافة سيارة' : 'Add vehicle'),
              ),
          ],
          statistics: CarsStatistics(
            totalCars: cars.length,
            availableCars: availableCars,
            purchasingCars: purchasingCars,
            sellingCars: sellingCars,
            reservedCars: sellingCars,
            soldCars: soldCars,
            totalValueByCurrency: totalValueByCurrency,
            showTotalValue: canViewInventoryValue,
          ),
          toolbar: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 700;
              final unifiedToolbar = UnifiedQueryToolbar(
                controller: _queryController,
                searchHint: context.l10n.isArabic ? 'ابحث في بيانات السيارات...' : 'Search vehicles...',
                sorts: sortOptions,
              );
              final statusFilter = SizedBox(
                width: compact ? double.infinity : 180,
                child: DropdownButtonFormField<String>(
                  value: selectedStatus,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'الحالة',
                    prefixIcon: Icon(Icons.flag_outlined),
                  ),
                  items: statusOptions,
                  onChanged: _setStatus,
                ),
              );
              final warehouseFilter = SizedBox(
                width: compact ? double.infinity : 240,
                child: OutlinedButton.icon(
                  onPressed: _loadingWarehouses ? null : _selectWarehouses,
                  icon: const Icon(Icons.warehouse_outlined),
                  label: AppText(
                    selectedWarehouseIds.isEmpty
                        ? 'كل المخازن'
                        : 'المخازن المحددة (${selectedWarehouseIds.length})',
                  ),
                ),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    unifiedToolbar,
                    const SizedBox(height: 8),
                    statusFilter,
                    const SizedBox(height: 8),
                    warehouseFilter,
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  unifiedToolbar,
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      statusFilter,
                      const SizedBox(width: 8),
                      warehouseFilter,
                    ],
                  ),
                ],
              );
            },
          ),
          body: filteredCars.isEmpty
              ? AppEmpty(
                  title: context.l10n.isArabic ? 'لا توجد سيارات مطابقة' : 'No matching vehicles',
                  message: 'جرّب تغيير معايير البحث أو أضف سيارة جديدة',
                  icon: Icons.directions_car_outlined,
                  action: canCreate
                      ? FilledButton.icon(
                          onPressed: _openAddCar,
                          icon: const Icon(Icons.add_rounded, size: 17),
                          label: const AppText('إضافة سيارة جديدة'),
                        )
                      : null,
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1180
                        ? 3
                        : constraints.maxWidth >= 760
                        ? 2
                        : 1;
                    return GridView.builder(
                      padding: const EdgeInsets.all(10),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        mainAxisExtent: columns == 3
                            ? 168
                            : columns == 2
                            ? 176
                            : 188,
                      ),
                      itemCount: filteredCars.length,
                      itemBuilder: (context, index) {
                        final car = filteredCars[index];
                        return CarCard(
                          car: car,
                          onEdit: () => _editCar(car),
                          onHistory: () => _showCarHistory(car),
                          onDelete: () => _deleteCar(car),
                          warehouseName: (() {
                            final warehouseId = canonicalWarehouseId(car);
                            if (warehouseId == null) return warehouseLabel(car);
                            for (final warehouse in _warehouses) {
                              if (warehouse.id.trim() == warehouseId.trim()) return warehouse.name;
                            }
                            return warehouseLabel(car);
                          })(),
                          carNumber: car.carNumber,
                          plateNumber: car.plateNumber,
                        );
                      },
                    );
                  },
                ),
        );
      },
    );
  }

  Future<void> _openTransfers() async {
    await showAppModuleDialog(
      context: context,
      title: 'نقل السيارات بين المخازن',
      windowKey: 'cars:warehouse-transfers',
      maxWidth: 1050,
      maxHeight: 780,
      builder: (_) => const CarWarehouseTransfersPage(),
    );
    if (mounted) await context.read<CarsController>().loadCars();
  }

  Future<void> _openAddCar() async {
    await showAppModuleDialog(
      context: context,
      title: 'إضافة سيارة',
      windowKey: 'cars:add',
      builder: (_) => const AddCarPage(),
    );
  }

  Future<void> _editCar(CarModel car) async {
    if (!await PermissionAction.require(context, 'cars.update')) return;
    if (!mounted) return;
    await showAppModuleDialog(
      context: context,
      title: 'تعديل سيارة',
      windowKey: 'cars:edit:${car.id}',
      builder: (_) => EditCarPage(car: car),
    );
  }

  Future<void> _showCarHistory(CarModel car) async {
    await showAppModuleDialog(
      context: context,
      title: 'سجل ${car.brand} ${car.model}',
      windowKey: 'cars:history:${car.id}',
      builder: (_) => AssetHistoryPage.car(assetId: car.id),
    );
  }

  Future<void> _deleteCar(CarModel car) async {
    if (!await PermissionAction.require(context, 'cars.delete')) return;
    if (!mounted) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: 'تأكيد حذف السيارة',
      message: 'هل تريد حذف هذه السيارة؟ لا يمكن التراجع عن هذا الإجراء.',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    await context.read<CarsController>().removeCar(car.id);
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
