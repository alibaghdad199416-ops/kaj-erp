import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
import 'package:quality_line_erp/core/widgets/app_back_button.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/design_system/kaj_inventory_stage4_components.dart';
import 'package:quality_line_erp/design_system/kaj_shell_components.dart';
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

class AddCarPage extends StatefulWidget {
  const AddCarPage({super.key});

  @override
  State<AddCarPage> createState() => _AddCarPageState();
}

class _AddCarPageState extends State<AddCarPage> {
  final _formKey = GlobalKey<FormState>();

  Widget _securedField(String field, Widget child) => FieldPermissionControl(
    resource: 'cars',
    field: field,
    viewPermission: 'cars.view',
    writePermission: 'cars.create',
    child: child,
  );

  final brandController = TextEditingController();
  final modelController = TextEditingController();
  final yearController = TextEditingController();
  final colorController = TextEditingController();
  final chassisController = TextEditingController();
  final engineNumberController = TextEditingController();
  final plateNumberController = TextEditingController();
  final carNumberController = TextEditingController();
  final vehicleTypeController = TextEditingController();
  final purchaseDateController = TextEditingController();
  final costController = TextEditingController(text: '0');
  final salePriceController = TextEditingController(text: '0');
  final notesController = TextEditingController();

  String status = 'معرفة';
  String currency = 'IQD';
  String? _inventoryAssetAccountId;
  String? _salesCostExpenseAccountId;
  String? _salesRevenueIqdAccountId;
  String? _salesRevenueUsdAccountId;
  late final String _carId = const Uuid().v4();
  List<CarImageModel> _images = [];
  bool _isSaving = false;

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
    final ar = context.l10n.isArabic;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: AppText(ar ? 'إضافة سيارة' : 'Add vehicle'),
      ),
      body: Form(
        key: _formKey,
        child: KajInventoryScreen(
          children: <Widget>[
            KajInventoryPageHeader(
              titleAr: 'إضافة سيارة جديدة',
              titleEn: 'Create a new vehicle',
              subtitleAr:
                  'أدخل بيانات التعريف والتسعير والحسابات والصور ضمن نموذج موحد.',
              subtitleEn:
                  'Capture identity, pricing, accounting and imagery in one structured workflow.',
              icon: Icons.directions_car_filled_outlined,
            ),
            const SizedBox(height: 16),
            KajInventorySection(
              titleAr: 'الهوية والمواصفات',
              titleEn: 'Identity and specifications',
              icon: Icons.badge_outlined,
              child: KajInventoryResponsiveFields(
                children: <Widget>[
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
                ],
              ),
            ),
            const SizedBox(height: 16),
            KajInventorySection(
              titleAr: 'التسعير والحسابات',
              titleEn: 'Pricing and accounting',
              icon: Icons.account_balance_wallet_outlined,
              child: Column(
                children: <Widget>[
                  KajInventoryResponsiveFields(
                    children: <Widget>[
                      _securedField(
                        'currency',
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: currency,
                          decoration: InputDecoration(
                            labelText: AppTranslation.translate('العملة'),
                          ),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'IQD',
                              child: AppText('IQD'),
                            ),
                            DropdownMenuItem(
                              value: 'USD',
                              child: AppText('USD'),
                            ),
                          ],
                          onChanged: (value) {
                            final next = value ?? 'IQD';
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
                      _moneyField(
                        'الكلفة',
                        costController,
                        field: 'purchasePrice',
                      ),
                      _moneyField(
                        'سعر البيع',
                        salePriceController,
                        field: 'salePrice',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
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
                    writePermission: 'cars.create',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            KajInventorySection(
              titleAr: 'الملفات والملاحظات',
              titleEn: 'Media and notes',
              icon: Icons.photo_library_outlined,
              child: Column(
                children: <Widget>[
                  KajInventoryResponsiveFields(
                    children: <Widget>[
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
                      _securedField(
                        'status',
                        TextFormField(
                          initialValue: status,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: AppTranslation.translate('الحالة'),
                            helperText: AppTranslation.translate(
                              'تتغير الحالة تلقائياً حسب دورة الشراء والبيع والمخزون',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _securedField(
                    'images',
                    CarImagesEditor(
                      carId: _carId,
                      initialImages: const [],
                      onChanged: (images) => _images = images,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: KajPrimaryAction(
                label: ar ? 'حفظ السيارة' : 'Save vehicle',
                icon: Icons.save_outlined,
                busy: _isSaving,
                onPressed: _isSaving ? null : _saveCar,
              ),
            ),
            const SizedBox(height: 24),
          ],
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

  Future<void> _saveCar() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    if (!_validateAccountingAssignments()) return;

    setState(() => _isSaving = true);
    try {
      final car = CarModel(
        id: _carId,
        vehicleType: vehicleTypeController.text.trim(),
        brand: brandController.text.trim(),
        model: modelController.text.trim(),
        year: int.parse(yearController.text.trim()),
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
        imagePath: '',
        supplierName: null,
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
      await carsController.addCar(car);
      await imagesController.replaceImages(car.id, _images);

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
              arabicFallback: 'فشل حفظ السيارة.',
              englishFallback: 'Unable to save the vehicle.',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
