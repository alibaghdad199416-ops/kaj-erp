import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_full_page_route.dart';
import 'package:quality_line_erp/design_system/kaj_admin_stage8_components.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/models/permission_codes.dart';
import '../models/operational_period.dart';
import '../repositories/operational_period_repository.dart';

class OperationalPeriodsPage extends StatefulWidget {
  const OperationalPeriodsPage({super.key});

  @override
  State<OperationalPeriodsPage> createState() => _OperationalPeriodsPageState();
}

class _OperationalPeriodsPageState extends State<OperationalPeriodsPage> {
  final _repository = OperationalPeriodRepository();
  final _format = DateFormat('yyyy-MM-dd HH:mm');
  List<OperationalPeriod> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final values = await _repository.list();
      if (mounted) setState(() => _items = values);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _moduleLabel(String module) {
    const ar = {
      'all': 'جميع الوحدات',
      'sales': 'المبيعات',
      'purchases': 'المشتريات',
      'accounting': 'المحاسبة',
      'inventory': 'المخزون',
      'maintenance': 'الصيانة',
    };
    const en = {
      'all': 'All modules',
      'sales': 'Sales',
      'purchases': 'Purchases',
      'accounting': 'Accounting',
      'inventory': 'Inventory',
      'maintenance': 'Maintenance',
    };
    return (context.l10n.isArabic ? ar : en)[module] ?? module;
  }

  Future<void> _edit([OperationalPeriod? item]) async {
    final access = context.read<AccessController>();
    if (!access.canEditField(
      'settings',
      'operationalPeriods',
      viewPermission: PermissionCodes.periodsView,
    ))
      return;
    final changed = await showAppFullPageRoute<bool>(
      context: context,
      title: context.l10n.isArabic
          ? (item == null ? 'إضافة فترة تشغيلية' : 'تعديل الفترة التشغيلية')
          : (item == null
                ? 'Add operational period'
                : 'Edit operational period'),
      maxWidth: 760,
      maxHeight: 700,
      minWidth: 500,
      minHeight: 480,
      builder: (_) =>
          _OperationalPeriodForm(repository: _repository, value: item),
    );
    if (changed == true) await _load();
  }

  Future<void> _delete(OperationalPeriod item) async {
    final accepted =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: AppText(
              context.l10n.isArabic
                  ? 'حذف الفترة التشغيلية'
                  : 'Delete operational period',
            ),
            content: AppText(
              context.l10n.isArabic
                  ? 'سيتم نقل الفترة «${item.name}» إلى سلة المحذوفات.'
                  : 'The period “${item.name}” will be moved to the recycle bin.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: AppText(context.l10n.isArabic ? 'إلغاء' : 'Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: AppText(context.l10n.isArabic ? 'حذف' : 'Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!accepted) return;
    try {
      await _repository.delete(item.id);
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(error, isArabic: context.l10n.isArabic),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessController>();
    final canViewPeriods = access.canViewField(
      'settings',
      'operationalPeriods',
      viewPermission: PermissionCodes.periodsView,
    );
    if (!canViewPeriods) return const SizedBox.shrink();
    final canManage =
        (access.hasPermission(PermissionCodes.periodsClose) ||
            access.hasPermission(PermissionCodes.periodsReopen)) &&
        access.canEditField(
          'settings',
          'operationalPeriods',
          viewPermission: PermissionCodes.periodsView,
        );
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          KajAdminWorkspace(
            title: context.l10n.isArabic
                ? 'الفترات التشغيلية'
                : 'Operational Periods',
            subtitle: context.l10n.isArabic
                ? 'حوكمة التواريخ المفتوحة والمغلقة للمبيعات والمشتريات والمحاسبة والمخزون.'
                : 'Govern open and closed dates for sales, purchases, accounting and inventory.',
            icon: Icons.timeline_outlined,
            metrics: <KajAdminMetricData>[
              KajAdminMetricData(
                label: context.l10n.isArabic ? 'الفترات' : 'Periods',
                value: _items.length.toString(),
                icon: Icons.date_range_outlined,
              ),
              KajAdminMetricData(
                label: context.l10n.isArabic ? 'المفتوحة' : 'Open',
                value: _items.where((item) => item.isOpen).length.toString(),
                icon: Icons.lock_open_outlined,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.timeline_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppText(
                      context.l10n.isArabic
                          ? 'تحدد الفترات المفتوحة التواريخ المسموح استخدامها في أوامر البيع والشراء والقيود وحركات المخزون. عند عدم تعريف فترات تبقى التواريخ متاحة دون تقييد.'
                          : 'Open periods define the dates allowed for sales, purchases, journals, and inventory movements. When no periods are defined, dates remain unrestricted.',
                    ),
                  ),
                  if (canManage)
                    FilledButton.icon(
                      onPressed: () => _edit(),
                      icon: const Icon(Icons.add),
                      label: AppText(
                        context.l10n.isArabic ? 'إضافة فترة' : 'Add period',
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            KajAdminState(
              kind: KajAdminStateKind.loading,
              title: context.l10n.isArabic
                  ? 'جاري تحميل الفترات'
                  : 'Loading periods',
              message: context.l10n.isArabic
                  ? 'يتم التحقق من الفترات المفتوحة والمغلقة.'
                  : 'Checking open and closed operational periods.',
            )
          else if (_error != null)
            Center(
              child: AppText(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            )
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: AppText(
                  context.l10n.isArabic
                      ? 'لا توجد فترات تشغيلية معرفة حالياً.'
                      : 'No operational periods are currently defined.',
                ),
              ),
            )
          else
            ..._items.map(
              (item) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      item.isOpen
                          ? Icons.lock_open_outlined
                          : Icons.lock_outline,
                    ),
                  ),
                  title: AppText(item.name),
                  subtitle: AppText(
                    '${_moduleLabel(item.module)} • ${_format.format(item.startsAt)} → ${_format.format(item.endsAt)}\n'
                    '${context.l10n.isArabic ? 'الحالة' : 'Status'}: ${item.isOpen ? (context.l10n.isArabic ? 'مفتوحة' : 'Open') : (context.l10n.isArabic ? 'مغلقة' : 'Closed')}',
                  ),
                  isThreeLine: true,
                  trailing: canManage
                      ? Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              onPressed: () => _edit(item),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              onPressed: () => _delete(item),
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        )
                      : null,
                ),
              ),
            ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}

class _OperationalPeriodForm extends StatefulWidget {
  const _OperationalPeriodForm({required this.repository, this.value});

  final OperationalPeriodRepository repository;
  final OperationalPeriod? value;

  @override
  State<_OperationalPeriodForm> createState() => _OperationalPeriodFormState();
}

class _OperationalPeriodFormState extends State<_OperationalPeriodForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _notes;
  late String _module;
  late String _status;
  late DateTime _startsAt;
  late DateTime _endsAt;
  bool _saving = false;
  final _format = DateFormat('yyyy-MM-dd HH:mm');

  @override
  void initState() {
    super.initState();
    final value = widget.value;
    _name = TextEditingController(text: value?.name ?? '');
    _notes = TextEditingController(text: value?.notes ?? '');
    _module = value?.module ?? 'all';
    _status = value?.status ?? 'open';
    _startsAt = value?.startsAt ?? DateTime.now();
    _endsAt = value?.endsAt ?? DateTime.now().add(const Duration(days: 30));
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime value) async {
    final date = await showDatePicker(
      context: context,
      initialDate: value,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(value),
    );
    if (!mounted) return null;
    final t = time ?? TimeOfDay.fromDateTime(value);
    return DateTime(date.year, date.month, date.day, t.hour, t.minute);
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    if (_endsAt.isBefore(_startsAt)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            context.l10n.isArabic
                ? 'نهاية الفترة تسبق بدايتها.'
                : 'The period end precedes its start.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.save(
        id: widget.value?.id,
        module: _module,
        name: _name.text,
        startsAt: _startsAt,
        endsAt: _endsAt,
        status: _status,
        notes: _notes.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            userFacingError(error, isArabic: context.l10n.isArabic),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: AppText(
        context.l10n.isArabic
            ? (widget.value == null
                  ? 'فترة تشغيلية جديدة'
                  : 'تعديل الفترة التشغيلية')
            : (widget.value == null
                  ? 'New operational period'
                  : 'Edit operational period'),
      ),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _name,
            decoration: InputDecoration(
              labelText: context.l10n.isArabic ? 'اسم الفترة' : 'Period name',
              border: const OutlineInputBorder(),
            ),
            validator: (value) => (value ?? '').trim().isEmpty
                ? (context.l10n.isArabic
                      ? 'اسم الفترة مطلوب'
                      : 'Period name is required')
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _module,
            decoration: InputDecoration(
              labelText: context.l10n.isArabic ? 'الوحدة' : 'Module',
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: 'all',
                child: AppText(
                  context.l10n.isArabic ? 'جميع الوحدات' : 'All modules',
                ),
              ),
              DropdownMenuItem(
                value: 'sales',
                child: AppText(context.l10n.isArabic ? 'المبيعات' : 'Sales'),
              ),
              DropdownMenuItem(
                value: 'purchases',
                child: AppText(
                  context.l10n.isArabic ? 'المشتريات' : 'Purchases',
                ),
              ),
              DropdownMenuItem(
                value: 'accounting',
                child: AppText(
                  context.l10n.isArabic ? 'المحاسبة' : 'Accounting',
                ),
              ),
              DropdownMenuItem(
                value: 'inventory',
                child: AppText(context.l10n.isArabic ? 'المخزون' : 'Inventory'),
              ),
              DropdownMenuItem(
                value: 'maintenance',
                child: AppText(
                  context.l10n.isArabic ? 'الصيانة' : 'Maintenance',
                ),
              ),
            ],
            onChanged: (value) => setState(() => _module = value ?? 'all'),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _DateField(
                label: context.l10n.isArabic ? 'بداية الفترة' : 'Starts at',
                value: _format.format(_startsAt),
                onTap: () async {
                  final value = await _pick(_startsAt);
                  if (value != null) setState(() => _startsAt = value);
                },
              ),
              _DateField(
                label: context.l10n.isArabic ? 'نهاية الفترة' : 'Ends at',
                value: _format.format(_endsAt),
                onTap: () async {
                  final value = await _pick(_endsAt);
                  if (value != null) setState(() => _endsAt = value);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _status,
            decoration: InputDecoration(
              labelText: context.l10n.isArabic
                  ? 'حالة الفترة'
                  : 'Period status',
              border: const OutlineInputBorder(),
            ),
            items: [
              DropdownMenuItem(
                value: 'open',
                child: AppText(context.l10n.isArabic ? 'مفتوحة' : 'Open'),
              ),
              DropdownMenuItem(
                value: 'closed',
                child: AppText(context.l10n.isArabic ? 'مغلقة' : 'Closed'),
              ),
            ],
            onChanged: (value) => setState(() => _status = value ?? 'open'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: context.l10n.isArabic ? 'ملاحظات' : 'Notes',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: AppText(
              context.l10n.isArabic ? 'حفظ الفترة' : 'Save period',
            ),
          ),
        ],
      ),
    ),
  );
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 300,
    child: InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.event_outlined),
        ),
        child: AppText(value),
      ),
    ),
  );
}
