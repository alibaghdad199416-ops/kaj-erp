// Contract vocabulary: transferLines represents the atomic multi-line payload.
// The completed transfer document remains printable through the print workflow.
import 'dart:async';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';
import 'package:quality_line_erp/core/utils/money_formatter.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/design_system/kaj_inventory_stage4_components.dart';
import 'package:quality_line_erp/design_system/kaj_shell_components.dart';
import 'package:quality_line_erp/core/printing/warehouse_transfer_pdf_service.dart';
import 'package:quality_line_erp/core/widgets/app_back_button.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/core/widgets/unified_document_details_dialog.dart';
import 'package:quality_line_erp/features/inventory/cars/data/car_repository.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_model.dart';
import 'package:quality_line_erp/features/inventory/controllers/inventory_controller.dart';
import 'package:quality_line_erp/features/inventory/data/inventory_repository.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_model.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_model.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_stock_model.dart';

class TransferStockPage extends StatefulWidget {
  const TransferStockPage({super.key, this.initialAssetType = 'product'});

  final String initialAssetType;

  @override
  State<TransferStockPage> createState() => _TransferStockPageState();
}

class _TransferStockPageState extends State<TransferStockPage> {
  Widget _securedTransferField(String field, Widget child) =>
      FieldPermissionControl(
        resource: 'inventory',
        field: field,
        viewPermission: 'inventory.view',
        writePermission: 'inventory.transfer',
        child: child,
      );

  final _quantityController = TextEditingController(text: '1');
  final _notesController = TextEditingController();
  final _inventoryRepository = InventoryRepository();

  String _assetType = 'product';
  String? _productId;
  String? _carId;
  String? _fromWarehouseId;
  String? _toWarehouseId;
  bool _saving = false;
  bool _loadingCars = true;
  bool _loadingProductStocks = false;
  bool _initialized = false;
  DateTime _effectiveAt = DateTime.now();
  int _stockRequestSerial = 0;
  List<CarModel> _cars = const [];
  List<WarehouseStockModel> _productStocks = const [];
  final List<_ProductTransferLine> _productLines = [];

  @override
  void initState() {
    super.initState();
    _assetType = widget.initialAssetType == 'car' ? 'car' : 'product';
    unawaited(_loadCars());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final inventory = context.read<InventoryController>();
    if (inventory.items.isEmpty || inventory.warehouses.isEmpty) return;
    _initialized = true;
    _productId = inventory.items
        .firstWhere(
          (item) => item.isStockItem,
          orElse: () => inventory.items.first,
        )
        .id;
    unawaited(_loadProductStocks(_productId!));
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  WarehouseModel? _warehouse(InventoryController inventory, String? id) =>
      inventory.warehouses.where((warehouse) => warehouse.id == id).firstOrNull;

  InventoryModel? _selectedProduct(InventoryController inventory) =>
      inventory.items.where((item) => item.id == _productId).firstOrNull;

  CarModel? get _selectedCar =>
      _cars.where((car) => car.id == _carId).firstOrNull;

  WarehouseStockModel? get _selectedProductStock => _productStocks
      .where((stock) => stock.warehouseId == _fromWarehouseId)
      .firstOrNull;

  int get _availableProductQuantity =>
      _selectedProductStock?.availableQuantity ?? 0;

  Future<void> _loadCars() async {
    try {
      final cars = await CarRepository().getCars();
      if (!mounted) return;
      final available =
          cars
              .where(
                (car) =>
                    car.statusValue == CarStatus.available &&
                    (car.warehouseId?.isNotEmpty ?? false),
              )
              .toList(growable: false)
            ..sort((a, b) {
              final brand = a.brand.toLowerCase().compareTo(
                b.brand.toLowerCase(),
              );
              if (brand != 0) return brand;
              final model = a.model.toLowerCase().compareTo(
                b.model.toLowerCase(),
              );
              return model != 0 ? model : b.year.compareTo(a.year);
            });
      setState(() {
        _cars = available;
        _loadingCars = false;
        if (_carId == null && available.isNotEmpty) {
          _carId = available.first.id;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingCars = false);
      _showError(
        error,
        arabicFallback: 'تعذر تحميل السيارات السحابية.',
        englishFallback: 'Unable to load cloud vehicles.',
      );
    }
  }

  Future<void> _loadProductStocks(String productId) async {
    final serial = ++_stockRequestSerial;
    if (mounted) setState(() => _loadingProductStocks = true);
    try {
      final stocks = await _inventoryRepository.getTransferableProductStocks(
        productId,
      );
      if (!mounted || serial != _stockRequestSerial) return;
      final inventory = context.read<InventoryController>();
      final validIds = inventory.warehouses
          .map((warehouse) => warehouse.id)
          .toSet();
      final valid = stocks
          .where(
            (stock) =>
                validIds.contains(stock.warehouseId) &&
                stock.availableQuantity > 0,
          )
          .toList(growable: false);
      setState(() {
        _productStocks = valid;
        final fixedSource = _productLines.isNotEmpty
            ? _productLines.first.fromWarehouseId
            : null;
        if (fixedSource != null) {
          // A multi-line order must keep one source warehouse even when the
          // newly selected product has no stock there. The card will show a
          // zero balance and prevent adding an invalid line.
          _fromWarehouseId = fixedSource;
        } else if (!valid.any(
          (stock) => stock.warehouseId == _fromWarehouseId,
        )) {
          _fromWarehouseId = valid.isEmpty ? null : valid.first.warehouseId;
        }
        _normalizeDestination(inventory);
      });
    } catch (error) {
      if (!mounted || serial != _stockRequestSerial) return;
      setState(() {
        _productStocks = const [];
        if (_productLines.isEmpty) _fromWarehouseId = null;
      });
      _showError(
        error,
        arabicFallback: 'تعذر تحميل أرصدة المنتج.',
        englishFallback: 'Unable to load product balances.',
      );
    } finally {
      if (mounted && serial == _stockRequestSerial) {
        setState(() => _loadingProductStocks = false);
      }
    }
  }

  void _normalizeDestination(InventoryController inventory) {
    final targets = inventory.warehouses
        .where((warehouse) => warehouse.id != _fromWarehouseId)
        .toList(growable: false);
    if (!targets.any((warehouse) => warehouse.id == _toWarehouseId)) {
      _toWarehouseId = targets.isEmpty ? null : targets.first.id;
    }
  }

  void _selectAssetType(String type, InventoryController inventory) {
    setState(() {
      _assetType = type;
      if (type == 'car') {
        final car = _selectedCar ?? _cars.firstOrNull;
        _carId = car?.id;
        _fromWarehouseId = car?.warehouseId;
      } else {
        _fromWarehouseId = _productLines.isNotEmpty
            ? _productLines.first.fromWarehouseId
            : _selectedProductStock?.warehouseId;
      }
      _normalizeDestination(inventory);
    });
  }

  Future<void> _selectProduct(String productId) async {
    setState(() => _productId = productId);
    await _loadProductStocks(productId);
  }

  void _selectCar(String carId, InventoryController inventory) {
    final car = _cars.firstWhere((value) => value.id == carId);
    setState(() {
      _carId = carId;
      _fromWarehouseId = car.warehouseId;
      _normalizeDestination(inventory);
    });
  }

  void _changeSource(String? value, InventoryController inventory) {
    if (value == null || value == _fromWarehouseId) return;
    setState(() {
      _fromWarehouseId = value;
      if (_assetType == 'product') _productLines.clear();
      _normalizeDestination(inventory);
    });
  }

  bool _addCurrentProductLine({bool showMessage = true}) {
    final inventory = context.read<InventoryController>();
    final item = _selectedProduct(inventory);
    final stock = _selectedProductStock;
    final quantity = int.tryParse(_quantityController.text.trim());
    if (item == null || stock == null || _fromWarehouseId == null) {
      if (showMessage) _showInfo('اختر منتجاً ومخزن مصدر يحتوي على رصيد.');
      return false;
    }
    if (quantity == null ||
        quantity <= 0 ||
        quantity > stock.availableQuantity) {
      if (showMessage)
        _showInfo('الكمية المطلوبة غير صحيحة أو أكبر من الرصيد المتاح.');
      return false;
    }
    if (_productLines.any((line) => line.item.id == item.id)) {
      if (showMessage) _showInfo('المنتج مضاف إلى سند النقل مسبقاً.');
      return false;
    }
    if (_productLines.isNotEmpty &&
        _productLines.first.fromWarehouseId != _fromWarehouseId) {
      if (showMessage) _showInfo('يجب أن تكون جميع المواد من مخزن مصدر واحد.');
      return false;
    }
    setState(() {
      _productLines.add(
        _ProductTransferLine(
          item: item,
          fromWarehouseId: _fromWarehouseId!,
          quantity: quantity,
          unitCost: stock.averageUnitCost == 0
              ? item.unitCost
              : stock.averageUnitCost,
        ),
      );
      _quantityController.text = '1';
    });
    return true;
  }

  Future<void> _pickEffectiveAt() async {
    final ar = context.l10n.isArabic;
    final date = await showDatePicker(
      context: context,
      initialDate: _effectiveAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: ar ? 'اختر التاريخ التشغيلي' : 'Select operational date',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_effectiveAt),
      helpText: ar ? 'اختر الوقت التشغيلي' : 'Select operational time',
    );
    if (!mounted) return;
    final selectedTime = time ?? TimeOfDay.fromDateTime(_effectiveAt);
    setState(() {
      _effectiveAt = DateTime(
        date.year,
        date.month,
        date.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  Future<void> _save() async {
    if (!await PermissionAction.require(context, 'inventory.transfer')) return;
    if (!mounted) return;
    if (_saving || _fromWarehouseId == null || _toWarehouseId == null) return;
    if (_fromWarehouseId == _toWarehouseId) {
      _showInfo('يجب اختيار مخزنين مختلفين.');
      return;
    }
    if (_assetType == 'car' && _selectedCar == null) return;
    if (_assetType == 'product' &&
        _productLines.isEmpty &&
        !_addCurrentProductLine()) {
      return;
    }

    setState(() => _saving = true);
    try {
      final inventory = context.read<InventoryController>();
      final source = _warehouse(inventory, _fromWarehouseId);
      final destination = _warehouse(inventory, _toWarehouseId);
      if (source == null || destination == null) {
        _showInfo('تعذر العثور على أحد المخازن المحددة. أعد اختيار المخازن.');
        return;
      }
      final notes = _notesController.text.trim();
      if (_assetType == 'car') {
        final car = _selectedCar!;
        final result = await inventory.transferCar(
          carId: car.id,
          fromWarehouseId: source.id,
          toWarehouseId: destination.id,
          notes: notes,
          effectiveAt: _effectiveAt,
        );
        await _printCarTransfer(
          car: car,
          source: source,
          destination: destination,
          result: result,
          notes: notes,
        );
      } else {
        final transferLines = _productLines
            .map(
              (line) => <String, Object?>{
                'productId': line.item.id,
                'fromWarehouseId': source.id,
                'toWarehouseId': destination.id,
                'quantity': line.quantity,
                'notes': notes,
              },
            )
            .toList(growable: false);
        final result = await inventory.transferStockBatch(
          transferLines: transferLines,
          notes: notes,
          effectiveAt: _effectiveAt,
        );
        await _printProductTransfer(
          source: source,
          destination: destination,
          result: result,
          notes: notes,
        );
      }
      if (!mounted) return;
      AppWorkspaceWindowScope.closeCurrent(context, true);
    } catch (error) {
      if (!mounted) return;
      _showError(
        error,
        arabicFallback: 'تعذر تنفيذ النقل.',
        englishFallback: 'Unable to complete transfer.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _printCarTransfer({
    required CarModel car,
    required WarehouseModel source,
    required WarehouseModel destination,
    required Map<String, Object?> result,
    required String notes,
  }) => const WarehouseTransferPdfService().printDocument(
    language: context.l10n.isArabic ? 'ar' : 'en',
    documentNumber:
        result['transferNumber']?.toString() ??
        result['id']?.toString() ??
        car.id,
    transferDate:
        result['transferDate']?.toString() ?? _effectiveAt.toIso8601String(),
    sourceWarehouse: source.toMap(),
    destinationWarehouse: destination.toMap(),
    notes: notes.isEmpty ? null : notes,
    items: [
      <String, Object?>{
        'code': car.carNumber.isEmpty ? car.id : car.carNumber,
        'name': '${car.brand} ${car.model}',
        'details':
            '${car.year} • ${car.color} • VIN: ${car.chassis} • Engine: ${car.engineNumber} • Plate: ${car.plateNumber}',
        'quantity': 1,
        'unit': context.l10n.isArabic ? 'سيارة' : 'Vehicle',
        'cost': car.totalCost.toStringAsFixed(2),
        'currency': car.costCurrency ?? car.currency,
      },
    ],
  );

  Future<void> _printProductTransfer({
    required WarehouseModel source,
    required WarehouseModel destination,
    required Map<String, Object?> result,
    required String notes,
  }) => const WarehouseTransferPdfService().printDocument(
    language: context.l10n.isArabic ? 'ar' : 'en',
    documentNumber:
        result['transferNumber']?.toString() ??
        result['transferId']?.toString() ??
        'TR-${_effectiveAt.millisecondsSinceEpoch}',
    transferDate:
        result['transferDate']?.toString() ?? _effectiveAt.toIso8601String(),
    sourceWarehouse: source.toMap(),
    destinationWarehouse: destination.toMap(),
    notes: notes.isEmpty ? null : notes,
    items: _productLines
        .map(
          (line) => <String, Object?>{
            'code': line.item.code,
            'name': line.item.name,
            'details': '${line.item.category} • ${line.item.description}',
            'quantity': line.quantity,
            'unit': line.item.unit,
            'cost': line.unitCost.toStringAsFixed(2),
            'currency': line.item.costCurrency ?? line.item.currency,
          },
        )
        .toList(growable: false),
  );

  Future<void> _showSelectedAssetDetails() async {
    final inventory = context.read<InventoryController>();
    if (_assetType == 'car') {
      final car = _selectedCar;
      if (car == null) return;
      final warehouse = _warehouse(inventory, car.warehouseId);
      await showUnifiedDocumentDetails(
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
            ],
          ),
          UnifiedDocumentSection(
            title: 'المخزون والقيمة',
            fields: [
              UnifiedDocumentField('المخزن الحالي', warehouse?.name),
              UnifiedDocumentField('الحالة', car.status),
              UnifiedDocumentField('التكلفة', car.totalCost),
              UnifiedDocumentField('القيمة الدفترية', car.totalCost),
              UnifiedDocumentField('العملة', car.costCurrency ?? car.currency),
            ],
          ),
        ],
      );
      return;
    }

    final item = _selectedProduct(inventory);
    if (item == null) return;
    final source = _warehouse(inventory, _fromWarehouseId);
    await showUnifiedDocumentDetails(
      context: context,
      title: 'بطاقة المنتج',
      documentNumber: item.code.isEmpty ? item.id : item.code,
      status: item.isService ? 'خدمة' : 'منتج مخزني',
      icon: Icons.inventory_2_outlined,
      sections: [
        UnifiedDocumentSection(
          title: 'البيانات الأساسية',
          fields: [
            UnifiedDocumentField('الرمز', item.code),
            UnifiedDocumentField('الاسم', item.name),
            UnifiedDocumentField('الوحدة', item.unit),
            UnifiedDocumentField('المجموعة', item.category),
            UnifiedDocumentField('الباركود', item.barcode),
          ],
        ),
        UnifiedDocumentSection(
          title: 'المخزون والقيمة',
          fields: [
            UnifiedDocumentField('المخزن', source?.name),
            UnifiedDocumentField('الرصيد', _availableProductQuantity),
            UnifiedDocumentField(
              'الكلفة',
              _selectedProductStock?.averageUnitCost == 0
                  ? item.unitCost
                  : _selectedProductStock?.averageUnitCost,
            ),
            UnifiedDocumentField('العملة', item.costCurrency ?? item.currency),
          ],
        ),
      ],
    );
  }

  void _showInfo(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: AppText(message)));
  }

  void _showError(
    Object error, {
    required String arabicFallback,
    required String englishFallback,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: AppText(
          userFacingError(
            error,
            isArabic: context.l10n.isArabic,
            arabicFallback: arabicFallback,
            englishFallback: englishFallback,
          ),
        ),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryController>();
    final ar = context.l10n.isArabic;
    if (!_initialized &&
        inventory.items.isNotEmpty &&
        inventory.warehouses.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _initialized) return;
        setState(() {
          _initialized = true;
          _productId = inventory.items.first.id;
        });
        unawaited(_loadProductStocks(_productId!));
      });
    }
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: AppText(ar ? 'التحويلات المخزنية' : 'Warehouse transfers'),
      ),
      body: KajInventoryScreen(
        maxWidth: 1120,
        children: <Widget>[
          KajInventoryPageHeader(
            titleAr: 'تحويل المنتجات والسيارات',
            titleEn: 'Transfer products and vehicles',
            subtitleAr:
                'أنشئ مستند نقل موحدًا مع تحقق الرصيد ومسار المصدر والوجهة والطباعة.',
            subtitleEn:
                'Create a controlled transfer document with stock validation, source/destination routing and printing.',
            icon: Icons.swap_horiz_rounded,
          ),
          const SizedBox(height: 16),
          KajInventorySection(
            titleAr: 'نوع الأصل والاختيار',
            titleEn: 'Asset type and selection',
            icon: Icons.category_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _securedTransferField(
                  'itemType',
                  SegmentedButton<String>(
                    segments: <ButtonSegment<String>>[
                      ButtonSegment(
                        value: 'product',
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: AppText(ar ? 'منتج' : 'Product'),
                      ),
                      ButtonSegment(
                        value: 'car',
                        icon: const Icon(Icons.directions_car_outlined),
                        label: AppText(ar ? 'سيارة' : 'Vehicle'),
                      ),
                    ],
                    selected: <String>{_assetType},
                    onSelectionChanged: (value) =>
                        _selectAssetType(value.first, inventory),
                  ),
                ),
                const SizedBox(height: 16),
                if (_assetType == 'product')
                  _buildProductSelector(inventory)
                else
                  _buildCarSelector(inventory),
                const SizedBox(height: 14),
                _buildSelectedCard(inventory),
              ],
            ),
          ),
          const SizedBox(height: 16),
          KajInventorySection(
            titleAr: 'المسار والكميات',
            titleEn: 'Route and quantities',
            icon: Icons.route_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildWarehouseRow(inventory),
                if (_assetType == 'product') ...<Widget>[
                  const SizedBox(height: 14),
                  _buildProductQuantityAndAdd(),
                  if (_productLines.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 16),
                    _buildProductLines(inventory),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          KajInventorySection(
            titleAr: 'الملاحظات والتنفيذ',
            titleEn: 'Notes and execution',
            icon: Icons.task_alt_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _securedTransferField(
                  'operationalDate',
                  InkWell(
                    onTap: _saving ? null : _pickEffectiveAt,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: ar
                            ? 'التاريخ والوقت التشغيلي'
                            : 'Operational date and time',
                        prefixIcon: const Icon(Icons.event_available_outlined),
                        border: const OutlineInputBorder(),
                      ),
                      child: AppText(
                        DateFormat('yyyy-MM-dd HH:mm').format(_effectiveAt),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _securedTransferField(
                  'transferNotes',
                  KajField(
                    controller: _notesController,
                    maxLines: 3,
                    label: ar ? 'ملاحظات النقل' : 'Transfer notes',
                    leading: Icons.notes_outlined,
                  ),
                ),
                const SizedBox(height: 18),
                if (PermissionAction.allowed(context, 'inventory.transfer'))
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: KajPrimaryAction(
                      label: _saving
                          ? (ar
                                ? 'جارٍ تنفيذ النقل...'
                                : 'Processing transfer...')
                          : (ar
                                ? 'تنفيذ وطباعة أمر النقل'
                                : 'Execute and print transfer'),
                      icon: Icons.print_rounded,
                      busy: _saving,
                      onPressed: _saving ? null : _save,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildProductSelector(InventoryController inventory) =>
      _securedTransferField(
        'transferItem',
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: ValueKey(
            'product-${_productId ?? ''}-${inventory.items.length}',
          ),
          initialValue: inventory.items.any((item) => item.id == _productId)
              ? _productId
              : null,
          decoration: InputDecoration(
            labelText: AppTranslation.translate('المنتج'),
            border: const OutlineInputBorder(),
          ),
          items: inventory.items
              .where((item) => item.isStockItem)
              .map(
                (item) => DropdownMenuItem(
                  value: item.id,
                  child: AppText('${item.code} — ${item.name}'),
                ),
              )
              .toList(growable: false),
          onChanged: (value) {
            if (value != null) unawaited(_selectProduct(value));
          },
        ),
      );

  Widget _buildCarSelector(InventoryController inventory) {
    if (_loadingCars) return const LinearProgressIndicator();
    return _securedTransferField(
      'transferItem',
      DropdownButtonFormField<String>(
        isExpanded: true,
        key: ValueKey('car-${_carId ?? ''}-${_cars.length}'),
        initialValue: _cars.any((car) => car.id == _carId) ? _carId : null,
        decoration: InputDecoration(
          labelText: AppTranslation.translate('السيارة'),
          border: const OutlineInputBorder(),
        ),
        items: _cars
            .map(
              (car) => DropdownMenuItem(
                value: car.id,
                child: AppText(
                  '${car.brand} ${car.model} ${car.year} — ${car.chassis}',
                ),
              ),
            )
            .toList(growable: false),
        onChanged: (value) {
          if (value != null) _selectCar(value, inventory);
        },
      ),
    );
  }

  Widget _buildSelectedCard(InventoryController inventory) {
    final car = _selectedCar;
    final product = _selectedProduct(inventory);
    final source = _warehouse(inventory, _fromWarehouseId);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _showSelectedAssetDetails,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _assetType == 'car'
              ? _vehicleCardBody(car, source)
              : _productCardBody(product, source),
        ),
      ),
    );
  }

  Widget _vehicleCardBody(CarModel? car, WarehouseModel? source) {
    if (car == null) return const AppText('اختر سيارة');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.directions_car_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: AppText(
                '${car.brand} ${car.model} • ${car.year} • ${car.color}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const Icon(Icons.open_in_new_rounded, size: 18),
          ],
        ),
        const SizedBox(height: 8),
        AppText(
          'رقم الهيكل: ${_display(car.chassis)} • رقم المحرك: ${_display(car.engineNumber)} • اللوحة: ${_display(car.plateNumber)}\n'
          'المخزن الحالي: ${_display(source?.name)} • الحالة: ${car.status}\n'
          'التكلفة: ${MoneyFormatter.withCurrency(car.totalCost, car.costCurrency ?? car.currency)} • القيمة الدفترية: ${MoneyFormatter.withCurrency(car.totalCost, car.costCurrency ?? car.currency)}',
        ),
      ],
    );
  }

  Widget _productCardBody(InventoryModel? item, WarehouseModel? source) {
    if (item == null) return const AppText('اختر منتجاً');
    final cost = _selectedProductStock?.averageUnitCost == 0
        ? item.unitCost
        : _selectedProductStock?.averageUnitCost ?? item.unitCost;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.inventory_2_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: AppText(
                '${item.code} — ${item.name}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            const Icon(Icons.open_in_new_rounded, size: 18),
          ],
        ),
        const SizedBox(height: 8),
        AppText(
          'الوحدة: ${item.unit} • المجموعة: ${item.category} • المخزن: ${_display(source?.name)}\n'
          'الرصيد المتاح: $_availableProductQuantity • الكلفة: ${MoneyFormatter.withCurrency(cost, item.costCurrency ?? item.currency)}',
        ),
      ],
    );
  }

  Widget _buildWarehouseRow(InventoryController inventory) => LayoutBuilder(
    builder: (context, constraints) {
      final sourceItems = _assetType == 'car'
          ? inventory.warehouses
          : inventory.warehouses.where(
              (warehouse) => _productStocks.any(
                (stock) =>
                    stock.warehouseId == warehouse.id &&
                    stock.availableQuantity > 0,
              ),
            );
      final source = _warehouseDropdown(
        field: 'sourceWarehouseId',
        label: 'من المخزن',
        value: _fromWarehouseId,
        items: sourceItems.toList(growable: false),
        onChanged: _assetType == 'car'
            ? null
            : (value) => _changeSource(value, inventory),
      );
      final destination = _warehouseDropdown(
        field: 'destinationWarehouseId',
        label: 'إلى المخزن',
        value: _toWarehouseId,
        items: inventory.warehouses
            .where((warehouse) => warehouse.id != _fromWarehouseId)
            .toList(growable: false),
        onChanged: (value) => setState(() => _toWarehouseId = value),
      );
      if (constraints.maxWidth < 650) {
        return Column(
          children: [source, const SizedBox(height: 12), destination],
        );
      }
      return Row(
        children: [
          Expanded(child: source),
          const SizedBox(width: 14),
          Expanded(child: destination),
        ],
      );
    },
  );

  Widget _warehouseDropdown({
    required String field,
    required String label,
    required String? value,
    required List<WarehouseModel> items,
    required ValueChanged<String?>? onChanged,
  }) {
    final validValue = items.any((item) => item.id == value) ? value : null;
    return _securedTransferField(
      field,
      DropdownButtonFormField<String>(
        isExpanded: true,
        key: ValueKey('$label-${validValue ?? ''}-${items.length}'),
        initialValue: validValue,
        decoration: InputDecoration(
          labelText: AppTranslation.translate(label),
          border: const OutlineInputBorder(),
        ),
        items: items
            .map(
              (warehouse) => DropdownMenuItem(
                value: warehouse.id,
                child: AppText('${warehouse.code} — ${warehouse.name}'),
              ),
            )
            .toList(growable: false),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildProductQuantityAndAdd() => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: _securedTransferField(
          'transferQuantity',
          TextFormField(
            controller: _quantityController,
            keyboardType: TextInputType.number,
            inputFormatters: <TextInputFormatter>[
              ThousandsInputFormatter(decimalDigits: 0),
            ],
            decoration: InputDecoration(
              labelText: AppTranslation.translate('الكمية'),
              helperText: _loadingProductStocks
                  ? AppTranslation.translate('جارٍ تحميل الرصيد...')
                  : '${AppTranslation.translate('الرصيد المتاح')}: $_availableProductQuantity',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      FilledButton.icon(
        onPressed: _loadingProductStocks
            ? null
            : () => _addCurrentProductLine(),
        icon: const Icon(Icons.add_rounded),
        label: const AppText('إضافة إلى السند'),
      ),
    ],
  );

  Widget _buildProductLines(InventoryController inventory) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(
            'مواد أمر النقل (${_productLines.length})',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const Divider(),
          for (final line in _productLines)
            ListTile(
              contentPadding: EdgeInsets.zero,
              onTap: () {
                setState(() => _productId = line.item.id);
                unawaited(_loadProductStocks(line.item.id));
              },
              leading: const Icon(Icons.inventory_2_outlined),
              title: AppText('${line.item.code} — ${line.item.name}'),
              subtitle: AppText(
                '${line.quantity} ${line.item.unit} • ${MoneyFormatter.withCurrency(line.unitCost, line.item.costCurrency ?? line.item.currency)}',
              ),
              trailing: IconButton(
                tooltip: AppTranslation.translate('إزالة'),
                onPressed: () => setState(() => _productLines.remove(line)),
                icon: const Icon(Icons.delete_outline),
              ),
            ),
        ],
      ),
    ),
  );

  String _display(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text.toLowerCase() == 'null' ? '—' : text;
  }
}

class _ProductTransferLine {
  const _ProductTransferLine({
    required this.item,
    required this.fromWarehouseId,
    required this.quantity,
    required this.unitCost,
  });

  final InventoryModel item;
  final String fromWarehouseId;
  final int quantity;
  final double unitCost;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
