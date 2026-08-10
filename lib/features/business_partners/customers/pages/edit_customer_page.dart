import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
import 'package:quality_line_erp/core/widgets/app_back_button.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/base64_photo_picker.dart';

import 'package:quality_line_erp/features/business_partners/customers/controllers/customers_controller.dart';
import 'package:quality_line_erp/features/business_partners/customers/models/customer_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

class EditCustomerPage extends StatefulWidget {
  final CustomerModel customer;

  const EditCustomerPage({super.key, required this.customer});

  @override
  State<EditCustomerPage> createState() => _EditCustomerPageState();
}

class _EditCustomerPageState extends State<EditCustomerPage> {
  final _formKey = GlobalKey<FormState>();

  Widget _securedField(String field, Widget child) => FieldPermissionControl(
    resource: 'customers',
    field: field,
    viewPermission: 'customers.view',
    writePermission: 'customers.update',
    child: child,
  );

  late final TextEditingController nameController;
  late final TextEditingController phoneController;
  late final TextEditingController addressController;
  late final TextEditingController nationalIdController;
  late final TextEditingController notesController;
  String? photoBase64;

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(text: widget.customer.name);

    phoneController = TextEditingController(text: widget.customer.phone);

    addressController = TextEditingController(text: widget.customer.address);

    nationalIdController = TextEditingController(
      text: widget.customer.nationalId,
    );

    notesController = TextEditingController(text: widget.customer.notes);
    photoBase64 = widget.customer.photoBase64;
  }

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
          title: const AppText('تعديل العميل'),
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
                ),
                _field('العنوان', addressController, field: 'address'),
                _field('رقم الهوية', nationalIdController, field: 'nationalId'),
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
                    onPressed: _saveCustomer,
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
      id: widget.customer.id,
      name: nameController.text.trim(),
      phone: phoneController.text.trim(),
      address: addressController.text.trim(),
      nationalId: nationalIdController.text.trim(),
      notes: notesController.text.trim(),
      createdAt: widget.customer.createdAt,
      photoBase64: photoBase64,
    );

    await context.read<CustomersController>().updateCustomer(customer);

    if (!mounted) return;

    AppWorkspaceWindowScope.closeCurrent(context);
  }
}
