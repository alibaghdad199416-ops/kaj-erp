import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quality_line_erp/core/widgets/app_back_button.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/base64_photo_picker.dart';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

import 'package:quality_line_erp/features/business_partners/suppliers/controllers/suppliers_controller.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/models/supplier_model.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/finance/supported_currency.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

class AddSupplierPage extends StatefulWidget {
  const AddSupplierPage({super.key, this.supplier});

  final SupplierModel? supplier;

  bool get isEditing => supplier != null;

  @override
  State<AddSupplierPage> createState() => _AddSupplierPageState();
}

class _AddSupplierPageState extends State<AddSupplierPage> {
  final _formKey = GlobalKey<FormState>();

  String get _writePermission =>
      widget.isEditing ? 'suppliers.update' : 'suppliers.create';

  Widget _securedField(String field, Widget child) => FieldPermissionControl(
    resource: 'suppliers',
    field: field,
    viewPermission: 'suppliers.view',
    writePermission: _writePermission,
    child: child,
  );

  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _alternativePhoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _companyNameController;
  late final TextEditingController _taxNumberController;
  late final TextEditingController _openingBalanceController;
  late final TextEditingController _notesController;

  String _currency = 'USD';
  bool _isActive = true;
  bool _isSaving = false;
  String? _photoBase64;

  @override
  void initState() {
    super.initState();

    final supplier = widget.supplier;

    _nameController = TextEditingController(text: supplier?.name ?? '');

    _phoneController = TextEditingController(text: supplier?.phone ?? '');

    _alternativePhoneController = TextEditingController(
      text: supplier?.alternativePhone ?? '',
    );

    _addressController = TextEditingController(text: supplier?.address ?? '');

    _companyNameController = TextEditingController(
      text: supplier?.companyName ?? '',
    );

    _taxNumberController = TextEditingController(
      text: supplier?.taxNumber ?? '',
    );

    _openingBalanceController = TextEditingController(
      text: supplier == null || supplier.openingBalance == 0
          ? ''
          : supplier.openingBalance.toString(),
    );

    _notesController = TextEditingController(text: supplier?.notes ?? '');

    _currency = SupportedCurrency.initial(
      isNew: supplier == null,
      stored: supplier?.currency,
    );
    _isActive = supplier?.isActive ?? true;
    _photoBase64 = supplier?.photoBase64;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _alternativePhoneController.dispose();
    _addressController.dispose();
    _companyNameController.dispose();
    _taxNumberController.dispose();
    _openingBalanceController.dispose();
    _notesController.dispose();

    super.dispose();
  }

  Future<void> _saveSupplier() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final existingSupplier = widget.supplier;

      final openingBalance =
          double.tryParse(
            _openingBalanceController.text.trim().replaceAll(',', ''),
          ) ??
          0;

      final supplier = SupplierModel(
        id: existingSupplier?.id ?? const Uuid().v4(),
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        alternativePhone: _nullableText(_alternativePhoneController.text),
        address: _nullableText(_addressController.text),
        companyName: _nullableText(_companyNameController.text),
        taxNumber: _nullableText(_taxNumberController.text),
        notes: _nullableText(_notesController.text),
        openingBalance: openingBalance,
        currency: _currency,
        createdAt: existingSupplier?.createdAt ?? DateTime.now(),
        updatedAt: existingSupplier == null ? null : DateTime.now(),
        isActive: _isActive,
        photoBase64: _photoBase64,
      );

      final controller = context.read<SuppliersController>();

      if (widget.isEditing) {
        await controller.updateSupplier(supplier);
      } else {
        await controller.addSupplier(supplier);
      }

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop<SupplierModel>(supplier);
    } catch (error) {
      if (!mounted) {
        return;
      }

      final controller = context.read<SuppliersController>();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            controller.errorMessage ??
                userFacingError(
                  error,
                  isArabic: context.l10n.isArabic,
                  arabicFallback: 'تعذر حفظ بيانات المورد.',
                  englishFallback: 'Unable to save supplier data.',
                ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String? _nullableText(String value) {
    final normalizedValue = value.trim();

    if (normalizedValue.isEmpty) {
      return null;
    }

    return normalizedValue;
  }

  String? _requiredValidator(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return AppTranslation.translate('يرجى إدخال $fieldName');
    }

    return null;
  }

  String? _phoneValidator(String? value) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) return null;

    if (phone.length < 7) {
      return AppTranslation.translate('رقم الهاتف قصير جدًا');
    }

    return null;
  }

  String? _openingBalanceValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }

    final normalizedValue = value.trim().replaceAll(',', '');

    final amount = double.tryParse(normalizedValue);

    if (amount == null) {
      return AppTranslation.translate('يرجى إدخال مبلغ صحيح');
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        appBar: AppBar(
          leading: const AppBackButton(),
          title: AppText(widget.isEditing ? 'تعديل المورد' : 'إضافة مورد'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 16),
                      _securedField(
                        'photo',
                        Base64PhotoPicker(
                          value: _photoBase64,
                          label: 'صورة المورد',
                          onChanged: (value) =>
                              setState(() => _photoBase64 = value),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildBasicInformationCard(),
                      const SizedBox(height: 16),
                      _buildFinancialInformationCard(),
                      const SizedBox(height: 16),
                      _buildAdditionalInformationCard(),
                      const SizedBox(height: 24),
                      _buildActions(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      elevation: 0,
      color: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white,
              child: Icon(
                Icons.local_shipping_outlined,
                color: Colors.black,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    widget.isEditing
                        ? 'تحديث بيانات المورد'
                        : 'تسجيل مورد جديد',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const AppText(
                    'أدخل المعلومات الأساسية والمالية للمورد.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicInformationCard() {
    return _sectionCard(
      title: 'المعلومات الأساسية',
      icon: Icons.person_outline,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 650;

          if (isWide) {
            return Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildNameField()),
                    const SizedBox(width: 16),
                    Expanded(child: _buildCompanyField()),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildPhoneField()),
                    const SizedBox(width: 16),
                    Expanded(child: _buildAlternativePhoneField()),
                  ],
                ),
                const SizedBox(height: 16),
                _buildAddressField(),
              ],
            );
          }

          return Column(
            children: [
              _buildNameField(),
              const SizedBox(height: 16),
              _buildCompanyField(),
              const SizedBox(height: 16),
              _buildPhoneField(),
              const SizedBox(height: 16),
              _buildAlternativePhoneField(),
              const SizedBox(height: 16),
              _buildAddressField(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFinancialInformationCard() {
    return _sectionCard(
      title: 'المعلومات المالية',
      icon: Icons.account_balance_wallet_outlined,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 650;

          final balanceField = _securedField(
            'openingBalance',
            TextFormField(
              controller: _openingBalanceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),

              inputFormatters: <TextInputFormatter>[
                ThousandsInputFormatter(decimalDigits: 2),
              ],
              decoration: InputDecoration(
                labelText: AppTranslation.translate('الرصيد الافتتاحي'),
                hintText: AppTranslation.translate('0'),
                prefixIcon: Icon(Icons.payments_outlined),
                border: OutlineInputBorder(),
              ),
              validator: _openingBalanceValidator,
            ),
          );

          final currencyField = _securedField(
            'currency',
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: SupportedCurrency.normalize(_currency),
              validator: (value) => SupportedCurrency.isSupported(value)
                  ? null
                  : AppTranslation.translate('العملة مطلوبة'),
              decoration: InputDecoration(
                labelText: AppTranslation.translate('العملة'),
                prefixIcon: Icon(Icons.currency_exchange),
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: 'USD',
                  child: AppText('دولار أمريكي - USD'),
                ),
                DropdownMenuItem(
                  value: 'IQD',
                  child: AppText('دينار عراقي - IQD'),
                ),
              ],
              onChanged: _isSaving
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        _currency = value;
                      });
                    },
            ),
          );

          if (isWide) {
            return Row(
              children: [
                Expanded(child: balanceField),
                const SizedBox(width: 16),
                Expanded(child: currencyField),
              ],
            );
          }

          return Column(
            children: [balanceField, const SizedBox(height: 16), currencyField],
          );
        },
      ),
    );
  }

  Widget _buildAdditionalInformationCard() {
    return _sectionCard(
      title: 'معلومات إضافية',
      icon: Icons.notes_outlined,
      child: Column(
        children: [
          _securedField(
            'taxNumber',
            TextFormField(
              controller: _taxNumberController,
              decoration: InputDecoration(
                labelText: AppTranslation.translate('الرقم الضريبي'),
                prefixIcon: Icon(Icons.badge_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _securedField(
            'notes',
            TextFormField(
              controller: _notesController,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: AppTranslation.translate('ملاحظات'),
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.description_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _securedField(
            'isActive',
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const AppText(
                'المورد نشط',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: AppText(
                _isActive
                    ? 'يمكن اختيار المورد في عمليات الشراء.'
                    : 'لن يظهر المورد ضمن الموردين النشطين.',
              ),
              value: _isActive,
              activeThumbColor: Colors.black,
              onChanged: _isSaving
                  ? null
                  : (value) {
                      setState(() {
                        _isActive = value;
                      });
                    },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return _securedField(
      'name',
      TextFormField(
        controller: _nameController,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: AppTranslation.translate('اسم المورد *'),
          prefixIcon: Icon(Icons.person_outline),
          border: OutlineInputBorder(),
        ),
        validator: (value) {
          return _requiredValidator(value, 'اسم المورد');
        },
      ),
    );
  }

  Widget _buildCompanyField() {
    return _securedField(
      'companyName',
      TextFormField(
        controller: _companyNameController,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: AppTranslation.translate('اسم الشركة'),
          prefixIcon: Icon(Icons.business_outlined),
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildPhoneField() {
    return _securedField(
      'phone',
      TextFormField(
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: AppTranslation.translate('رقم الهاتف'),
          prefixIcon: Icon(Icons.phone_outlined),
          border: OutlineInputBorder(),
        ),
        validator: _phoneValidator,
      ),
    );
  }

  Widget _buildAlternativePhoneField() {
    return _securedField(
      'alternativePhone',
      TextFormField(
        controller: _alternativePhoneController,
        keyboardType: TextInputType.phone,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: AppTranslation.translate('رقم الهاتف البديل'),
          prefixIcon: Icon(Icons.phone_android_outlined),
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _buildAddressField() {
    return _securedField(
      'address',
      TextFormField(
        controller: _addressController,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: AppTranslation.translate('العنوان'),
          prefixIcon: Icon(Icons.location_on_outlined),
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.black),
                const SizedBox(width: 10),
                AppText(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isSaving
                ? null
                : () {
                    Navigator.of(context).pop();
                  },
            icon: const Icon(Icons.close),
            label: const AppText('إلغاء'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: _isSaving ? null : _saveSupplier,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: AppText(
              _isSaving
                  ? 'جارٍ الحفظ...'
                  : widget.isEditing
                  ? 'حفظ التعديلات'
                  : 'حفظ المورد',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              minimumSize: const Size.fromHeight(52),
            ),
          ),
        ),
      ],
    );
  }
}
