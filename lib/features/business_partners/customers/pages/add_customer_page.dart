import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/widgets/app_back_button.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/widgets/base64_photo_picker.dart';

import 'package:quality_line_erp/features/business_partners/customers/controllers/customers_controller.dart';
import 'package:quality_line_erp/features/business_partners/customers/models/customer_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

class AddCustomerPage extends StatefulWidget {
  const AddCustomerPage({super.key});

  @override
  State<AddCustomerPage> createState() => _AddCustomerPageState();
}

class _AddCustomerPageState extends State<AddCustomerPage> {
  final _formKey = GlobalKey<FormState>();

  Widget _securedField(String field, Widget child) => FieldPermissionControl(
    resource: 'customers',
    field: field,
    viewPermission: 'customers.view',
    writePermission: 'customers.create',
    child: child,
  );

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();
  final nationalIdController = TextEditingController();
  final notesController = TextEditingController();
  String? photoBase64;
  bool _isSaving = false;

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    nationalIdController.dispose();
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
          title: const AppText('إضافة عميل'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _securedField(
                  'photo',
                  Base64PhotoPicker(
                    value: photoBase64,
                    label: 'صورة العميل',
                    onChanged: (value) => setState(() => photoBase64 = value),
                  ),
                ),
                const SizedBox(height: 12),
                _field('اسم العميل', nameController, field: 'name'),
                _field(
                  'رقم الهاتف',
                  phoneController,
                  field: 'phone',
                  keyboardType: TextInputType.phone,
                  requiredField: false,
                ),
                _field(
                  'العنوان',
                  addressController,
                  field: 'address',
                  requiredField: false,
                ),
                _field(
                  'رقم الهوية',
                  nationalIdController,
                  field: 'nationalId',
                  requiredField: false,
                ),
                _field(
                  'ملاحظات',
                  notesController,
                  field: 'notes',
                  requiredField: false,
                  maxLines: 4,
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveCustomer,
                    child: AppText(
                      _isSaving ? 'جارٍ حفظ العميل...' : 'حفظ العميل',
                    ),
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
    bool requiredField = true,
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
            if (requiredField && (value == null || value.trim().isEmpty)) {
              return AppTranslation.translate('يرجى إدخال $label');
            }
            return null;
          },
          decoration: InputDecoration(
            labelText: AppTranslation.translate(label),
            border: const OutlineInputBorder(),
          ),
        ),
      ),
    );
  }

  Future<void> _saveCustomer() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final customer = CustomerModel(
      id: const Uuid().v4(),
      name: nameController.text.trim(),
      phone: phoneController.text.trim(),
      address: addressController.text.trim(),
      nationalId: nationalIdController.text.trim(),
      notes: notesController.text.trim(),
      createdAt: DateTime.now().toIso8601String(),
      photoBase64: photoBase64,
    );

    setState(() => _isSaving = true);
    try {
      await context.read<CustomersController>().addCustomer(customer);
      if (!mounted) return;
      Navigator.of(context).pop<CustomerModel>(customer);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(
              error,
              isArabic: context.l10n.isArabic,
              arabicFallback: 'تعذر حفظ اسم العميل وبياناته.',
              englishFallback: 'Unable to save the customer name and details.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
