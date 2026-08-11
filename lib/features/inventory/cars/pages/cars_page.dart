import 'dart:async';

import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_empty.dart';
import 'package:quality_line_erp/core/widgets/app_entity_page.dart';
import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/inventory/cars/pages/vehicle_service_card_page.dart';
import 'package:quality_line_erp/features/inventory/cars/controllers/cars_controller.dart';
import 'package:quality_line_erp/features/inventory/cars/controllers/car_images_controller.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_model.dart';
import 'package:quality_line_erp/features/inventory/cars/widgets/car_card.dart';
import 'package:quality_line_erp/features/inventory/cars/widgets/cars_search.dart';
import 'package:quality_line_erp/features/inventory/cars/widgets/cars_statistics.dart';
import 'package:quality_line_erp/features/inventory/cars/widgets/status_filter.dart';
import 'package:quality_line_erp/features/inventory/data/inventory_repository.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_model.dart';
import 'add_car_page.dart';
import 'edit_car_page.dart';
import 'car_warehouse_transfers_page.dart';

class CarsPage extends StatefulWidget {
  const CarsPage({super.key});

  @override
  State<CarsPage> createState() => _CarsPageState();
}

class _CarsPageState extends State<CarsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';
  String _selectedStatus = 'الكل';
  final InventoryRepository _inventoryRepository = InventoryRepository();
  List<WarehouseModel> _warehouses = const [];
  final Set<String> _selectedWarehouseIds = <String>{};
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
        _warehouseIdByReference = Map<String, String>.unmodifiable(
          idByReference,
        );
        _warehouseLabelById = Map<String, String>.unmodifiable(labelById);
        _selectedWarehouseIds.retainWhere(labelById.containsKey);
        _loadingWarehouses = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingWarehouses = false);
    }
  }

  Future<void> _selectWarehouses() async {
    final selected = Set<String>.from(_selectedWarehouseIds);
    final accepted = await showAppWorkspaceDialogBuilder<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const AppText('فرز السيارات حسب مجموعة مخازن'),
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
    if (accepted == true && mounted)
      setState(() {
        _selectedWarehouseIds
          ..clear()
          ..addAll(selected);
      });
  }

  @override
  void dispose() {
    _searchController.dispose();
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
    final availableCars = cars
        .where((car) => car.statusValue == CarStatus.available)
        .length;
    final purchasingCars = cars
        .where((car) => car.statusValue == CarStatus.purchasing)
        .length;
    final sellingCars = cars
        .where((car) => car.statusValue == CarStatus.selling)
        .length;
    final reservedCars = sellingCars;
    final soldCars = cars
        .where((car) => car.statusValue == CarStatus.sold)
        .length;
    final totalValueByCurrency = <String, double>{};
    for (final car in cars.where(
      (car) => car.isIncludedInCurrentInventoryValue,
    )) {
      final currency = (car.costCurrency ?? car.currency).trim().toUpperCase();
      if (currency.isEmpty) continue;
      totalValueByCurrency.update(
        currency,
        (value) => value + car.totalCost,
        ifAbsent: () => car.totalCost,
      );
    }
    final query = _searchText.trim();
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

    final selectedStatus = _selectedStatus == 'الكل'
        ? null
        : CarStatusCodec.parse(_selectedStatus);
    final filteredCars = UnifiedFilterEngine.apply<CarModel>(
      cars,
      criteria: UnifiedFilterCriteria(
        searchText: query,
        warehouseIds: Set<String>.unmodifiable(_selectedWarehouseIds),
        statuses: selectedStatus == null
            ? const <String>{}
            : <String>{selectedStatus.name},
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
    );
    // The shared engine preserves the required AND behavior:
    // matchesSearch && statusMatches && warehouseMatches.

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
          label: AppText(
            context.l10n.isArabic ? 'نقل بين المخازن' : 'Warehouse transfers',
          ),
        ),
        if (canCreate)
          FilledButton.icon(
            onPressed: _openAddCar,
            icon: const Icon(Icons.add_rounded, size: 17),
            label: AppText(
              context.l10n.isArabic ? 'إضافة سيارة' : 'Add vehicle',
            ),
          ),
      ],
      statistics: CarsStatistics(
        totalCars: cars.length,
        availableCars: availableCars,
        purchasingCars: purchasingCars,
        sellingCars: sellingCars,
        reservedCars: reservedCars,
        soldCars: soldCars,
        totalValueByCurrency: totalValueByCurrency,
        showTotalValue: canViewInventoryValue,
      ),
      toolbar: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 680;
          final search = CarsSearch(
            controller: _searchController,
            onChanged: (value) => setState(() => _searchText = value),
          );
          final statusFilter = SizedBox(
            width: compact ? double.infinity : 180,
            child: StatusFilter(
              selectedStatus: _selectedStatus,
              onChanged: (value) => setState(() => _selectedStatus = value),
            ),
          );
          final warehouseFilter = SizedBox(
            width: compact ? double.infinity : 240,
            child: OutlinedButton.icon(
              onPressed: _loadingWarehouses ? null : _selectWarehouses,
              icon: const Icon(Icons.warehouse_outlined),
              label: AppText(
                _selectedWarehouseIds.isEmpty
                    ? (context.l10n.isArabic ? 'كل المخازن' : 'All warehouses')
                    : (context.l10n.isArabic
                          ? 'المخازن المحددة (${_selectedWarehouseIds.length})'
                          : 'Selected warehouses (${_selectedWarehouseIds.length})'),
              ),
            ),
          );
          final hasFilters =
              query.isNotEmpty ||
              _selectedStatus != 'الكل' ||
              _selectedWarehouseIds.isNotEmpty;
          final clearFilters = SizedBox(
            width: compact ? double.infinity : 150,
            child: TextButton.icon(
              onPressed: hasFilters
                  ? () => setState(() {
                      _searchController.clear();
                      _searchText = '';
                      _selectedStatus = 'الكل';
                      _selectedWarehouseIds.clear();
                    })
                  : null,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const AppText('مسح الفلاتر'),
            ),
          );
          if (compact) {
            return Column(
              children: [
                search,
                const SizedBox(height: 8),
                warehouseFilter,
                const SizedBox(height: 8),
                statusFilter,
                const SizedBox(height: 8),
                clearFilters,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 8),
              warehouseFilter,
              const SizedBox(width: 8),
              statusFilter,
              const SizedBox(width: 8),
              clearFilters,
            ],
          );
        },
      ),
      body: filteredCars.isEmpty
          ? AppEmpty(
              title: context.l10n.isArabic
                  ? 'لا توجد سيارات مطابقة'
                  : 'No matching vehicles',
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
                        return _warehouses
                                .where(
                                  (warehouse) =>
                                      warehouse.id.trim() == warehouseId.trim(),
                                )
                                .map((warehouse) => warehouse.name)
                                .firstOrNull ??
                            warehouseLabel(car);
                      })(),
                      carNumber: car.carNumber,
                      plateNumber: car.plateNumber,
                    );
                  },
                );
              },
            ),
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
      builder: (_) => VehicleServiceCardPage(car: car),
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
