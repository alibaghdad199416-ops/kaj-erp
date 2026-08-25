import 'dart:async';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/utils/definition_currency_resolver.dart';
import 'package:flutter/services.dart';
import 'package:quality_line_erp/design_system/kaj_commercial_stage6_components.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/widgets/enterprise_item_picker.dart';
import 'package:quality_line_erp/core/widgets/enterprise_item_visual_card.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/controllers/suppliers_controller.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/models/supplier_model.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/pages/add_supplier_page.dart';
import 'package:quality_line_erp/features/purchases/models/purchase_workflow_models.dart';
import 'package:quality_line_erp/features/purchases/repositories/purchase_workflow_repository.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

class PurchaseOrderDraftPage extends StatefulWidget {
  const PurchaseOrderDraftPage({super.key, this.orderId, this.opportunityId});

  final String? orderId;
  final String? opportunityId;

  @override
  State<PurchaseOrderDraftPage> createState() => _PurchaseOrderDraftPageState();
}

class _PurchaseOrderDraftPageState extends State<PurchaseOrderDraftPage> {
  final _formKey = GlobalKey<FormState>();
  final _discount = TextEditingController(text: '0');
  final _notes = TextEditingController();
  final _exchangeRate = TextEditingController(text: '1');
  final _repository = PurchaseWorkflowRepository();
  final _money = NumberFormat('#,##0.##');

  SupplierModel? _supplier;
  String _currency = 'USD';
  DateTime _effectiveAt = DateTime.now();
  bool _loadingCatalog = true;
  bool _saving = false;
  String _existingStatus = 'draft';
  DateTime? _loadedUpdatedAt;
  List<_PurchaseCatalogItem> _catalog = const [];
  final List<_PurchaseDraftLine> _lines = [];

  String get _writePermission =>
      widget.orderId == null ? 'purchases.create' : 'purchases.update';

  Widget _securedField(String field, Widget child) => FieldPermissionControl(
    resource: 'purchases',
    field: field,
    viewPermission: 'purchases.view',
    writePermission: _writePermission,
    child: child,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_bootstrap()),
    );
  }

  Future<void> _bootstrap() async {
    final suppliers = context.read<SuppliersController>();
    if (suppliers.suppliers.isEmpty) {
      await suppliers.loadSuppliers();
    }
    if (!mounted) return;
    await _loadCatalog();
  }

  @override
  void dispose() {
    _discount.dispose();
    _notes.dispose();
    _exchangeRate.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    try {
      final rows = await _repository.purchaseCatalog(orderId: widget.orderId);
      if (!mounted) return;
      setState(() {
        _catalog = rows
            .map(
              (row) => _PurchaseCatalogItem(
                type: row['itemType']?.toString() ?? 'product',
                id: row['id'].toString(),
                description: row['description']?.toString() ?? '-',
                baseCost: (row['baseCost'] as num?)?.toDouble() ?? 0,
                imagePath: row['imagePath']?.toString(),
                definitionCurrency: DefinitionCurrencyResolver.resolve(
                  row,
                  fallback: _currency,
                ),
                details: Map<String, Object?>.from(
                  (row['details'] as Map?) ?? const {},
                ),
              ),
            )
            .toList();
        _loadingCatalog = false;
      });
      if (widget.orderId != null) await _loadExisting();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _catalog = const [];
        _loadingCatalog = false;
      });
      _message(
        userFacingError(
          error,
          isArabic: context.l10n.isArabic,
          arabicFallback: AppTranslation.translate(
            'تعذر تحميل السيارات والمنتجات المتاحة للشراء',
          ),
          englishFallback:
              'Unable to load vehicles and products available for purchase.',
        ),
      );
    }
  }

  Future<void> _loadExisting() async {
    final orderId = widget.orderId?.trim();
    if (orderId == null || orderId.isEmpty) return;
    final payload = await _repository.getDraft(orderId);
    if (payload == null || !mounted) return;
    final order = Map<String, Object?>.from(
      (payload['order'] as Map?) ?? const {},
    );
    final items = ((payload['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, Object?>.from(e));
    final storedCurrency =
        order['currency']?.toString().trim().toUpperCase() ?? '';
    if (storedCurrency != 'USD' && storedCurrency != 'IQD') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            context.l10n.isArabic
                ? 'عملة الأمر المحفوظ غير محددة أو غير صالحة. صحح بيانات المستند قبل تعديله.'
                : 'The saved order currency is missing or invalid. Correct the document data before editing it.',
          ),
        ),
      );
      return;
    }
    final suppliers = context.read<SuppliersController>().suppliers;
    final match = suppliers.where(
      (e) => e.id == order['supplierId']?.toString(),
    );
    for (final line in _lines) {
      line.dispose();
    }
    _lines.clear();
    for (final row in items) {
      final catalogMatch = _catalog.where(
        (e) =>
            e.id == row['itemId']?.toString() &&
            e.type == row['itemType']?.toString(),
      );
      final item = catalogMatch.isNotEmpty
          ? catalogMatch.first
          : _PurchaseCatalogItem(
              type: row['itemType']?.toString() ?? 'product',
              id: row['itemId']?.toString() ?? '',
              description: row['description']?.toString() ?? '-',
              baseCost: (row['unitCost'] as num?)?.toDouble() ?? 0,
              definitionCurrency: DefinitionCurrencyResolver.resolve(
                row,
                fallback: storedCurrency,
              ),
              details: Map<String, Object?>.from(
                (row['details'] as Map?) ??
                    <String, Object?>{
                      'id': row['itemId'],
                      'status': 'linked_to_current_order',
                    },
              ),
            );
      final line = _PurchaseDraftLine(
        item: item,
        onChanged: () => setState(() {}),
      );
      line.quantityController.text = '${row['quantity'] ?? 1}';
      line.costController.text = '${row['unitCost'] ?? 0}';
      _lines.add(line);
    }
    setState(() {
      _supplier = match.isEmpty ? null : match.first;
      _currency = storedCurrency;
      _exchangeRate.text = '${order['exchangeRate'] ?? 1}';
      _effectiveAt =
          DateTime.tryParse(
            order['effectiveAt']?.toString() ?? '',
          )?.toLocal() ??
          _effectiveAt;
      _discount.text = '${order['discount'] ?? 0}';
      _notes.text = order['notes']?.toString() ?? '';
      _existingStatus = order['status']?.toString() ?? 'draft';
      _loadedUpdatedAt = DateTime.tryParse(
        order['updatedAt']?.toString() ?? '',
      );
    });
  }

  String _bi(String arabic, String english) =>
      context.l10n.isArabic ? arabic : english;

  double get _rate =>
      double.tryParse(_exchangeRate.text.replaceAll(',', '')) ?? 0;

  double get _subtotal => _lines.fold(0, (sum, line) => sum + line.total);
  double get _discountValue =>
      double.tryParse(_discount.text.replaceAll(',', '')) ?? 0;
  double get _total =>
      (_subtotal - _discountValue).clamp(0, double.infinity).toDouble();

  Future<void> _addSupplier() async {
    final created = await Navigator.of(context).push<SupplierModel>(
      MaterialPageRoute<SupplierModel>(builder: (_) => const AddSupplierPage()),
    );
    if (created == null || !mounted) return;
    final controller = context.read<SuppliersController>();
    if (!controller.suppliers.any((item) => item.id == created.id)) {
      await controller.loadSuppliers();
      if (!mounted) return;
    }
    setState(() => _supplier = created);
  }

  List<_PurchaseCatalogItem> get _currencyCatalog => _catalog
      .where(
        (item) => DefinitionCurrencyResolver.matches(
          item.definitionCurrency,
          _currency,
        ),
      )
      .toList(growable: false);

  void _changeCurrency(String? value) {
    final next = (value ?? 'USD').toUpperCase();
    if (next == _currency) return;
    for (final line in _lines) line.dispose();
    setState(() {
      _currency = next;
      _lines.clear();
    });
    _message(
      _bi(
        'تم مسح البنود لأن عملة الأمر تغيرت',
        'Items were cleared because the order currency changed.',
      ),
    );
  }

  void _addLine() {
    final used = _lines
        .map((line) => '${line.item.type}:${line.item.id}')
        .toSet();
    final available = _currencyCatalog.where(
      (item) => !used.contains('${item.type}:${item.id}'),
    );
    if (available.isEmpty) {
      _message(
        _catalog.isEmpty
            ? 'لا توجد سيارات أو منتجات معرفة للشراء'
            : 'تمت إضافة جميع البنود المتاحة',
      );
      return;
    }
    setState(
      () => _lines.add(
        _PurchaseDraftLine(
          item: available.first,
          onChanged: () => setState(() {}),
        ),
      ),
    );
  }

  Future<void> _pickEffectiveAt() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _effectiveAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: _bi('اختر التاريخ التشغيلي', 'Select operational date'),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_effectiveAt),
      helpText: _bi('اختر الوقت التشغيلي', 'Select operational time'),
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

  Future<void> _save({required bool approve}) async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    final supplier = _supplier;
    if (supplier == null) {
      _message('يجب اختيار المورد');
      return;
    }
    if (_rate <= 0) {
      _message('سعر الصرف يجب أن يكون أكبر من صفر');
      return;
    }
    if (_lines.isEmpty) {
      _message('يجب إضافة سيارة أو منتج واحد على الأقل');
      return;
    }
    final uniqueItems = _lines
        .map((line) => '${line.item.type}:${line.item.id}')
        .toSet();
    if (uniqueItems.length != _lines.length) {
      _message('لا يمكن إضافة البند نفسه أكثر من مرة');
      return;
    }
    setState(() => _saving = true);
    try {
      final inputs = _lines
          .map(
            (line) => PurchaseOrderItemInput(
              itemType: line.item.type,
              itemId: line.item.id,
              description: line.item.description,
              quantity: line.quantity,
              unitCost: line.unitCost,
            ),
          )
          .toList();
      final id =
          widget.orderId ??
          await _repository.createDraft(
            supplierId: supplier.id,
            currency: _currency,
            exchangeRate: _rate,
            discount: _discountValue,
            notes: _notes.text.trim(),
            effectiveAt: _effectiveAt,
            items: inputs,
            opportunityId: widget.opportunityId,
          );
      if (widget.orderId != null) {
        final expectedUpdatedAt = _loadedUpdatedAt;
        if (expectedUpdatedAt == null) {
          throw StateError(
            AppTranslation.translate(
              'تعذر تحديد نسخة أمر الشراء الحالية. أعد فتح المستند.',
            ),
          );
        }
        await _repository.updateDraft(
          orderId: id,
          supplierId: supplier.id,
          currency: _currency,
          exchangeRate: _rate,
          discount: _discountValue,
          notes: _notes.text.trim(),
          effectiveAt: _effectiveAt,
          items: inputs,
          expectedUpdatedAt: expectedUpdatedAt,
        );
        if (approve && _existingStatus != 'approved') {
          await _repository.approveOrder(id);
        }
      } else if (approve) {
        await _repository.approveOrder(id);
      }
      if (mounted) AppWorkspaceWindowScope.closeCurrent(context, true);
    } catch (error) {
      AppLogger.debug('Purchase order save failed: $error');
      // ignore: use_build_context_synchronously
      _message(userFacingError(error, isArabic: context.l10n.isArabic));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: AppText(text)));
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = context
        .watch<SuppliersController>()
        .suppliers
        .where((s) => s.isActive)
        .toList();
    return Scaffold(
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            KajCommercialDocumentHeader(
              title: _bi(
                widget.orderId == null ? 'أمر شراء جديد' : 'تعديل أمر الشراء',
                widget.orderId == null
                    ? 'New purchase order'
                    : 'Edit purchase order',
              ),
              subtitle: _bi(
                'المورد والبنود والكلف والتاريخ التشغيلي ضمن نموذج واضح ومتجاوب.',
                'Supplier, items, costs, and operational date in a clear responsive form.',
              ),
            ),
            const SizedBox(height: 12),
            if (widget.orderId != null) ...[
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.sync_alt),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppText(
                          _bi(
                            'عند الحفظ ستُعكس الارتباطات الحالية ثم تُعاد الفاتورة وإشعار الاستلام والدفعات والقيود والمخزون بالحالة الجديدة داخل معاملة واحدة.',
                            'Saving reverses the current links, then rebuilds the invoice, receipt, payments, journal entries, and inventory in one database transaction.',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: _securedField(
                    'supplierId',
                    DropdownButtonFormField<SupplierModel>(
                      isExpanded: true,
                      key: ValueKey<String>(
                        'purchase-supplier-${_supplier?.id ?? 'none'}',
                      ),
                      initialValue: _supplier,
                      decoration: InputDecoration(
                        labelText: AppTranslation.translate('المورد'),
                        border: OutlineInputBorder(),
                      ),
                      items: suppliers
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: AppText(s.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _supplier = value),
                      validator: (value) => value == null
                          ? AppTranslation.translate('اختر المورد')
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FieldPermissionControl(
                  resource: 'purchases',
                  field: 'supplierId',
                  viewPermission: 'purchases.view',
                  writePermission: _writePermission,
                  child: IconButton.filledTonal(
                    tooltip: AppTranslation.translate('إضافة مورد'),
                    onPressed: _addSupplier,
                    icon: const Icon(Icons.person_add_alt_1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 260,
                  child: _securedField(
                    'currencyCode',
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _currency,
                      decoration: InputDecoration(
                        labelText: AppTranslation.translate('عملة أمر الشراء'),
                        border: const OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'USD', child: AppText('USD')),
                        DropdownMenuItem(value: 'IQD', child: AppText('IQD')),
                      ],
                      onChanged: _changeCurrency,
                    ),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: _securedField(
                    'exchangeRate',
                    TextFormField(
                      controller: _exchangeRate,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: <TextInputFormatter>[
                        ThousandsInputFormatter(decimalDigits: 20),
                      ],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: _bi(
                          'سعر الصرف (دينار لكل دولار)',
                          'Exchange rate (IQD per USD)',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final rate =
                            double.tryParse(
                              (value ?? '').replaceAll(',', ''),
                            ) ??
                            0;
                        return rate > 0
                            ? null
                            : _bi(
                                'أدخل سعر صرف صحيحًا',
                                'Enter a valid exchange rate',
                              );
                      },
                    ),
                  ),
                ),
                SizedBox(
                  width: 310,
                  child: _securedField(
                    'operationalDate',
                    InkWell(
                      onTap: _saving ? null : _pickEffectiveAt,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: _bi(
                            'التاريخ والوقت التشغيلي',
                            'Operational date and time',
                          ),
                          prefixIcon: const Icon(
                            Icons.event_available_outlined,
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        child: AppText(
                          DateFormat('yyyy-MM-dd HH:mm').format(_effectiveAt),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: AppText(
                    'البنود',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                FieldPermissionControl(
                  resource: 'purchases',
                  field: 'items',
                  viewPermission: 'purchases.view',
                  writePermission: _writePermission,
                  child: FilledButton.icon(
                    onPressed: _loadingCatalog ? null : _addLine,
                    icon: const Icon(Icons.add),
                    label: const AppText('إضافة بند'),
                  ),
                ),
              ],
            ),
            if (_loadingCatalog) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            for (var index = 0; index < _lines.length; index++)
              _lines[index].build(
                context,
                catalog: _currencyCatalog,
                rate: _rate,
                currency: _currency,
                writePermission: _writePermission,
                onRemove: () {
                  final removed = _lines.removeAt(index);
                  removed.dispose();
                  setState(() {});
                },
              ),
            const SizedBox(height: 12),
            _securedField(
              'discount',
              TextFormField(
                controller: _discount,

                inputFormatters: <TextInputFormatter>[
                  ThousandsInputFormatter(decimalDigits: 15),
                ],
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('الخصم'),
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                validator: (value) {
                  final amount =
                      double.tryParse((value ?? '').replaceAll(',', '')) ?? -1;
                  return amount < 0 || amount > _subtotal
                      ? AppTranslation.translate('قيمة الخصم غير صحيحة')
                      : null;
                },
              ),
            ),
            const SizedBox(height: 12),
            _securedField(
              'notes',
              TextFormField(
                controller: _notes,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('ملاحظات'),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _totalRow('الإجمالي الفرعي', _subtotal),
                    _totalRow('الخصم', _discountValue),
                    const Divider(),
                    _totalRow('الإجمالي النهائي', _total, bold: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _save(approve: false),
                  icon: const Icon(Icons.save_outlined),
                  label: AppText(
                    _bi(
                      widget.orderId == null ? 'حفظ كمسودة' : 'حفظ التعديلات',
                      widget.orderId == null ? 'Save draft' : 'Save changes',
                    ),
                  ),
                ),
                if (widget.orderId == null || _existingStatus != 'approved')
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _save(approve: true),
                    icon: const Icon(Icons.verified_outlined),
                    label: AppText(
                      _bi(
                        widget.orderId == null
                            ? 'حفظ وتصديق أمر الشراء'
                            : 'حفظ وتصديق الأمر',
                        widget.orderId == null
                            ? 'Save and approve purchase order'
                            : 'Save and approve order',
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalRow(String label, double value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        AppText(
          label,
          style: TextStyle(fontWeight: bold ? FontWeight.bold : null),
        ),
        AppText(
          '${_money.format(value)} $_currency',
          style: TextStyle(fontWeight: bold ? FontWeight.bold : null),
        ),
      ],
    ),
  );
}

// ignore: unused_element
class _PurchaseFormBanner extends StatelessWidget {
  const _PurchaseFormBanner({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Theme.of(context).dividerColor),
    ),
    child: Row(
      children: [
        const CircleAvatar(child: Icon(Icons.shopping_cart_checkout_rounded)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              AppText(subtitle, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ],
    ),
  );
}

class _PurchaseCatalogItem {
  const _PurchaseCatalogItem({
    required this.type,
    required this.id,
    required this.description,
    required this.baseCost,
    required this.details,
    required this.definitionCurrency,
    this.imagePath,
  });
  final String type;
  final String id;
  final String description;
  final double baseCost;
  final Map<String, Object?> details;
  final String definitionCurrency;
  final String? imagePath;
}

class _PurchaseDraftLine {
  _PurchaseDraftLine({required this.item, required this.onChanged})
    : quantityController = TextEditingController(text: '1'),
      costController = TextEditingController(
        text: item.baseCost.toStringAsFixed(2),
      );

  _PurchaseCatalogItem item;
  final VoidCallback onChanged;
  final TextEditingController quantityController;
  final TextEditingController costController;

  int get quantity =>
      int.tryParse(quantityController.text.replaceAll(',', '')) ?? 0;
  double get unitCost =>
      double.tryParse(costController.text.replaceAll(',', '')) ?? 0;
  double get total => quantity * unitCost;

  Widget build(
    BuildContext context, {
    required List<_PurchaseCatalogItem> catalog,
    required double rate,
    required String currency,
    required String writePermission,
    required VoidCallback onRemove,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: FieldPermissionControl(
                    resource: 'purchases',
                    field: 'items',
                    viewPermission: 'purchases.view',
                    writePermission: writePermission,
                    child: EnterpriseItemPicker<_PurchaseCatalogItem>(
                      label: AppTranslation.translate(
                        'ابحث واختر السيارة أو المنتج',
                      ),
                      selected: EnterprisePickerItem<_PurchaseCatalogItem>(
                        value: item,
                        title: item.description,
                        subtitle: item.details.entries
                            .take(3)
                            .map((e) => '${e.key}: ${e.value}')
                            .join(' • '),
                        kind: item.type,
                        searchText:
                            '${item.id} ${item.description} ${item.details.values.join(' ')}',
                        details: item.details,
                        image: item.imagePath,
                        badge: AppTranslation.translate(
                          item.details['status']?.toString() ??
                              item.details['الحالة']?.toString() ??
                              '',
                        ),
                      ),
                      items: catalog
                          .map(
                            (
                              entry,
                            ) => EnterprisePickerItem<_PurchaseCatalogItem>(
                              value: entry,
                              title: entry.description,
                              subtitle: entry.details.entries
                                  .take(3)
                                  .map((e) => '${e.key}: ${e.value}')
                                  .join(' • '),
                              kind: entry.type,
                              searchText:
                                  '${entry.id} ${entry.description} ${entry.details.values.join(' ')}',
                              details: entry.details,
                              image: entry.imagePath,
                              badge: AppTranslation.translate(
                                entry.details['status']?.toString() ??
                                    entry.details['الحالة']?.toString() ??
                                    '',
                              ),
                            ),
                          )
                          .toList(),
                      onSelected: (selection) {
                        final value = selection.value;
                        item = value;
                        quantityController.text = '1';
                        costController.text = value.baseCost.toStringAsFixed(2);
                        onChanged();
                      },
                    ),
                  ),
                ),
                FieldPermissionControl(
                  resource: 'purchases',
                  field: 'items',
                  viewPermission: 'purchases.view',
                  writePermission: writePermission,
                  child: IconButton(
                    onPressed: onRemove,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ],
            ),
            EnterpriseItemVisualCard(
              title: item.description,
              kind: item.type,
              details: item.details,
              image: item.imagePath,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FieldPermissionControl(
                    resource: 'purchases',
                    field: 'itemQuantity',
                    viewPermission: 'purchases.view',
                    writePermission: writePermission,
                    child: TextFormField(
                      controller: quantityController,
                      enabled: item.type != 'car',
                      decoration: InputDecoration(
                        labelText: AppTranslation.translate('الكمية'),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        ThousandsInputFormatter(decimalDigits: 0),
                      ],
                      onChanged: (_) => onChanged(),
                      validator: (_) => quantity <= 0
                          ? AppTranslation.translate('الكمية غير صحيحة')
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FieldPermissionControl(
                    resource: 'purchases',
                    field: 'itemCost',
                    viewPermission: 'purchases.view',
                    writePermission: writePermission,
                    child: TextFormField(
                      controller: costController,

                      inputFormatters: <TextInputFormatter>[
                        ThousandsInputFormatter(decimalDigits: 15),
                      ],
                      decoration: InputDecoration(
                        labelText: AppTranslation.translate('الكلفة $currency'),
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => onChanged(),
                      validator: (_) => unitCost < 0
                          ? AppTranslation.translate('كلفة غير صحيحة')
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            if (rate > 0 && rate != 1)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: AppText(
                    'القيمة المحولة: ${NumberFormat('#,##0.##').format(total * rate)}',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void dispose() {
    quantityController.dispose();
    costController.dispose();
  }
}
