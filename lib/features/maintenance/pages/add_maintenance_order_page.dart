import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/finance/supported_currency.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_phase3_components.dart';
import 'package:quality_line_erp/design_system/kaj_relationship_stage5_components.dart';
import 'package:quality_line_erp/features/inventory/controllers/inventory_controller.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_model.dart';
import 'package:quality_line_erp/features/maintenance/controllers/maintenance_controller.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';

class AddMaintenanceOrderPage extends StatefulWidget {
  const AddMaintenanceOrderPage({super.key, this.order});

  final MaintenanceOrderModel? order;

  @override
  State<AddMaintenanceOrderPage> createState() =>
      _AddMaintenanceOrderPageState();
}

class _AddMaintenanceOrderPageState extends State<AddMaintenanceOrderPage> {
  final _formKey = GlobalKey<FormState>();
  final _labor = TextEditingController(text: '0');
  final _price = TextEditingController(text: '0');
  final _notes = TextEditingController();
  final List<_LineDraft> _lines = [];
  String? _carId;
  String _pricingType = 'paid';
  String _currency = 'USD';
  DateTime _maintenanceDate = DateTime.now();
  bool _saving = false;
  bool _loading = true;
  String? _loadError;

  bool get _editing => widget.order != null;
  bool get _ar => context.l10n.isArabic;
  String t(String ar, String en) => _ar ? ar : en;

  String get _writePermission =>
      _editing ? 'maintenance.update' : 'maintenance.create';

  Widget _securedField(String field, Widget child) => FieldPermissionControl(
    resource: 'maintenance',
    field: field,
    viewPermission: 'maintenance.view',
    writePermission: _writePermission,
    child: child,
  );

  @override
  void initState() {
    super.initState();
    final order = widget.order;
    if (order != null) {
      _carId = order.carId;
      _pricingType = order.pricingType;
      _currency = SupportedCurrency.initial(
        isNew: false,
        stored: order.currencyCode,
      );
      _labor.text = order.laborCost.toStringAsFixed(2);
      _price.text = order.salePrice.toStringAsFixed(2);
      _notes.text = order.notes ?? '';
      _maintenanceDate =
          DateTime.tryParse(order.maintenanceDate)?.toLocal() ?? DateTime.now();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap({bool force = false}) async {
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    final inventory = context.read<InventoryController>();
    final maintenance = context.read<MaintenanceController>();
    try {
      await Future.wait([
        if (inventory.warehouses.isEmpty || force) inventory.loadInventory(),
        inventory.loadMaintenanceCatalog(force: force),
        maintenance.loadEligibleVehicles(force: force),
      ]);
      final editingOrder = widget.order;
      if (editingOrder != null && _lines.isEmpty) {
        // ignore: use_build_context_synchronously
        final existing = await context
            .read<MaintenanceController>()
            .getOrderLines(editingOrder.id);
        for (final line in existing) {
          _lines.add(
            _LineDraft(
              productId: line.productId,
              warehouseId: line.warehouseId,
              quantity: line.quantity,
              unitPrice: line.unitPrice,
            ),
          );
        }
      }
      if (!mounted) return;
      final soldCars = maintenance.eligibleVehicles;
      _carId ??= soldCars.isEmpty ? null : soldCars.first.carId;
    } catch (error) {
      if (!mounted) return;
      _loadError = userFacingError(
        error,
        isArabic: _ar,
        arabicFallback: 'تعذر تحميل السيارات المباعة وبيانات أمر الصيانة.',
        englishFallback: 'Unable to load sold vehicles and maintenance data.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _labor.dispose();
    _price.dispose();
    _notes.dispose();
    for (final line in _lines) line.dispose();
    super.dispose();
  }

  String _itemCurrency(InventoryModel item) =>
      (item.saleCurrency ?? item.currency).trim().toUpperCase();

  List<InventoryModel> _currencyItems(InventoryController inventory) =>
      inventory.maintenanceItems
          .where((item) => item.isActive && _itemCurrency(item) == _currency)
          .toList(growable: false);

  void _changeCurrency(String? value) {
    final next = (value ?? 'USD').toUpperCase();
    if (next == _currency) return;
    for (final line in _lines) line.dispose();
    setState(() {
      _currency = next;
      _lines.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: AppText(
          t(
            'تم مسح البنود لأن عملة أمر الصيانة تغيرت.',
            'Items were cleared because the maintenance order currency changed.',
          ),
        ),
      ),
    );
  }

  Future<void> _addLine() async {
    final inventory = context.read<InventoryController>();
    final available = _currencyItems(inventory);
    if (available.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            t(
              'لا توجد مواد أو خدمات صيانة فعالة متاحة للإضافة.',
              'No active maintenance items or services are available.',
            ),
          ),
        ),
      );
      return;
    }

    final selected = await _selectMaintenanceItem(available);
    if (selected == null || !mounted) return;
    setState(
      () => _lines.add(
        _LineDraft(
          productId: selected.id,
          warehouseId: selected.isService || inventory.warehouses.isEmpty
              ? null
              : inventory.warehouses.first.id,
          quantity: 1,
          unitPrice: selected.salePrice,
        ),
      ),
    );
  }

  InventoryModel? _item(String? id) {
    if (id == null) return null;
    for (final item in context.read<InventoryController>().maintenanceItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  String _maintenanceWarehouseId() {
    for (final line in _lines) {
      final value = line.warehouseId?.trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    final carId = _carId;
    if (form == null || !form.validate() || carId == null || carId.isEmpty)
      return;
    final inventory = context.read<InventoryController>();
    final incompatible = _lines.any((line) {
      final item = inventory.maintenanceItems.where(
        (e) => e.id == line.productId,
      );
      return item.isEmpty || _itemCurrency(item.first) != _currency;
    });
    if (incompatible) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            t(
              'كل مادة أو خدمة يجب أن تطابق عملة أمر الصيانة.',
              'Every item or service must match the maintenance order currency.',
            ),
          ),
        ),
      );
      return;
    }
    for (final line in _lines) {
      final item = _item(line.productId);
      if (item == null || (!item.isService && line.warehouseId == null)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
              t(
                'اختر مخزن كل مادة مخزنية',
                'Select a warehouse for each stock item',
              ),
            ),
          ),
        );
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final requests = <MaintenancePartRequest>[];
      for (final line in _lines) {
        final productId = line.productId;
        final item = _item(productId);
        if (productId == null || productId.isEmpty || item == null) {
          throw StateError(
            t(
              'المادة أو الخدمة المحددة لم تعد متاحة',
              'The selected item or service is no longer available',
            ),
          );
        }
        requests.add(
          MaintenancePartRequest(
            productId: productId,
            warehouseId: item.isService ? null : line.warehouseId,
            quantity: int.tryParse(line.quantity.text.trim()) ?? 0,
            unitPrice: double.tryParse(line.unitPrice.text.trim()) ?? 0,
          ),
        );
      }
      final controller = context.read<MaintenanceController>();
      if (_editing) {
        await controller.updateDraft(
          orderId:
              widget.order?.id ??
              (throw StateError(
                t(
                  'أمر الصيانة غير متاح للتعديل',
                  'The maintenance order is unavailable for editing',
                ),
              )),
          warehouseId: _maintenanceWarehouseId(),
          pricingType: _pricingType,
          laborCost: double.tryParse(_labor.text.trim()) ?? 0,
          salePrice: double.tryParse(_price.text.trim()) ?? 0,
          parts: requests,
          currencyCode: _currency,
          maintenanceExpenseAccountId: null,
          notes: _notes.text.trim(),
          effectiveAt: _maintenanceDate,
          expectedUpdatedAt:
              widget.order?.updatedAt ??
              (throw StateError(
                t(
                  'تعذر تحديد نسخة أمر الصيانة الحالية. أعد فتح المستند.',
                  'Unable to determine the current maintenance order version. Reopen the document.',
                ),
              )),
        );
      } else {
        await controller.createDraftOrder(
          carId: carId,
          warehouseId: _maintenanceWarehouseId(),
          pricingType: _pricingType,
          laborCost: double.tryParse(_labor.text.trim()) ?? 0,
          salePrice: double.tryParse(_price.text.trim()) ?? 0,
          parts: requests,
          currencyCode: _currency,
          maintenanceExpenseAccountId: null,
          notes: _notes.text.trim(),
          effectiveAt: _maintenanceDate,
        );
      }
      if (mounted) AppWorkspaceWindowScope.closeCurrent(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: AppText(
            userFacingError(
              error,
              isArabic: _ar,
              arabicFallback: 'تعذر حفظ أمر الصيانة.',
              englishFallback: 'Unable to save maintenance order.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 44),
                  const SizedBox(height: 12),
                  AppText(_loadError ?? '', textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _bootstrap(force: true),
                    icon: const Icon(Icons.refresh_rounded),
                    label: AppText(t('إعادة المحاولة', 'Retry')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final inventory = context.watch<InventoryController>();
    final maintenance = context.watch<MaintenanceController>();
    final soldCars = maintenance.eligibleVehicles;
    MaintenanceVehicleOption? selectedVehicle;
    for (final vehicle in soldCars) {
      if (vehicle.carId == _carId) {
        selectedVehicle = vehicle;
        break;
      }
    }
    final editingOrder = widget.order;
    if (selectedVehicle == null && editingOrder != null) {
      selectedVehicle = MaintenanceVehicleOption(
        carId: editingOrder.carId,
        displayName: editingOrder.carName,
        customerId: editingOrder.customerId ?? '',
        customerName: editingOrder.customerName ?? '—',
        saleSequence: 0,
      );
    }

    return Scaffold(
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            KajRelationshipHero(
              eyebrow: t('تجربة خدمة راقية', 'PREMIUM SERVICE INTAKE'),
              title: _editing
                  ? t('تعديل أمر الصيانة', 'Edit maintenance order')
                  : t('إنشاء أمر صيانة جديد', 'Create a new maintenance order'),
              subtitle: t(
                'نموذج تشغيلي منظم للسيارة والعميل والخدمات والمواد والتسعير، مع الحفاظ على تسلسل المراحل والارتباطات المالية والمخزنية.',
                'A structured service intake for vehicle, customer, labor, materials, and pricing while preserving the complete operational and financial chain.',
              ),
              icon: Icons.precision_manufacturing_outlined,
              trailing: KajStatusBadge(
                label: _editing
                    ? t('وضع التعديل', 'EDIT MODE')
                    : t('مسودة جديدة', 'NEW DRAFT'),
                color: _editing
                    ? KajDesignTokens.warning
                    : KajDesignTokens.electricBlue,
                icon: _editing ? Icons.edit_outlined : Icons.add_task_rounded,
              ),
            ),
            const SizedBox(height: 12),
            KajWorkflowStepper(
              currentIndex: _editing ? 3 : 0,
              compact: MediaQuery.sizeOf(context).width < 1000,
              steps: <String>[
                t('المركبة', 'Vehicle'),
                t('الخدمات', 'Services'),
                t('المواد', 'Materials'),
                t('التسعير', 'Pricing'),
                t('المراجعة', 'Review'),
              ],
            ),
            const SizedBox(height: 12),
            if (_editing) ...[
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.sync_alt_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppText(
                          t(
                            'الحفظ يعكس أثر الصيانة السابق ثم يعيد إنشاء إذن الصرف والفاتورة والدفعات والقيود إلى المرحلة نفسها بالقيم المعدلة. تبقى السيارة المرتبطة ثابتة لحماية سجلها التاريخي.',
                            'Saving reverses the previous maintenance effect, then rebuilds the stock issue, invoice, payments, and journals to the same stage with the edited values. The linked vehicle remains fixed to protect its history.',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: _securedField(
                'carId',
                FormField<String>(
                  initialValue: _carId,
                  validator: (_) => _carId == null
                      ? t('اختر سيارة مباعة', 'Select a sold vehicle')
                      : null,
                  builder: (field) => InkWell(
                    onTap: _editing || soldCars.isEmpty
                        ? null
                        : () async {
                            final selected = await _selectVehicle(soldCars);
                            if (selected == null || !mounted) return;
                            setState(() => _carId = selected.carId);
                            field.didChange(selected.carId);
                          },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: t('السيارة المباعة', 'Sold vehicle'),
                        prefixIcon: const Icon(Icons.directions_car),
                        suffixIcon: const Icon(Icons.search),
                        errorText: field.errorText,
                      ),
                      child: AppText(
                        selectedVehicle == null
                            ? t(
                                'ابحث واختر السيارة المباعة',
                                'Search and select sold vehicle',
                              )
                            : _vehicleSummary(selectedVehicle),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (selectedVehicle != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppText(
                        selectedVehicle.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 6),
                      AppText(
                        '${t('العميل', 'Customer')}: ${selectedVehicle.customerName}',
                      ),
                      AppText(
                        '${t('تسلسل البيع', 'Sale sequence')}: ${selectedVehicle.saleSequence}',
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppText(
                          t(
                            'لا توجد سيارات مباعة متاحة للصيانة. اضغط تحديث لإعادة قراءة المبيعات والسيارات القديمة.',
                            'No sold vehicles are available. Refresh to reload sales and legacy sold vehicles.',
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _bootstrap(force: true),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 240,
                  child: _securedField(
                    'operationalDate',
                    InkWell(
                      onTap: () async {
                        final selected = await showDatePicker(
                          context: context,
                          initialDate: _maintenanceDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(DateTime.now().year + 2),
                        );
                        if (selected == null || !context.mounted) return;
                        final selectedTime = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(_maintenanceDate),
                        );
                        if (!mounted) return;
                        final time =
                            selectedTime ??
                            TimeOfDay.fromDateTime(_maintenanceDate);
                        setState(
                          () => _maintenanceDate = DateTime(
                            selected.year,
                            selected.month,
                            selected.day,
                            time.hour,
                            time.minute,
                          ),
                        );
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: t('التاريخ التشغيلي', 'Operational date'),
                          prefixIcon: const Icon(Icons.event_outlined),
                        ),
                        child: AppText(
                          '${_maintenanceDate.year.toString().padLeft(4, '0')}-'
                          '${_maintenanceDate.month.toString().padLeft(2, '0')}-'
                          '${_maintenanceDate.day.toString().padLeft(2, '0')} '
                          '${_maintenanceDate.hour.toString().padLeft(2, '0')}:'
                          '${_maintenanceDate.minute.toString().padLeft(2, '0')}',
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: _securedField(
                    'currencyCode',
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: SupportedCurrency.normalize(_currency),
                      validator: (value) => SupportedCurrency.isSupported(value)
                          ? null
                          : AppTranslation.translate('العملة مطلوبة'),
                      items: const [
                        DropdownMenuItem(value: 'USD', child: AppText('USD')),
                        DropdownMenuItem(value: 'IQD', child: AppText('IQD')),
                      ],
                      onChanged: _changeCurrency,
                      decoration: InputDecoration(
                        labelText: t('العملة', 'Currency'),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: _securedField(
                    'pricingType',
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _pricingType,
                      items: [
                        DropdownMenuItem(
                          value: 'paid',
                          child: AppText(t('مدفوعة', 'Paid')),
                        ),
                        DropdownMenuItem(
                          value: 'free',
                          child: AppText(t('مجانية', 'Free')),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _pricingType = v ?? 'paid'),
                      decoration: InputDecoration(
                        labelText: t('نوع الصيانة', 'Maintenance type'),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: _securedField(
                    'laborCost',
                    TextFormField(
                      controller: _labor,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        ThousandsInputFormatter(decimalDigits: 2),
                      ],
                      decoration: InputDecoration(
                        labelText: t('كلفة العمل', 'Labor cost'),
                      ),
                      validator: _nonNegative,
                    ),
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: _securedField(
                    'salePrice',
                    TextFormField(
                      controller: _price,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        ThousandsInputFormatter(decimalDigits: 2),
                      ],
                      enabled: _pricingType == 'paid',
                      decoration: InputDecoration(
                        labelText: t('سعر الفاتورة', 'Invoice price'),
                      ),
                      validator: _nonNegative,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: AppText(
                    t('مواد وخدمات الصيانة', 'Maintenance items and services'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FieldPermissionControl(
                  resource: 'maintenance',
                  field: 'items',
                  viewPermission: 'maintenance.view',
                  writePermission: _writePermission,
                  child: FilledButton.icon(
                    onPressed: () => _addLine(),
                    icon: const Icon(Icons.add),
                    label: AppText(t('إضافة بند', 'Add line')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...List.generate(_lines.length, (index) {
              final line = _lines[index];
              final item = _item(line.productId);
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 330,
                        child: _securedField(
                          'items',
                          DropdownMenu<String>(
                            width: 330,
                            enableFilter: true,
                            requestFocusOnTap: true,
                            initialSelection: line.productId,
                            label: AppText(t('المادة/الخدمة', 'Item/service')),
                            dropdownMenuEntries: _currencyItems(inventory)
                                .map(
                                  (e) => DropdownMenuEntry(
                                    value: e.id,
                                    label:
                                        '${e.name} • ${e.code} • ${e.isService ? t('خدمة', 'Service') : t('مخزني', 'Stock')} • ${e.salePrice} ${e.saleCurrency ?? e.currency}',
                                  ),
                                )
                                .toList(),
                            onSelected: (v) {
                              if (v == null) return;
                              final selected = _currencyItems(
                                inventory,
                              ).firstWhere((e) => e.id == v);
                              setState(() {
                                line.productId = v;
                                line.unitPrice.text = selected.salePrice
                                    .toStringAsFixed(2);
                                if (selected.isService) {
                                  line.warehouseId = null;
                                } else {
                                  line.warehouseId ??=
                                      inventory.warehouses.isEmpty
                                      ? null
                                      : inventory.warehouses.first.id;
                                }
                              });
                            },
                          ),
                        ),
                      ),
                      if (item != null && !item.isService)
                        SizedBox(
                          width: 260,
                          child: _securedField(
                            'itemWarehouse',
                            DropdownButtonFormField<String>(
                              isExpanded: true,
                              initialValue: line.warehouseId,
                              items: inventory.warehouses
                                  .map(
                                    (w) => DropdownMenuItem(
                                      value: w.id,
                                      child: AppText(w.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) =>
                                  setState(() => line.warehouseId = v),
                              decoration: InputDecoration(
                                labelText: t('مخزن السحب', 'Source warehouse'),
                              ),
                            ),
                          ),
                        ),
                      if (item?.isService == true)
                        Chip(
                          label: AppText(
                            t('خدمة بلا مخزون', 'Non-stock service'),
                          ),
                        ),
                      SizedBox(
                        width: 120,
                        child: _securedField(
                          'itemQuantity',
                          TextFormField(
                            controller: line.quantity,
                            keyboardType: TextInputType.number,
                            inputFormatters: <TextInputFormatter>[
                              ThousandsInputFormatter(decimalDigits: 0),
                            ],
                            decoration: InputDecoration(
                              labelText: t('الكمية', 'Quantity'),
                            ),
                            validator: _positiveInteger,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 150,
                        child: _securedField(
                          'itemPrice',
                          TextFormField(
                            controller: line.unitPrice,
                            keyboardType: TextInputType.number,
                            inputFormatters: <TextInputFormatter>[
                              ThousandsInputFormatter(decimalDigits: 2),
                            ],
                            decoration: InputDecoration(
                              labelText: t('سعر المستخدم', 'User price'),
                            ),
                            validator: _nonNegative,
                          ),
                        ),
                      ),
                      FieldPermissionControl(
                        resource: 'maintenance',
                        field: 'items',
                        viewPermission: 'maintenance.view',
                        writePermission: _writePermission,
                        child: IconButton(
                          onPressed: () => setState(() {
                            final removed = _lines.removeAt(index);
                            removed.dispose();
                          }),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 12),
            _securedField(
              'notes',
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: InputDecoration(labelText: t('ملاحظات', 'Notes')),
              ),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: AppText(t('حفظ المسودة', 'Save draft')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<InventoryModel?> _selectMaintenanceItem(
    List<InventoryModel> items,
  ) async {
    var query = '';
    String type = 'all';
    return showAppWorkspaceDialogBuilder<InventoryModel>(
      context: context,
      title: t(
        'اختيار مادة أو خدمة صيانة',
        'Select maintenance item or service',
      ),
      maxWidth: 860,
      maxHeight: 620,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final normalized = query.trim().toLowerCase();
          final filtered = items
              .where((item) {
                if (type == 'stock' && item.isService) return false;
                if (type == 'service' && !item.isService) return false;
                if (normalized.isEmpty) return true;
                return <String>[
                  item.name,
                  item.nameEn,
                  item.code,
                  item.sku,
                  item.barcode,
                  item.category,
                  item.description,
                ].join(' ').toLowerCase().contains(normalized);
              })
              .toList(growable: false);

          return AlertDialog(
            title: AppText(
              t(
                'اختيار مادة أو خدمة صيانة',
                'Select maintenance item or service',
              ),
            ),
            content: SizedBox(
              width: AppResponsive.dialogWidth(context, 800),
              height: AppResponsive.dialogHeight(context, 500),
              child: Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final search = TextField(
                        autofocus: true,
                        onChanged: (value) =>
                            setDialogState(() => query = value),
                        decoration: InputDecoration(
                          labelText: t(
                            'بحث بالاسم أو الرمز أو الباركود',
                            'Search name, code, or barcode',
                          ),
                          prefixIcon: const Icon(Icons.search_rounded),
                        ),
                      );
                      final filter = SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: 'all',
                            label: AppText(t('الكل', 'All')),
                          ),
                          ButtonSegment(
                            value: 'stock',
                            label: AppText(t('مواد مخزنية', 'Stock items')),
                          ),
                          ButtonSegment(
                            value: 'service',
                            label: AppText(t('خدمات', 'Services')),
                          ),
                        ],
                        selected: <String>{type},
                        showSelectedIcon: false,
                        onSelectionChanged: (values) =>
                            setDialogState(() => type = values.first),
                      );
                      if (constraints.maxWidth < 650) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [search, const SizedBox(height: 8), filter],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: search),
                          const SizedBox(width: 10),
                          filter,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: AppText(
                              t('لا توجد نتائج مطابقة', 'No matching results'),
                            ),
                          )
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 360,
                                  mainAxisExtent: 164,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                ),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              return Card(
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () =>
                                      AppWorkspaceWindowScope.closeCurrent(
                                        dialogContext,
                                        item,
                                      ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(11),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              item.isService
                                                  ? Icons.miscellaneous_services
                                                  : Icons.inventory_2_outlined,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: AppText(
                                                item.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 7),
                                        AppText(
                                          '${item.code} • ${item.category}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const Spacer(),
                                        AppText(
                                          item.isService
                                              ? t(
                                                  'خدمة غير مخزنية',
                                                  'Non-stock service',
                                                )
                                              : '${t('المتوفر', 'Available')}: ${item.availableQuantity} ${item.unit}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    AppWorkspaceWindowScope.closeCurrent(dialogContext),
                child: AppText(t('إلغاء', 'Cancel')),
              ),
            ],
          );
        },
      ),
    );
  }

  String _vehicleSummary(MaintenanceVehicleOption vehicle) {
    final details = <String>[
      [
        vehicle.brand,
        vehicle.model,
        vehicle.year?.toString(),
      ].whereType<String>().where((value) => value.trim().isNotEmpty).join(' '),
      if ((vehicle.chassis ?? '').isNotEmpty)
        '${t('رقم الشاصي', 'Chassis')}: ${vehicle.chassis}',
      if ((vehicle.plateNumber ?? '').isNotEmpty)
        '${t('رقم اللوحة', 'Plate number')}: ${vehicle.plateNumber}',
      '${t('العميل', 'Customer')}: ${vehicle.customerName}',
    ].where((value) => value.trim().isNotEmpty).toList();
    return details.isEmpty ? vehicle.displayName : details.join(' • ');
  }

  Future<MaintenanceVehicleOption?> _selectVehicle(
    List<MaintenanceVehicleOption> vehicles,
  ) async {
    var query = '';
    return showAppWorkspaceDialogBuilder<MaintenanceVehicleOption>(
      context: context,
      title: t('اختيار السيارة المباعة', 'Select sold vehicle'),
      maxWidth: 820,
      maxHeight: 640,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final normalized = query.trim().toLowerCase();
          final filtered = vehicles
              .where((vehicle) {
                if (normalized.isEmpty) return true;
                return [
                      vehicle.displayName,
                      vehicle.customerName,
                      vehicle.brand,
                      vehicle.model,
                      vehicle.year?.toString(),
                      vehicle.chassis,
                      vehicle.plateNumber,
                      vehicle.carNumber,
                      vehicle.color,
                    ]
                    .whereType<String>()
                    .join(' ')
                    .toLowerCase()
                    .contains(normalized);
              })
              .toList(growable: false);
          return AlertDialog(
            title: AppText(t('اختيار السيارة المباعة', 'Select sold vehicle')),
            content: SizedBox(
              width: AppResponsive.dialogWidth(context, 760),
              height: AppResponsive.dialogHeight(context, 520),
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    onChanged: (value) => setDialogState(() => query = value),
                    decoration: InputDecoration(
                      labelText: t(
                        'بحث بالموديل أو الشاصي أو اللوحة أو العميل',
                        'Search model, chassis, plate, or customer',
                      ),
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: AppText(
                              t('لا توجد نتائج مطابقة', 'No matching results'),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (_, index) {
                              final vehicle = filtered[index];
                              return ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.directions_car_outlined),
                                ),
                                title: AppText(
                                  [
                                        vehicle.brand,
                                        vehicle.model,
                                        vehicle.year?.toString(),
                                      ]
                                      .whereType<String>()
                                      .where((value) => value.trim().isNotEmpty)
                                      .join(' '),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: AppText(
                                  _vehicleSummary(vehicle),
                                  maxLines: 3,
                                ),
                                trailing: vehicle.carId == _carId
                                    ? const Icon(Icons.check_circle)
                                    : null,
                                onTap: () =>
                                    AppWorkspaceWindowScope.closeCurrent(
                                      dialogContext,
                                      vehicle,
                                    ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    AppWorkspaceWindowScope.closeCurrent(dialogContext),
                child: AppText(t('إلغاء', 'Cancel')),
              ),
            ],
          );
        },
      ),
    );
  }

  String? _nonNegative(String? value) {
    final number = double.tryParse(value?.trim() ?? '');
    return number == null || number < 0
        ? t('قيمة غير صحيحة', 'Invalid value')
        : null;
  }

  String? _positiveInteger(String? value) {
    final number = int.tryParse(value?.trim() ?? '');
    return number == null || number <= 0
        ? t('كمية غير صحيحة', 'Invalid quantity')
        : null;
  }
}

class _LineDraft {
  _LineDraft({
    required this.productId,
    required this.warehouseId,
    required int quantity,
    required double unitPrice,
  }) : quantity = TextEditingController(text: quantity.toString()),
       unitPrice = TextEditingController(text: unitPrice.toStringAsFixed(2));

  String? productId;
  String? warehouseId;
  final TextEditingController quantity;
  final TextEditingController unitPrice;

  void dispose() {
    quantity.dispose();
    unitPrice.dispose();
  }
}
