import 'dart:async';
import 'dart:convert';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import 'package:quality_line_erp/core/widgets/app_back_button.dart';
import 'package:quality_line_erp/core/media/app_image_service.dart';
import 'package:quality_line_erp/features/inventory/controllers/inventory_controller.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_model.dart';
import 'package:quality_line_erp/features/accounting/controllers/accounting_controller.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

class AddInventoryPage extends StatefulWidget {
  const AddInventoryPage({super.key, this.item, this.initialImages = const []});

  final InventoryModel? item;
  final List<String> initialImages;

  @override
  State<AddInventoryPage> createState() => _AddInventoryPageState();
}

class _AddInventoryPageState extends State<AddInventoryPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _unitController = TextEditingController(text: 'قطعة');
  final _quantityController = TextEditingController(text: '0');
  final _minimumController = TextEditingController(text: '0');
  final _costController = TextEditingController(text: '0');
  final _salePriceController = TextEditingController(text: '0');
  final _notesController = TextEditingController();
  String? _groupId;
  String? _warehouseId;
  String _currency = 'IQD';
  String _itemType = 'stock';
  String? _inventoryAssetAccountId;
  String? _salesCostExpenseAccountId;
  String? _salesRevenueIqdAccountId;
  String? _salesRevenueUsdAccountId;
  final List<String> _images = [];
  bool _saving = false;
  bool _loadingOpeningBalance = false;
  bool _pickingImages = false;
  bool _loadingAccounts = false;
  String? _accountLoadError;

  bool get _isEditing => widget.item != null;

  String get _writePermission =>
      _isEditing ? 'inventory.update' : 'inventory.create';

  Widget _securedField(String field, Widget child) => FieldPermissionControl(
    resource: 'inventory',
    field: field,
    viewPermission: 'inventory.view',
    writePermission: _writePermission,
    child: child,
  );

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item != null) {
      _nameController.text = item.name;
      _unitController.text = item.unit;
      _quantityController.text = item.quantity.toString();
      _minimumController.text = item.minQuantity.toString();
      _costController.text = item.unitCost.toString();
      _salePriceController.text = item.salePrice.toString();
      _currency = item.currency;
      _itemType = item.itemType;
      _inventoryAssetAccountId = item.inventoryAssetAccountId;
      _salesCostExpenseAccountId = item.salesCostExpenseAccountId;
      _salesRevenueIqdAccountId = item.salesRevenueIqdAccountId;
      _salesRevenueUsdAccountId = item.salesRevenueUsdAccountId;
      _notesController.text = item.notes ?? '';
      _groupId = item.groupId;
      if (widget.initialImages.isNotEmpty) {
        _images.addAll(widget.initialImages);
      } else if ((item.imageBase64 ?? '').isNotEmpty) {
        _images.add(item.imageBase64!);
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_ensureAccountingLoaded());
      if (item != null) unawaited(_loadOpeningBalance());
    });
  }

  Future<void> _ensureAccountingLoaded({bool force = false}) async {
    if (!mounted || _loadingAccounts) return;
    final accounting = context.read<AccountingController>();
    if (!force && accounting.accounts.isNotEmpty) return;
    setState(() {
      _loadingAccounts = true;
      _accountLoadError = null;
    });
    try {
      await accounting.ensureAccountsLoaded(force: force);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _accountLoadError = userFacingError(
          error,
          isArabic: context.l10n.isArabic,
          arabicFallback: 'تعذر تحميل حسابات المخزون والكلفة.',
          englishFallback: 'Unable to load inventory and cost accounts.',
        );
      });
    } finally {
      if (mounted) setState(() => _loadingAccounts = false);
    }
  }

  Future<void> _loadOpeningBalance({String? warehouseId}) async {
    final item = widget.item;
    if (item == null || !mounted) return;
    setState(() => _loadingOpeningBalance = true);
    try {
      final controller = context.read<InventoryController>();
      final stocks = await controller.getProductStocks(item.id);
      if (!mounted) return;
      final selectedId =
          warehouseId ??
          _warehouseId ??
          (stocks.isNotEmpty ? stocks.first.warehouseId : null);
      final matching = stocks.where((stock) => stock.warehouseId == selectedId);
      setState(() {
        _warehouseId = selectedId;
        _quantityController.text = matching.isEmpty
            ? '0'
            : matching.first.quantity.toString();
      });
    } finally {
      if (mounted) setState(() => _loadingOpeningBalance = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _unitController.dispose();
    _quantityController.dispose();
    _minimumController.dispose();
    _costController.dispose();
    _salePriceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    if (_pickingImages) return;
    setState(() => _pickingImages = true);
    try {
      final remaining = (12 - _images.length).clamp(0, 12).toInt();
      if (remaining == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
              context.l10n.isArabic
                  ? 'الحد الأعلى 12 صورة للمنتج.'
                  : 'A product can have up to 12 images.',
            ),
          ),
        );
        return;
      }
      final batch = await AppImageService.pickManyAndProcess(
        maxFiles: remaining,
        maxWidth: 1400,
        maxHeight: 1400,
        quality: 82,
        maxOutputBytes: 240 * 1024,
      );
      if (!mounted) return;
      if (batch.images.isNotEmpty) {
        setState(() {
          _images.addAll(batch.images.map((image) => image.base64));
        });
      }
      if (batch.rejectedCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
              context.l10n.isArabic
                  ? 'أضيفت الصور الصالحة، وتعذر قبول ${batch.rejectedCount} صورة.'
                  : 'Valid images were added; ${batch.rejectedCount} image(s) could not be accepted.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } on FormatException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            context.l10n.isArabic
                ? 'تعذر قراءة الصور أو ضغطها. استخدم JPG أو PNG أو WEBP.'
                : 'The images could not be read or compressed. Use JPG, PNG, or WEBP.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _pickingImages = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_groupId == null || (_itemType == 'stock' && _warehouseId == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            _itemType == 'stock'
                ? 'يرجى اختيار المجموعة والمخزن'
                : 'يرجى اختيار المجموعة',
          ),
        ),
      );
      return;
    }

    final accounts = context.read<AccountingController>().accounts;
    AccountModel? assetAccount;
    AccountModel? expenseAccount;
    final revenueIqdAccount = _firstAccount(
      accounts,
      _salesRevenueIqdAccountId,
    );
    final revenueUsdAccount = _firstAccount(
      accounts,
      _salesRevenueUsdAccountId,
    );
    if (revenueIqdAccount == null ||
        !revenueIqdAccount.isActive ||
        revenueIqdAccount.type.toLowerCase() != 'revenue' ||
        revenueIqdAccount.currency.toUpperCase() != 'IQD') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('اختر حساب إيراد فعالًا بعملة IQD.')),
      );
      return;
    }
    if (revenueUsdAccount == null ||
        !revenueUsdAccount.isActive ||
        revenueUsdAccount.type.toLowerCase() != 'revenue' ||
        revenueUsdAccount.currency.toUpperCase() != 'USD') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('اختر حساب إيراد فعالًا بعملة USD.')),
      );
      return;
    }
    if (_itemType == 'stock') {
      assetAccount = _firstAccount(accounts, _inventoryAssetAccountId);
      expenseAccount = _firstAccount(accounts, _salesCostExpenseAccountId);
      if (assetAccount == null ||
          !assetAccount.isActive ||
          assetAccount.type.toLowerCase() != 'asset' ||
          assetAccount.currency.toUpperCase() != _currency.toUpperCase()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: AppText('اختر حساب أصل مخزون فعالًا من نفس العملة.'),
          ),
        );
        return;
      }
      if (expenseAccount == null ||
          !expenseAccount.isActive ||
          expenseAccount.type.toLowerCase() != 'expense' ||
          expenseAccount.currency.toUpperCase() != _currency.toUpperCase()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: AppText(
              'اختر حساب تكلفة مبيعات من المصاريف وبنفس العملة.',
            ),
          ),
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final group = context
          .read<InventoryController>()
          .groups
          .where((item) => item.id == _groupId)
          .first;
      final existing = widget.item;
      final product = InventoryModel(
        id: existing?.id ?? const Uuid().v4(),
        name: _nameController.text.trim(),
        // Retired product fields are deliberately cleared on every save.
        // They remain in the model only for backward-compatible decoding of old rows.
        nameEn: '',
        description: '',
        code: '',
        sku: '',
        barcode: '',
        serialNumber: '',
        category: group.name,
        groupId: group.id,
        unit: _unitController.text.trim(),
        quantity: _itemType == 'service'
            ? 0
            : (existing?.quantity ??
                  (int.tryParse(_quantityController.text.trim()) ?? 0)),
        purchasePrice: _itemType == 'service'
            ? 0
            : double.parse(_costController.text.trim()),
        landedCost: 0,
        unitCost: _itemType == 'service'
            ? 0
            : double.parse(_costController.text.trim()),
        salePrice: double.parse(_salePriceController.text.trim()),
        currency: _currency,
        costCurrency: _currency,
        saleCurrency: _currency,
        taxRate: existing?.taxRate ?? 0,
        minQuantity: int.tryParse(_minimumController.text.trim()) ?? 0,
        expectedIncoming: existing?.expectedIncoming ?? 0,
        expectedOutgoing: existing?.expectedOutgoing ?? 0,
        date: existing?.date ?? now,
        imageBase64: _images.isEmpty ? null : _images.first,
        notes: _notesController.text.trim(),
        isActive: existing?.isActive ?? true,
        itemType: _itemType,
        inventoryAssetAccountId: _itemType == 'stock'
            ? _inventoryAssetAccountId
            : null,
        salesCostExpenseAccountId: _itemType == 'stock'
            ? _salesCostExpenseAccountId
            : null,
        salesRevenueIqdAccountId: _salesRevenueIqdAccountId,
        salesRevenueUsdAccountId: _salesRevenueUsdAccountId,
      );
      final inventory = context.read<InventoryController>();
      if (_isEditing) {
        await inventory.updateInventory(
          product,
          imagesBase64: _images,
          warehouseId: _itemType == 'stock' ? _warehouseId : null,
          openingQuantity: _itemType == 'stock'
              ? int.tryParse(_quantityController.text.trim())
              : null,
        );
      } else {
        await inventory.addInventory(
          product,
          warehouseId: _itemType == 'stock' ? _warehouseId : null,
          openingQuantity: _itemType == 'stock'
              ? (int.tryParse(_quantityController.text.trim()) ?? 0)
              : 0,
          imagesBase64: _images,
        );
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(
              error,
              isArabic: context.l10n.isArabic,
              arabicFallback: 'تعذر حفظ المنتج.',
              englishFallback: 'Unable to save the product.',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<InventoryController>();
    final accounting = context.watch<AccountingController>();
    final assetAccounts = accounting.accounts
        .where(
          (a) => a.isActive && a.type == 'asset' && a.currency == _currency,
        )
        .toList();
    final expenseAccounts = accounting.accounts
        .where(
          (a) => a.isActive && a.type == 'expense' && a.currency == _currency,
        )
        .toList();
    final revenueIqdAccounts = accounting.accounts
        .where((a) => a.isActive && a.type == 'revenue' && a.currency == 'IQD')
        .toList();
    final revenueUsdAccounts = accounting.accounts
        .where((a) => a.isActive && a.type == 'revenue' && a.currency == 'USD')
        .toList();
    if (_groupId == null && controller.groups.isNotEmpty) {
      _groupId = controller.groups.first.id;
    }
    if (_warehouseId == null && controller.warehouses.isNotEmpty) {
      _warehouseId = controller.warehouses.first.id;
    }

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: AppText(
          _isEditing ? 'تعديل المادة أو الخدمة' : 'إضافة مادة أو خدمة',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _section(
              title: 'بيانات المنتج',
              icon: Icons.inventory_2_outlined,
              child: Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _field(
                    _nameController,
                    'اسم المنتج',
                    field: 'name',
                    required: true,
                  ),
                  _field(
                    _unitController,
                    'وحدة القياس',
                    field: 'unit',
                    required: true,
                  ),
                  _dropdown(
                    field: 'itemType',
                    label: 'نوع الإدخال',
                    value: _itemType,
                    items: const [
                      DropdownMenuItem(
                        value: 'stock',
                        child: AppText('مادة مخزنية'),
                      ),
                      DropdownMenuItem(
                        value: 'service',
                        child: AppText('خدمة غير مخزنية'),
                      ),
                    ],
                    onChanged: (value) => setState(() {
                      _itemType = value ?? 'stock';
                      if (_itemType == 'service') {
                        _quantityController.text = '0';
                        _minimumController.text = '0';
                        _costController.text = '0';
                        _warehouseId = null;
                        _inventoryAssetAccountId = null;
                        _salesCostExpenseAccountId = null;
                      }
                    }),
                  ),
                  _dropdown(
                    field: 'groupId',
                    label: 'المجموعة المخزنية',
                    value: _groupId,
                    items: controller.groups
                        .map(
                          (group) => DropdownMenuItem(
                            value: group.id,
                            child: AppText('${group.code} — ${group.name}'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _groupId = value),
                  ),
                  if (_itemType == 'stock')
                    _dropdown(
                      field: 'warehouseId',
                      label: 'مخزن الرصيد الافتتاحي',
                      value: _warehouseId,
                      items: controller.warehouses
                          .map(
                            (warehouse) => DropdownMenuItem(
                              value: warehouse.id,
                              child: AppText(
                                '${warehouse.code} — ${warehouse.name}',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) async {
                        setState(() => _warehouseId = value);
                        if (_isEditing)
                          await _loadOpeningBalance(warehouseId: value);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'الرصيد والضبط المخزني',
              icon: Icons.inventory_outlined,
              child: Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  if (_itemType == 'stock')
                    _numberField(
                      _quantityController,
                      field: 'quantity',
                      _isEditing
                          ? 'الرصيد الافتتاحي للمخزن المحدد'
                          : 'الكمية الافتتاحية',
                      integer: true,
                      enabled: !_loadingOpeningBalance,
                    ),
                  if (_itemType == 'stock')
                    _numberField(
                      _minimumController,
                      field: 'minQuantity',
                      'حد إعادة الطلب',
                      integer: true,
                    ),
                  _dropdown(
                    field: 'currency',
                    label: 'العملة',
                    value: _currency,
                    items: const [
                      DropdownMenuItem(value: 'IQD', child: AppText('IQD')),
                      DropdownMenuItem(value: 'USD', child: AppText('USD')),
                    ],
                    onChanged: (value) {
                      final next = value ?? 'IQD';
                      setState(() {
                        if (_currency != next) {
                          _inventoryAssetAccountId = null;
                          _salesCostExpenseAccountId = null;
                        }
                        _currency = next;
                      });
                    },
                  ),
                  if (_itemType == 'stock')
                    _numberField(
                      _costController,
                      'الكلفة ($_currency)',
                      field: 'unitCost',
                    ),
                  _numberField(
                    _salePriceController,
                    'سعر البيع ($_currency)',
                    field: 'salePrice',
                  ),
                  if (_itemType == 'stock') ...[
                    _accountDropdown(
                      field: 'inventoryAssetAccountId',
                      label: 'حساب أصل المخزون (مدين عند الشراء)',
                      value: _inventoryAssetAccountId,
                      accounts: assetAccounts,
                      onChanged: (value) =>
                          setState(() => _inventoryAssetAccountId = value),
                    ),
                    _accountDropdown(
                      field: 'salesCostExpenseAccountId',
                      label: 'حساب تكلفة البيع (مدين عند البيع)',
                      value: _salesCostExpenseAccountId,
                      accounts: expenseAccounts,
                      onChanged: (value) =>
                          setState(() => _salesCostExpenseAccountId = value),
                    ),
                  ],
                  _accountDropdown(
                    field: 'salesRevenueIqdAccountId',
                    label: 'حساب إيراد البيع بالدينار IQD',
                    value: _salesRevenueIqdAccountId,
                    accounts: revenueIqdAccounts,
                    onChanged: (value) =>
                        setState(() => _salesRevenueIqdAccountId = value),
                  ),
                  _accountDropdown(
                    field: 'salesRevenueUsdAccountId',
                    label: 'حساب إيراد البيع بالدولار USD',
                    value: _salesRevenueUsdAccountId,
                    accounts: revenueUsdAccounts,
                    onChanged: (value) =>
                        setState(() => _salesRevenueUsdAccountId = value),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: AppText(
                      AppTranslation.translate(
                        _itemType == 'service'
                            ? 'الخدمة لا تملك كمية ولا تُشترى، وتستخدم في البيع والصيانة بالسعر المحدد.'
                            : 'الكلفة وسعر البيع إلزاميان، ويمكن إدخال صفر.',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'صور المنتج',
              icon: Icons.photo_library_outlined,
              child: _securedField(
                'image',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickingImages ? null : _pickImages,
                      icon: _pickingImages
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_photo_alternate_outlined),
                      label: const AppText('اختيار صور متعددة'),
                    ),
                    if (_images.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 92,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _images.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.memory(
                                    base64Decode(_images[index]),
                                    width: 92,
                                    height: 92,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 3,
                                  right: 3,
                                  child: InkWell(
                                    onTap: () =>
                                        setState(() => _images.removeAt(index)),
                                    child: const CircleAvatar(
                                      radius: 12,
                                      backgroundColor: Colors.black54,
                                      child: Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _section(
              title: 'ملاحظات',
              icon: Icons.notes_outlined,
              child: _securedField(
                'notes',
                TextFormField(
                  controller: _notesController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: AppTranslation.translate(
                      'ملاحظات المنتج أو التوافق مع السيارات...',
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SizedBox(
                width: 220,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: AppText(
                    _saving
                        ? 'جارٍ الحفظ...'
                        : (_isEditing ? 'حفظ التعديلات' : 'حفظ المنتج'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                AppText(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    required String field,
    bool required = false,
  }) {
    return _securedField(
      field,
      SizedBox(
        width: 310,
        child: TextFormField(
          controller: controller,
          validator: (value) {
            final text = value?.trim() ?? '';
            if (required && text.isEmpty) {
              return AppTranslation.translate('هذا الحقل مطلوب');
            }
            if (label.contains('العملة') &&
                text.isNotEmpty &&
                text.toUpperCase() != 'IQD' &&
                text.toUpperCase() != 'USD') {
              return AppTranslation.translate('العملة يجب أن تكون IQD أو USD');
            }
            return null;
          },
          decoration: InputDecoration(labelText: label),
        ),
      ),
    );
  }

  Widget _numberField(
    TextEditingController controller,
    String label, {
    required String field,
    ValueChanged<String>? onChanged,
    bool integer = false,
    bool enabled = true,
  }) {
    return _securedField(
      field,
      SizedBox(
        width: 250,
        child: TextFormField(
          controller: controller,
          enabled: enabled,
          keyboardType: TextInputType.numberWithOptions(decimal: !integer),
          inputFormatters: <TextInputFormatter>[
            ThousandsInputFormatter(decimalDigits: 2),
          ],
          onChanged: onChanged,
          validator: (value) {
            final text = value?.trim() ?? '';
            final number = integer ? int.tryParse(text) : double.tryParse(text);
            if (number == null) {
              return 'أدخل قيمة رقمية صحيحة';
            }
            if (number < 0) {
              return 'لا يمكن أن تكون القيمة سالبة';
            }
            return null;
          },
          decoration: InputDecoration(labelText: label),
        ),
      ),
    );
  }

  Widget _dropdown({
    required String field,
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return _securedField(
      field,
      SizedBox(
        width: 310,
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: value,
          items: items,
          onChanged: onChanged,
          decoration: InputDecoration(labelText: label),
        ),
      ),
    );
  }

  AccountModel? _firstAccount(List<AccountModel> accounts, String? id) {
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  Widget _accountDropdown({
    required String field,
    required String label,
    required String? value,
    required List<AccountModel> accounts,
    required ValueChanged<String?> onChanged,
  }) {
    Widget protect(Widget child) => _securedField(field, child);
    final safeValue = accounts.any((a) => a.id == value) ? value : null;
    if (_loadingAccounts) {
      return protect(
        SizedBox(
          width: 420,
          child: InputDecorator(
            decoration: InputDecoration(labelText: label),
            child: const LinearProgressIndicator(),
          ),
        ),
      );
    }
    if (accounts.isEmpty) {
      return protect(
        SizedBox(
          width: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: () => _ensureAccountingLoaded(force: true),
                icon: const Icon(Icons.refresh_rounded),
                label: AppText(
                  '${AppTranslation.translate('تحميل الحسابات المتاحة')} ($_currency)',
                ),
              ),
              if (_accountLoadError != null) ...[
                const SizedBox(height: 6),
                AppText(
                  _accountLoadError!,
                  style: const TextStyle(color: Colors.red, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      );
    }
    return protect(
      SizedBox(
        width: 420,
        child: DropdownButtonFormField<String>(
          key: ValueKey(
            'product-account-$label-$_currency-${safeValue ?? ''}-${accounts.length}',
          ),
          initialValue: safeValue,
          isExpanded: true,
          items: accounts
              .map(
                (a) => DropdownMenuItem(
                  value: a.id,
                  child: AppText('${a.code} — ${a.name} (${a.currency})'),
                ),
              )
              .toList(),
          onChanged: onChanged,
          validator: (selected) => selected == null || selected.isEmpty
              ? AppTranslation.translate('هذا الحقل مطلوب')
              : null,
          decoration: InputDecoration(labelText: label),
        ),
      ),
    );
  }
}
