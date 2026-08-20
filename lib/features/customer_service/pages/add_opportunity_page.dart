import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/finance/supported_currency.dart';
import 'package:quality_line_erp/core/widgets/app_page_lifecycle_scope.dart';
import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_phase3_components.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/business_partners/customers/controllers/customers_controller.dart';
import 'package:quality_line_erp/features/business_partners/customers/models/customer_model.dart';
import 'package:quality_line_erp/features/business_partners/customers/pages/add_customer_page.dart';
import 'package:quality_line_erp/features/sales/workflow/pages/sales_order_draft_page.dart';
import 'package:quality_line_erp/features/sales/workflow/repositories/sales_workflow_repository.dart';
import 'package:quality_line_erp/features/maintenance/controllers/maintenance_controller.dart';
import 'package:quality_line_erp/features/maintenance/pages/add_maintenance_order_page.dart';
import 'package:quality_line_erp/features/maintenance/data/maintenance_repository.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';
import 'package:quality_line_erp/features/customer_service/controllers/opportunities_controller.dart';
import 'package:quality_line_erp/features/customer_service/models/opportunity_model.dart';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';

class AddOpportunityPage extends StatefulWidget {
  const AddOpportunityPage({super.key, this.opportunity});
  final OpportunityModel? opportunity;
  @override
  State<AddOpportunityPage> createState() => _AddOpportunityPageState();
}

class _AddOpportunityPageState extends State<AddOpportunityPage> {
  final _key = GlobalKey<FormState>();

  String t(String ar, String en) => context.l10n.isArabic ? ar : en;

  String get _writePermission => widget.opportunity == null
      ? 'customer_service.create'
      : 'customer_service.update';

  Widget _securedField(String field, Widget child) => FieldPermissionControl(
    resource: 'opportunities',
    field: field,
    viewPermission: 'customer_service.view',
    writePermission: _writePermission,
    child: child,
  );
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _title;
  late final TextEditingController _value;
  late final TextEditingController _notes;
  late final TextEditingController _description;
  late final TextEditingController _probability;
  late final TextEditingController _winLossReason;
  String? _source;
  String _currency = 'USD';
  String _stage = 'new';
  CustomerModel? _customer;
  String _assignedUserId = '';
  String _assignedUserName = '';
  DateTime? _followUp;
  DateTime? _expectedClose;
  String? _carId;
  String? _carName;
  List<MaintenanceVehicleOption> _vehicleOptions = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final o = widget.opportunity;
    _name = TextEditingController(text: o?.customerName ?? '');
    _phone = TextEditingController(text: o?.customerPhone ?? '');
    _title = TextEditingController(text: o?.title ?? '');
    _value = TextEditingController(
      text: o == null ? '' : o.expectedValue.toString(),
    );
    _notes = TextEditingController(text: o?.notes ?? '');
    _description = TextEditingController(text: o?.description ?? '');
    _probability = TextEditingController(
      text: o == null ? '' : o.probability.toStringAsFixed(0),
    );
    _winLossReason = TextEditingController(text: o?.winLossReason ?? '');
    _currency = SupportedCurrency.initial(
      isNew: o == null,
      stored: o?.currency,
    );
    _stage = o?.stage ?? 'new';
    _assignedUserId = o?.assignedUserId.trim() ?? '';
    _assignedUserName = o?.assignedUserName.trim() ?? '';
    _expectedClose = o?.expectedCloseDate;
    _source = (o?.source ?? '').trim().isEmpty ? null : o!.source;
    _followUp = o?.followUpDate;
    _carId = o?.carId;
    _carName = o?.carName;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeDependencies(o));
    });
  }

  Future<void> _initializeDependencies(OpportunityModel? opportunity) async {
    final customersController = context.read<CustomersController>();
    await Future.wait<void>([
      customersController.loadCustomers(),
      _loadVehicleOptions(),
    ]);
    if (!mounted) return;
    final access = context.read<AccessController>();
    final customerMatches = opportunity?.customerId == null
        ? <CustomerModel>[]
        : customersController.customers
              .where((customer) => customer.id == opportunity!.customerId)
              .toList(growable: false);
    setState(() {
      final assignedMatches = access.users.where(
        (user) => user.id == _assignedUserId,
      );
      if (assignedMatches.isNotEmpty) {
        _assignedUserName = assignedMatches.first.fullName;
      }
      _customer = customerMatches.isEmpty ? null : customerMatches.first;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _title.dispose();
    _value.dispose();
    _notes.dispose();
    _description.dispose();
    _probability.dispose();
    _winLossReason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const standardSources = [
      'زيارة المعرض',
      'اتصال هاتفي',
      'واتساب',
      'إعلان',
      'إحالة',
      'أخرى',
    ];
    final sourceOptions = <String>[
      ...standardSources,
      if (_source != null && !standardSources.contains(_source)) _source!,
    ];
    final customers = context.watch<CustomersController>().customers;
    final access = context.watch<AccessController>();
    final users = access.users.where((u) => u.isActive).toList();
    final arabic = context.l10n.isArabic;
    String t(String arText, String enText) => arabic ? arText : enText;
    return Scaffold(
      body: Form(
        key: _key,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (AppWorkspaceWindowScope.maybeOf(context) == null)
              KajPhaseHero(
                eyebrow: t('إدارة رحلة العميل', 'CUSTOMER JOURNEY DESIGN'),
                title: widget.opportunity == null
                    ? t(
                        'إنشاء فرصة تجارية جديدة',
                        'Create a new commercial opportunity',
                      )
                    : t(
                        'تطوير الفرصة التجارية',
                        'Refine the commercial opportunity',
                      ),
                subtitle: t(
                  'سجّل العميل ومصدر الاهتمام والقيمة المتوقعة والمسؤول وموعد المتابعة، ثم حوّل الفرصة إلى مسودة بيع دون فقدان السياق.',
                  'Capture the customer, source, expected value, owner, and follow-up date, then convert the opportunity into a sales draft without losing context.',
                ),
                icon: Icons.track_changes_rounded,
                accent: KajDesignTokens.champagne,
                trailing: KajStatusBadge(
                  label: widget.opportunity == null
                      ? t('فرصة جديدة', 'NEW LEAD')
                      : t('تحديث الفرصة', 'OPPORTUNITY UPDATE'),
                  color: widget.opportunity == null
                      ? KajDesignTokens.electricBlue
                      : KajDesignTokens.warning,
                  icon: widget.opportunity == null
                      ? Icons.add_chart_rounded
                      : Icons.edit_note_rounded,
                ),
              ),
            if (AppWorkspaceWindowScope.maybeOf(context) == null)
              const SizedBox(height: 12),
            KajWorkflowStepper(
              currentIndex: widget.opportunity == null ? 0 : 2,
              compact: MediaQuery.sizeOf(context).width < 980,
              steps: <String>[
                t('العميل', 'Customer'),
                t('الاحتياج', 'Need'),
                t('القيمة', 'Value'),
                t('المتابعة', 'Follow-up'),
                t('التحويل', 'Conversion'),
              ],
            ),
            const SizedBox(height: 16),
            _securedField(
              'customerId',
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<CustomerModel>(
                      isExpanded: true,
                      initialValue: _customer,
                      decoration: InputDecoration(
                        labelText: AppTranslation.translate(
                          'عميل موجود (اختياري)',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      items: customers
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: AppText(c.name),
                            ),
                          )
                          .toList(),
                      onChanged: (c) => setState(() {
                        _customer = c;
                        if (c != null) {
                          _name.text = c.name;
                          _phone.text = c.phone;
                        }
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: AppTranslation.translate('إضافة عميل'),
                    onPressed: _addCustomer,
                    icon: const Icon(Icons.person_add_alt_1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _securedField(
              'customerName',
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('اسم العميل'),
                  border: OutlineInputBorder(),
                ),
                validator: _required,
              ),
            ),
            const SizedBox(height: 14),
            _securedField(
              'customerPhone',
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('الهاتف (اختياري)'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _securedField(
              'title',
              TextFormField(
                controller: _title,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('عنوان الفرصة (اختياري)'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _securedField(
              'value',
              TextFormField(
                key: const ValueKey('opportunity-expected-value-field'),
                controller: _value,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  ThousandsInputFormatter(decimalDigits: 2),
                ],
                decoration: InputDecoration(
                  labelText: AppTranslation.translate(
                    'القيمة المتوقعة (اختيارية)',
                  ),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null ||
                        v.trim().isEmpty ||
                        ThousandsInputFormatter.parse(v) != null)
                    ? null
                    : AppTranslation.translate('أدخل قيمة صحيحة'),
              ),
            ),
            const SizedBox(height: 14),
            _securedField(
              'currency',
              DropdownButtonFormField<String>(
                key: const ValueKey('opportunity-currency-field'),
                isExpanded: true,
                initialValue: SupportedCurrency.normalize(_currency),
                validator: (value) => SupportedCurrency.isSupported(value)
                    ? null
                    : AppTranslation.translate('العملة مطلوبة'),
                decoration: InputDecoration(
                  labelText: t('عملة الفرصة', 'Opportunity currency'),
                  border: const OutlineInputBorder(),
                ),
                items: const ['USD', 'IQD']
                    .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                    .toList(),
                onChanged: (v) {
                  final code = SupportedCurrency.normalize(v);
                  if (code != null) setState(() => _currency = code);
                },
              ),
            ),
            const SizedBox(height: 14),
            _securedField(
              'stage',
              _stage == 'won' || _stage == 'closed'
                  ? TextFormField(
                      key: const ValueKey('opportunity-terminal-stage-field'),
                      initialValue: _stage == 'won'
                          ? t('رابحة', 'Won')
                          : t('مغلقة', 'Closed'),
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: t('مرحلة الفرصة', 'Opportunity stage'),
                        helperText: t(
                          'هذه النتيجة مملوكة لمسار المبيعات المعتمد.',
                          'This result is owned by the canonical sales workflow.',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    )
                  : DropdownButtonFormField<String>(
                      key: const ValueKey('opportunity-stage-field'),
                      isExpanded: true,
                      initialValue: _stage,
                      decoration: InputDecoration(
                        labelText: t('مرحلة الفرصة', 'Opportunity stage'),
                        border: const OutlineInputBorder(),
                      ),
                      items:
                          <MapEntry<String, String>>[
                                MapEntry('new', t('جديدة', 'New')),
                                MapEntry(
                                  'contacted',
                                  t('تم التواصل', 'Contacted'),
                                ),
                                MapEntry('qualified', t('مؤهلة', 'Qualified')),
                                MapEntry(
                                  'proposal',
                                  t('عرض/تسعير', 'Proposal / Quotation'),
                                ),
                                MapEntry(
                                  'negotiation',
                                  t('تفاوض', 'Negotiation'),
                                ),
                                MapEntry('lost', t('خاسرة', 'Lost')),
                              ]
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                              )
                              .toList(),
                      onChanged: (v) => setState(() => _stage = v ?? 'new'),
                    ),
            ),
            const SizedBox(height: 14),
            _securedField(
              'probability',
              TextFormField(
                controller: _probability,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: t('الاحتمالية %', 'Probability %'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = double.tryParse(v.replaceAll(',', ''));
                  return n != null && n >= 0 && n <= 100
                      ? null
                      : t(
                          'أدخل نسبة بين 0 و100',
                          'Enter a value from 0 to 100',
                        );
                },
              ),
            ),
            const SizedBox(height: 14),
            _securedField(
              'description',
              TextFormField(
                controller: _description,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: t('وصف الفرصة', 'Opportunity description'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _securedField(
              'source',
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _source,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('مصدر الفرصة (اختياري)'),
                  border: OutlineInputBorder(),
                ),
                items: sourceOptions
                    .map((v) => DropdownMenuItem(value: v, child: AppText(v)))
                    .toList(),
                onChanged: (v) => setState(() => _source = v),
              ),
            ),
            const SizedBox(height: 14),
            _securedField(
              'assignedUserId',
              DropdownButtonFormField<String>(
                key: const ValueKey('opportunity-assigned-user-field'),
                isExpanded: true,
                initialValue: _assignedUserId,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate(
                    'المستخدم المسؤول (اختياري)',
                  ),
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String>>[
                  DropdownMenuItem(
                    value: '',
                    child: AppText(t('غير مسندة', 'Unassigned')),
                  ),
                  ...users.map(
                    (u) => DropdownMenuItem(
                      value: u.id,
                      child: AppText(u.fullName),
                    ),
                  ),
                  if (_assignedUserId.isNotEmpty &&
                      !users.any((u) => u.id == _assignedUserId))
                    DropdownMenuItem(
                      value: _assignedUserId,
                      child: AppText(
                        _assignedUserName.isEmpty
                            ? _assignedUserId
                            : _assignedUserName,
                      ),
                    ),
                ],
                onChanged: (userId) => setState(() {
                  _assignedUserId = userId ?? '';
                  _assignedUserName =
                      users
                          .where((u) => u.id == _assignedUserId)
                          .map((u) => u.fullName)
                          .firstOrNull ??
                      '';
                }),
              ),
            ),
            const SizedBox(height: 14),
            _securedField(
              'followUpDate',
              ListTile(
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                title: const AppText('موعد المتابعة'),
                subtitle: AppText(
                  _followUp == null
                      ? 'غير محدد'
                      : '${_followUp!.year}/${_followUp!.month}/${_followUp!.day}',
                ),
                trailing: const Icon(Icons.calendar_month),
                onTap: _pickDate,
              ),
            ),
            const SizedBox(height: 14),
            _securedField(
              'expectedCloseDate',
              ListTile(
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                title: Text(t('تاريخ الإغلاق المتوقع', 'Expected close date')),
                subtitle: Text(
                  _expectedClose == null
                      ? t('غير محدد', 'Not set')
                      : '${_expectedClose!.year}/${_expectedClose!.month}/${_expectedClose!.day}',
                ),
                trailing: const Icon(Icons.event_available_outlined),
                onTap: _pickExpectedCloseDate,
              ),
            ),
            if (_stage == 'won' || _stage == 'lost' || _stage == 'closed') ...[
              const SizedBox(height: 14),
              _securedField(
                'winLossReason',
                TextFormField(
                  controller: _winLossReason,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: t(
                      'سبب الفوز/الخسارة أو الإغلاق',
                      'Win/loss/close reason',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _securedField(
              'notes',
              TextFormField(
                controller: _notes,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: AppTranslation.translate('ملاحظات'),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _securedField(
              'carId',
              DropdownButtonFormField<String>(
                key: const ValueKey('opportunity-maintenance-vehicle'),
                isExpanded: true,
                initialValue:
                    _vehicleOptions.any((vehicle) => vehicle.carId == _carId)
                    ? _carId
                    : null,
                decoration: InputDecoration(
                  labelText: t(
                    'المركبة المرتبطة (اختياري)',
                    'Linked vehicle (optional)',
                  ),
                  prefixIcon: const Icon(Icons.directions_car_outlined),
                ),
                items: _vehicleOptions
                    .map(
                      (vehicle) => DropdownMenuItem(
                        value: vehicle.carId,
                        child: AppText(vehicle.displayName),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  final matches = _vehicleOptions.where(
                    (vehicle) => vehicle.carId == value,
                  );
                  setState(() {
                    _carId = value;
                    _carName = matches.isEmpty
                        ? null
                        : matches.first.displayName;
                  });
                },
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('opportunity-save-button'),
                  onPressed: _saving ? null : () => _save(),
                  icon: const Icon(Icons.save_outlined),
                  label: const AppText('حفظ الفرصة'),
                ),
                if (access.hasPermission('sales.create') &&
                    access.hasPermission('customer_service.update'))
                  FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _save(createSalesDraft: true),
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.edit_note_outlined),
                    label: const AppText('حفظ وإنشاء مسودة أمر بيع'),
                  ),
                if (access.hasPermission('maintenance.create') &&
                    access.hasPermission('maintenance.view') &&
                    access.hasPermission('customer_service.update'))
                  FilledButton.tonalIcon(
                    key: const ValueKey(
                      'opportunity-save-create-maintenance-draft',
                    ),
                    onPressed: _saving
                        ? null
                        : () => _save(createMaintenanceDraft: true),
                    icon: const Icon(Icons.car_repair_outlined),
                    label: AppText(
                      t(
                        'حفظ وإنشاء مسودة صيانة',
                        'Save & Create Maintenance Draft',
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

  String? _required(String? v) => (v == null || v.trim().isEmpty)
      ? AppTranslation.translate('هذا الحقل مطلوب')
      : null;
  Future<void> _addCustomer() async {
    final created = await showAppModuleDialog<CustomerModel>(
      context: context,
      title: AppTranslation.translate('إضافة عميل'),
      maxWidth: 760,
      maxHeight: 680,
      builder: (_) => const AddCustomerPage(),
    );
    if (created == null || !mounted) return;
    setState(() {
      _customer = created;
      _name.text = created.name;
      _phone.text = created.phone;
    });
  }

  Future<void> _loadVehicleOptions() async {
    try {
      final values = await MaintenanceRepository().getEligibleVehicles();
      if (mounted) setState(() => _vehicleOptions = values);
    } catch (_) {
      // The opportunity remains editable when maintenance data is unavailable.
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _followUp ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (d != null && mounted) setState(() => _followUp = d);
  }

  Future<void> _pickExpectedCloseDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate:
          _expectedClose ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (d != null && mounted) setState(() => _expectedClose = d);
  }

  Future<CustomerModel> _resolveCustomer() async {
    final controller = context.read<CustomersController>();
    final selected = _customer;
    if (selected != null) return selected;

    final normalizedName = _name.text.trim().toLowerCase();
    final normalizedPhone = _phone.text.trim();
    for (final customer in controller.customers) {
      final sameName = customer.name.trim().toLowerCase() == normalizedName;
      final samePhone =
          normalizedPhone.isNotEmpty &&
          customer.phone.trim() == normalizedPhone;
      if (sameName || samePhone) {
        if (mounted) setState(() => _customer = customer);
        return customer;
      }
    }

    final created = CustomerModel(
      id: const Uuid().v4(),
      name: _name.text.trim(),
      phone: normalizedPhone.isEmpty ? 'غير متوفر' : normalizedPhone,
      address: '',
      nationalId: '',
      notes: context.l10n.isArabic
          ? 'تم إنشاء العميل تلقائيًا من فرصة تجارية.'
          : 'Customer created automatically from an opportunity.',
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    await controller.addCustomer(created);
    if (mounted) setState(() => _customer = created);
    return created;
  }

  Future<void> _save({
    bool createSalesDraft = false,
    bool createMaintenanceDraft = false,
  }) async {
    if (_saving || !(_key.currentState?.validate() ?? false)) return;
    if (!await PermissionAction.require(context, _writePermission)) return;
    if (!mounted) return;
    if (createSalesDraft) {
      if (!await PermissionAction.require(context, 'customer_service.update'))
        return;
      if (!mounted || !await PermissionAction.require(context, 'sales.create'))
        return;
    }
    if (createMaintenanceDraft) {
      if (!mounted) return;
      if (!await PermissionAction.require(context, 'customer_service.update'))
        return;
      if (!mounted ||
          !await PermissionAction.require(context, 'maintenance.create'))
        return;
      if (!mounted ||
          !await PermissionAction.require(context, 'maintenance.view'))
        return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    try {
      final customer = await _resolveCustomer();
      if (!mounted) return;
      final access = context.read<AccessController>();
      final current = access.currentUser!;
      final old = widget.opportunity;
      final marksLost =
          _stage == 'lost' && old?.status != OpportunityStatus.lost;
      final savedStage = marksLost ? (old?.stage ?? 'new') : _stage;
      final item = OpportunityModel(
        id: old?.id ?? const Uuid().v4(),
        opportunityNumber:
            old?.opportunityNumber ??
            'OPP-${DateTime.now().millisecondsSinceEpoch}',
        customerId: customer.id,
        customerName: _name.text.trim(),
        customerPhone: _phone.text.trim(),
        title: _title.text.trim(),
        source: _source ?? '',
        expectedValue: ThousandsInputFormatter.parse(_value.text) ?? 0,
        currency: _currency,
        stage: savedStage,
        probability:
            double.tryParse(_probability.text.replaceAll(',', '')) ?? 0,
        description: _description.text.trim(),
        expectedCloseDate: _expectedClose,
        winLossReason: _winLossReason.text.trim(),
        status: old?.status ?? OpportunityStatus.pending,
        carId: _carId,
        carName: _carName,
        saleId: old?.saleId,
        invoiceNumber: old?.invoiceNumber,
        assignedUserId: _assignedUserId,
        assignedUserName: _assignedUserName,
        createdByUserId: old?.createdByUserId ?? current.id,
        createdByUserName: old?.createdByUserName ?? current.fullName,
        createdAt: old?.createdAt ?? DateTime.now(),
        followUpDate: _followUp,
        closedAt: old?.closedAt,
        notes: _notes.text.trim(),
        updatedAt: old?.updatedAt,
      );
      final opportunities = context.read<OpportunitiesController>();
      if (marksLost) {
        await opportunities.saveAsLost(item, isNew: old == null);
      } else if (old == null) {
        await opportunities.add(item);
      } else {
        await opportunities.update(item);
      }
      if (!mounted) return;
      if (createMaintenanceDraft) {
        final authoritative = opportunities.opportunities
            .where((value) => value.id == item.id)
            .firstOrNull;
        final carId = authoritative?.carId?.trim();
        final existing = await context
            .read<MaintenanceController>()
            .findByOpportunity(item.id);
        if (!mounted) return;
        await showAppModuleDialog<bool>(
          context: context,
          title: t('مسودة صيانة مرتبطة', 'Linked Maintenance Draft'),
          maxWidth: 1080,
          maxHeight: 780,
          builder: (_) => AddMaintenanceOrderPage(
            // A cancelled Maintenance order is preserved as history. The
            // explicit "Create Maintenance Draft" action starts a new active
            // lifecycle instead of trying to edit the cancelled document.
            order: existing?.isCancelled == true ? null : existing,
            initialCarId: carId == null || carId.isEmpty ? null : carId,
            opportunityId: item.id,
          ),
        );
        if (mounted) AppWorkspaceWindowScope.closeCurrent(context, true);
      } else if (createSalesDraft) {
        final linked = await SalesWorkflowRepository().findOrderByOpportunity(
          item.id,
        );
        final orderId = linked?['id']?.toString();
        if (!mounted) return;
        await showAppModuleDialog<bool>(
          context: context,
          title: AppTranslation.translate('إنشاء مسودة أمر بيع'),
          maxWidth: 1040,
          maxHeight: 760,
          builder: (_) => SalesOrderDraftPage(
            initialCustomerId: customer.id,
            initialCurrency: item.currency,
            opportunityId: item.id,
            orderId: orderId == null || orderId.isEmpty ? null : orderId,
          ),
        );
        if (mounted) AppWorkspaceWindowScope.closeCurrent(context, true);
      } else {
        AppWorkspaceWindowScope.closeCurrent(context, true);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(
              error,
              isArabic: context.l10n.isArabic,
              arabicFallback: 'تعذر حفظ الفرصة أو إنشاء العميل المرتبط.',
              englishFallback:
                  'Unable to save the opportunity or create its customer.',
            ),
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
