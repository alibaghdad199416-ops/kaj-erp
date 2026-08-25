import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
import 'package:quality_line_erp/core/widgets/app_back_button.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

import 'package:quality_line_erp/features/inventory/cars/controllers/cars_controller.dart';
import 'package:quality_line_erp/features/inventory/cars/controllers/car_images_controller.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_image_model.dart';
import 'package:quality_line_erp/features/inventory/cars/widgets/car_images_editor.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_model.dart';
import 'package:quality_line_erp/features/inventory/widgets/inventory_account_fields.dart';
import 'package:quality_line_erp/features/accounting/controllers/accounting_controller.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

class EditCarPage extends StatefulWidget {
  final CarModel car;

  const EditCarPage({super.key, required this.car});

  @override
  State<EditCarPage> createState() => _EditCarPageState();
}

class _EditCarPageState extends State<EditCarPage> {
  final _formKey = GlobalKey<FormState>();

  Widget _securedField(String field, Widget child) => FieldPermissionControl(
    resource: 'cars',
    field: field,
    viewPermission: 'cars.view',
    writePermission: 'cars.update',
    child: child,
  );

  late final TextEditingController brandController;
  late final TextEditingController modelController;
  late final TextEditingController yearController;
  late final TextEditingController colorController;
  late final TextEditingController chassisController;
  late final TextEditingController engineNumberController;
  late final TextEditingController plateNumberController;
  late final TextEditingController carNumberController;
  late final TextEditingController vehicleTypeController;
  late final TextEditingController purchaseDateController;
  late final TextEditingController costController;
  late final TextEditingController salePriceController;
  late final TextEditingController notesController;

  late String status;
  late String currency;
  String? _inventoryAssetAccountId;
  String? _salesCostExpenseAccountId;
  String? _salesRevenueIqdAccountId;
  String? _salesRevenueUsdAccountId;
  List<CarImageModel> _images = [];
  bool _imagesLoaded = false;

  @override
  void initState() {
    super.initState();

    brandController = TextEditingController(text: widget.car.brand);

    modelController = TextEditingController(text: widget.car.model);

    yearController = TextEditingController(text: widget.car.year.toString());

    colorController = TextEditingController(text: widget.car.color);

    chassisController = TextEditingController(text: widget.car.chassis);
    engineNumberController = TextEditingController(
      text: widget.car.engineNumber,
    );
    plateNumberController = TextEditingController(text: widget.car.plateNumber);
    carNumberController = TextEditingController(text: widget.car.carNumber);
    vehicleTypeController = TextEditingController(text: widget.car.vehicleType);

    purchaseDateController = TextEditingController(
      text: widget.car.purchaseDate ?? '',
    );
    costController = TextEditingController(
      text: widget.car.purchasePrice.toString(),
    );
    salePriceController = TextEditingController(
      text: widget.car.salePrice.toString(),
    );
    notesController = TextEditingController(text: widget.car.notes ?? '');

    status = widget.car.status;
    currency = widget.car.currency;
    _inventoryAssetAccountId = widget.car.inventoryAssetAccountId;
    _salesCostExpenseAccountId = widget.car.salesCostExpenseAccountId;
    _salesRevenueIqdAccountId = widget.car.salesRevenueIqdAccountId;
    _salesRevenueUsdAccountId = widget.car.salesRevenueUsdAccountId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = context.read<CarImagesController>();
      await controller.loadImages(widget.car.id, force: true);
      if (mounted) {
        setState(() {
          _images = controller.imagesFor(widget.car.id);
          _imagesLoaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    brandController.dispose();
    modelController.dispose();
    yearController.dispose();
    colorController.dispose();
    chassisController.dispose();
    engineNumberController.dispose();
    plateNumberController.dispose();
    carNumberController.dispose();
    vehicleTypeController.dispose();
    purchaseDateController.dispose();
    costController.dispose();
    salePriceController.dispose();
    notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),
          title: const AppText('تعديل السيارة'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _field('الماركة', brandController, field: 'brand'),
                _field('الموديل', modelController, field: 'model'),
                _field(
                  'السنة',
                  yearController,
                  field: 'year',
                  keyboardType: TextInputType.number,
                ),
                _field('اللون', colorController, field: 'color'),
                _field('رقم الشاصي', chassisController, field: 'chassis'),
                _field(
                  'رقم المحرك',
                  engineNumberController,
                  field: 'engineNumber',
                  required: false,
                ),
                _field(
                  'رقم اللوحة',
                  plateNumberController,
                  field: 'plateNumber',
                  required: false,
                ),
                _field(
                  'رقم السيارة',
                  carNumberController,
                  field: 'carNumber',
                  required: false,
                ),
                _field(
                  'نوع السيارة',
                  vehicleTypeController,
                  field: 'vehicleType',
                  required: false,
                ),
                _securedField(
                  'currency',
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: currency,
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate('العملة'),
                      border: const OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'IQD', child: AppText('IQD')),
                      DropdownMenuItem(value: 'USD', child: AppText('USD')),
                    ],
                    onChanged: (value) {
                      final next = value ?? currency;
                      setState(() {
                        if (currency != next) {
                          _inventoryAssetAccountId = null;
                          _salesCostExpenseAccountId = null;
                        }
                        currency = next;
                      });
                    },
                  ),
                ),
                const SizedBox(height: 15),
                _moneyField('الكلفة', costController, field: 'purchasePrice'),
                _moneyField(
                  'سعر البيع',
                  salePriceController,
                  field: 'salePrice',
                ),
                InventoryAccountFields(
                  currency: currency,
                  inventoryAssetAccountId: _inventoryAssetAccountId,
                  salesCostExpenseAccountId: _salesCostExpenseAccountId,
                  salesRevenueIqdAccountId: _salesRevenueIqdAccountId,
                  salesRevenueUsdAccountId: _salesRevenueUsdAccountId,
                  onInventoryAssetChanged: (value) =>
                      setState(() => _inventoryAssetAccountId = value),
                  onSalesCostExpenseChanged: (value) =>
                      setState(() => _salesCostExpenseAccountId = value),
                  onSalesRevenueIqdChanged: (value) =>
                      setState(() => _salesRevenueIqdAccountId = value),
                  onSalesRevenueUsdChanged: (value) =>
                      setState(() => _salesRevenueUsdAccountId = value),
                  permissionResource: 'cars',
                  viewPermission: 'cars.view',
                  writePermission: 'cars.update',
                ),
                const SizedBox(height: 15),
                _field(
                  'تاريخ الشراء',
                  purchaseDateController,
                  field: 'purchaseDate',
                  required: false,
                ),
                _field(
                  'الملاحظات',
                  notesController,
                  field: 'notes',
                  required: false,
                  maxLines: 3,
                ),
                const SizedBox(height: 15),
                _securedField(
                  'status',
                  TextFormField(
                    initialValue: status,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate('الحالة'),
                      helperText: AppTranslation.translate(
                        'الحالة محكومة تلقائياً بمستندات الشراء والبيع والمخزون',
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (_imagesLoaded)
                  _securedField(
                    'images',
                    CarImagesEditor(
                      carId: widget.car.id,
                      initialImages: _images,
                      onChanged: (images) => _images = images,
                    ),
                  )
                else
                  const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _updateCar,
                    child: const AppText('حفظ التعديلات'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    required String field,
    TextInputType keyboardType = TextInputType.text,
    bool required = true,
    int maxLines = 1,
  }) {
    return _securedField(
      field,
      Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          validator: (value) {
            final text = value?.trim() ?? '';
            if (required && text.isEmpty) {
              return AppTranslation.translate('يرجى إدخال $label');
            }
            if (text.isNotEmpty && keyboardType == TextInputType.number) {
              if (ThousandsInputFormatter.parse(text) == null) {
                return AppTranslation.translate('أدخل قيمة رقمية صحيحة');
              }
            }
            if (label.contains('العملة') &&
                text.isNotEmpty &&
                text.toUpperCase() != 'IQD' &&
                text.toUpperCase() != 'USD') {
              return AppTranslation.translate('العملة يجب أن تكون IQD أو USD');
            }
            return null;
          },

          inputFormatters: keyboardType == TextInputType.number
              ? <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly]
              : null,
          decoration: InputDecoration(
            labelText: AppTranslation.translate(label),
            border: const OutlineInputBorder(),
          ),
        ),
      ),
    );
  }

  Widget _moneyField(
    String label,
    TextEditingController controller, {
    required String field,
  }) {
    return _securedField(
      field,
      Padding(
        padding: const EdgeInsets.only(bottom: 15),
        child: TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            ThousandsInputFormatter(decimalDigits: 2),
          ],
          validator: (value) {
            final text = value?.trim() ?? '';
            if (text.isEmpty)
              return AppTranslation.translate('هذا الحقل مطلوب');
            final number = ThousandsInputFormatter.parse(text);
            if (number == null)
              return AppTranslation.translate('أدخل قيمة رقمية صحيحة');
            if (number < 0)
              return AppTranslation.translate('لا يمكن أن تكون القيمة سالبة');
            return null;
          },
          decoration: InputDecoration(
            labelText: AppTranslation.translate('$label ($currency)'),
            helperText: AppTranslation.translate('القيمة صفر مسموحة'),
            border: const OutlineInputBorder(),
          ),
        ),
      ),
    );
  }

  bool _validateAccountingAssignments() {
    final accounts = context.read<AccountingController>().accounts;
    AccountModel? accountById(String? id) {
      if (id == null || id.isEmpty) return null;
      for (final account in accounts) {
        if (account.id == id) return account;
      }
      return null;
    }

    final asset = accountById(_inventoryAssetAccountId);
    final expense = accountById(_salesCostExpenseAccountId);
    final revenueIqd = accountById(_salesRevenueIqdAccountId);
    final revenueUsd = accountById(_salesRevenueUsdAccountId);
    final normalizedCurrency = currency.toUpperCase();
    if (asset == null ||
        !asset.isActive ||
        asset.type.toLowerCase() != 'asset' ||
        asset.currency.toUpperCase() != normalizedCurrency) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('اختر حساب مخزون أصل فعالًا من نفس عملة السيارة.'),
        ),
      );
      return false;
    }
    if (expense == null ||
        !expense.isActive ||
        expense.type.toLowerCase() != 'expense' ||
        expense.currency.toUpperCase() != normalizedCurrency) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('اختر حساب كلفة/مصروف فعالًا من نفس عملة السيارة.'),
        ),
      );
      return false;
    }
    if (revenueIqd == null ||
        !revenueIqd.isActive ||
        revenueIqd.type.toLowerCase() != 'revenue' ||
        revenueIqd.currency.toUpperCase() != 'IQD') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('اختر حساب إيراد فعالًا بعملة IQD.')),
      );
      return false;
    }
    if (revenueUsd == null ||
        !revenueUsd.isActive ||
        revenueUsd.type.toLowerCase() != 'revenue' ||
        revenueUsd.currency.toUpperCase() != 'USD') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('اختر حساب إيراد فعالًا بعملة USD.')),
      );
      return false;
    }
    return true;
  }

  Future<void> _updateCar() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (!_validateAccountingAssignments()) return;

    final updatedCar = CarModel(
      id: widget.car.id,
      vehicleType: vehicleTypeController.text.trim(),
      brand: brandController.text.trim(),
      model: modelController.text.trim(),
      year: int.parse(yearController.text),
      color: colorController.text.trim(),
      chassis: chassisController.text.trim(),
      engineNumber: engineNumberController.text.trim(),
      plateNumber: plateNumberController.text.trim(),
      carNumber: carNumberController.text.trim(),
      purchasePrice: double.parse(costController.text.trim()),
      salePrice: double.parse(salePriceController.text.trim()),
      currency: currency,
      costCurrency: currency,
      saleCurrency: currency,
      status: status,
      imagePath: widget.car.imagePath,
      maintenanceCost: widget.car.maintenanceCost,
      warehouseId: widget.car.warehouseId,
      supplierId: widget.car.supplierId,
      supplierName: widget.car.supplierName,
      purchaseDate: purchaseDateController.text.trim().isEmpty
          ? null
          : purchaseDateController.text.trim(),
      notes: notesController.text.trim().isEmpty
          ? null
          : notesController.text.trim(),
      inventoryAssetAccountId: _inventoryAssetAccountId,
      salesCostExpenseAccountId: _salesCostExpenseAccountId,
      salesRevenueIqdAccountId: _salesRevenueIqdAccountId,
      salesRevenueUsdAccountId: _salesRevenueUsdAccountId,
    );

    final carsController = context.read<CarsController>();
    final imagesController = context.read<CarImagesController>();
    await carsController.updateCar(updatedCar);
    await imagesController.replaceImages(updatedCar.id, _images);

    if (!mounted) return;

    AppWorkspaceWindowScope.closeCurrent(context);
  }
}
