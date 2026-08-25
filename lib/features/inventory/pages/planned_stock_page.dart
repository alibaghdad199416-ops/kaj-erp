import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

import 'package:quality_line_erp/core/widgets/app_back_button.dart';
import 'package:quality_line_erp/features/inventory/controllers/inventory_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';

class PlannedStockPage extends StatefulWidget {
  const PlannedStockPage({super.key});

  @override
  State<PlannedStockPage> createState() => _PlannedStockPageState();
}

class _PlannedStockPageState extends State<PlannedStockPage> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController(text: '1');
  final _notesController = TextEditingController();
  String? _productId;
  String? _warehouseId;
  bool _incoming = true;
  bool _saving = false;

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!await PermissionAction.require(context, 'inventory.adjust')) return;
    if (!mounted) return;
    if (!(_formKey.currentState?.validate() ?? false) ||
        _productId == null ||
        _warehouseId == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      await context.read<InventoryController>().planExpectedMovement(
        productId: _productId!,
        warehouseId: _warehouseId!,
        incoming: _incoming,
        quantity: int.parse(_quantityController.text.trim()),
        notes: _notesController.text.trim(),
      );
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
              arabicFallback: 'تعذر تسجيل الحركة المتوقعة.',
              englishFallback: 'Unable to save the planned stock movement.',
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
    final inventory = context.watch<InventoryController>();
    final activeItems = inventory.items
        .where((item) => item.isActive)
        .toList(growable: false);
    final activeWarehouses = inventory.warehouses
        .where((warehouse) => warehouse.isActive)
        .toList(growable: false);
    if (_productId == null ||
        !activeItems.any((item) => item.id == _productId)) {
      _productId = activeItems.isEmpty ? null : activeItems.first.id;
    }
    if (_warehouseId == null ||
        !activeWarehouses.any((warehouse) => warehouse.id == _warehouseId)) {
      _warehouseId = activeWarehouses.isEmpty
          ? null
          : activeWarehouses.first.id;
    }

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const AppText('حركة مخزنية متوقعة'),
      ),
      body: Center(
        child: SizedBox(
          width: AppResponsive.dialogWidth(context, 760),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(22),
                shrinkWrap: true,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.south_west_rounded),
                        label: AppText('إدخال متوقع'),
                      ),
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.north_east_rounded),
                        label: AppText('إخراج متوقع'),
                      ),
                    ],
                    selected: {_incoming},
                    onSelectionChanged: (value) =>
                        setState(() => _incoming = value.first),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _productId,
                    items: activeItems
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: AppText(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _productId = value),
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate('المنتج'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _warehouseId,
                    items: activeWarehouses
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: AppText(item.name),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _warehouseId = value),
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate('المخزن'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      ThousandsInputFormatter(decimalDigits: 0),
                    ],
                    validator: (value) {
                      final quantity = int.tryParse(value ?? '');
                      return quantity == null || quantity <= 0
                          ? AppTranslation.translate('أدخل كمية صحيحة')
                          : null;
                    },
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate('الكمية المتوقعة'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _notesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: AppTranslation.translate(
                        'سبب أو مرجع الحركة المتوقعة',
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.insights_outlined),
                    label: AppText(
                      _saving ? 'جارٍ الحفظ...' : 'تسجيل الحركة المتوقعة',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
