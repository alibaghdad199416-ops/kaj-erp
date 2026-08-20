import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_dialog.dart';
import 'package:quality_line_erp/core/printing/vehicle_service_card_pdf_service.dart';
import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_dialog.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_model.dart';
import 'package:quality_line_erp/features/maintenance/data/maintenance_repository.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';
import 'package:quality_line_erp/features/maintenance/pages/add_maintenance_order_page.dart';
import 'package:quality_line_erp/features/maintenance/pages/maintenance_order_details_dialog.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/models/user_model.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';

class VehicleServiceCardPage extends StatefulWidget {
  const VehicleServiceCardPage({
    super.key,
    required this.car,
    this.cardLoader,
    this.onOpenMaintenance,
  });

  final CarModel car;
  final Future<Map<String, Object?>> Function(CarModel car)? cardLoader;
  final Future<void> Function(Map<String, Object?> order)? onOpenMaintenance;

  @override
  State<VehicleServiceCardPage> createState() => _VehicleServiceCardPageState();
}

class _VehicleServiceCardPageState extends State<VehicleServiceCardPage> {
  final MaintenanceRepository _repository = MaintenanceRepository();
  final ScrollController _scheduleScrollController = ScrollController();
  final ScrollController _historyScrollController = ScrollController();
  late Future<Map<String, Object?>> _future;

  bool get _ar => context.l10n.isArabic;
  String t(String ar, String en) => _ar ? ar : en;

  @override
  void initState() {
    super.initState();
    _future = _loadCard();
  }

  @override
  void dispose() {
    _scheduleScrollController.dispose();
    _historyScrollController.dispose();
    super.dispose();
  }

  Future<Map<String, Object?>> _loadCard() =>
      widget.cardLoader?.call(widget.car) ??
      _repository.getVehicleServiceCard(widget.car.id);

  Future<void> _reload() async {
    final next = _loadCard();
    if (mounted) setState(() => _future = next);
    await next;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, Object?>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(child: AppText(snapshot.error.toString()));
      }
      final card = snapshot.data ?? const <String, Object?>{};
      final history = _rows(card['maintenanceHistory']);
      final schedules = _rows(card['maintenanceSchedules']);
      final access = context.read<AccessController>();
      final canViewSchedules = access.canViewField(
        'maintenance',
        MaintenanceRepository.maintenanceScheduleFieldPermission,
        viewPermission: 'maintenance.view',
      );
      final canCreateSchedule =
          access.canPerformAction(
            'maintenance',
            'schedule.create',
            legacyPermission: 'maintenance.create',
          ) &&
          access.canEditField(
            'maintenance',
            MaintenanceRepository.maintenanceScheduleFieldPermission,
            viewPermission: 'maintenance.view',
            writePermission: 'maintenance.create',
          );
      return Scaffold(
        appBar: AppBar(
          title: AppText(t('بطاقة خدمة المركبة', 'Vehicle Service Card')),
          actions: [
            IconButton(
              tooltip: t('تحديث', 'Refresh'),
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
            IconButton(
              tooltip: t('طباعة PDF', 'Print PDF'),
              onPressed: () => const VehicleServiceCardPdfService().printCard(
                card: card,
                arabic: _ar,
              ),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _vehicleIdentity(),
            const SizedBox(height: 16),
            if (canViewSchedules) ...<Widget>[
              _sectionHeader(
                icon: Icons.event_repeat_rounded,
                title: t(
                  'جدولة صيانة المركبة',
                  'Vehicle Maintenance Scheduling',
                ),
                trailing: canCreateSchedule
                    ? FilledButton.icon(
                        onPressed: () => _editSchedule(),
                        icon: const Icon(Icons.add_alarm_rounded),
                        label: AppText(t('إضافة جدول', 'Add schedule')),
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              _scheduleTable(schedules),
              const SizedBox(height: 20),
            ],
            _sectionHeader(
              icon: Icons.history_rounded,
              title: t(
                'السجل الزمني المفصل للصيانة',
                'Detailed Maintenance History',
              ),
            ),
            const SizedBox(height: 8),
            _historyTable(history),
          ],
        ),
      );
    },
  );

  Widget _vehicleIdentity() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 20,
        runSpacing: 10,
        children: [
          _Identity(
            t('المركبة', 'Vehicle'),
            '${widget.car.brand} ${widget.car.model}',
          ),
          _Identity(t('السنة', 'Year'), '${widget.car.year}'),
          _Identity(t('رقم الشاصي', 'Chassis'), widget.car.chassis),
          _Identity(t('رقم اللوحة', 'Plate'), widget.car.plateNumber),
          _Identity(t('رقم المركبة', 'Vehicle No.'), widget.car.carNumber),
          _Identity(t('الحالة', 'Status'), widget.car.status),
        ],
      ),
    ),
  );

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    Widget? trailing,
  }) => Row(
    children: [
      Icon(icon),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ),
      ?trailing,
    ],
  );

  Widget _scheduleTable(List<Map<String, Object?>> schedules) {
    final access = context.read<AccessController>();
    final canEditSchedule =
        access.canPerformAction(
          'maintenance',
          'schedule.update',
          legacyPermission: 'maintenance.update',
        ) &&
        access.canEditField(
          'maintenance',
          MaintenanceRepository.maintenanceScheduleFieldPermission,
          viewPermission: 'maintenance.view',
          writePermission: 'maintenance.update',
        );
    final canDeleteSchedule = access.canPerformAction(
      'maintenance',
      'schedule.delete',
      legacyPermission: 'maintenance.delete',
    );
    final canConvertSchedule = access.canPerformAction(
      'maintenance',
      'schedule.convert',
      legacyPermission: 'maintenance.create',
    );
    if (schedules.isEmpty) {
      return _emptyCard(
        t(
          'لا توجد جداول صيانة لهذه المركبة. يمكن جدولة السيارة سواء كانت في المخزن أو مباعة.',
          'No maintenance schedules for this vehicle. Scheduling works for in-stock and sold vehicles.',
        ),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) => Scrollbar(
          controller: _scheduleScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scheduleScrollController,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                columnSpacing: 22,
                columns: [
                  _column('العنوان', 'Title'),
                  _column('الوصف', 'Description'),
                  _column('الاستحقاق', 'Due date & time'),
                  _column('التكرار', 'Recurrence'),
                  _column('المسند إليه', 'Assigned user'),
                  _column('أنشأ بواسطة', 'Created by'),
                  _column('التذكير', 'Reminder'),
                  _column('الحالة', 'Status'),
                  _column('أمر الصيانة', 'Linked order'),
                  _column('العمليات', 'Actions'),
                ],
                rows: schedules
                    .map(
                      (schedule) => DataRow(
                        cells: [
                          _cell(schedule['title'], strong: true),
                          _cell(schedule['description']),
                          _cell(_dateTime(schedule['dueAt'])),
                          _cell(_recurrenceLabel(schedule['recurrence'])),
                          _cell(schedule['assignedUserName']),
                          _cell(schedule['createdByName']),
                          _cell(_reminderLabel(schedule['reminderMinutes'])),
                          _cell(_statusLabel(schedule['status'])),
                          _cell(schedule['linkedMaintenanceOrderNumber']),
                          DataCell(
                            Wrap(
                              spacing: 4,
                              children: [
                                if (canEditSchedule)
                                  IconButton(
                                    tooltip: t('تعديل', 'Edit'),
                                    onPressed: () => _editSchedule(schedule),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                if (canConvertSchedule &&
                                    (schedule['linkedMaintenanceOrderId']
                                                ?.toString()
                                                .trim() ??
                                            '')
                                        .isEmpty)
                                  IconButton(
                                    tooltip: t(
                                      'تحويل إلى أمر صيانة',
                                      'Convert to Maintenance Order',
                                    ),
                                    onPressed: () => _convertSchedule(schedule),
                                    icon: const Icon(Icons.car_repair_outlined),
                                  ),
                                if (canDeleteSchedule)
                                  IconButton(
                                    tooltip: t('حذف', 'Delete'),
                                    onPressed: () => _deleteSchedule(schedule),
                                    icon: Icon(
                                      Icons.delete_outline,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _historyTable(List<Map<String, Object?>> history) {
    if (history.isEmpty) {
      return _emptyCard(
        t(
          'لا يوجد سجل صيانة لهذه المركبة.',
          'No maintenance history for this vehicle.',
        ),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) => Scrollbar(
              controller: _historyScrollController,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _historyScrollController,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    columnSpacing: 22,
                    columns: [
                      _column('أمر الصيانة', 'Maintenance order'),
                      _column('التاريخ والوقت', 'Date & time'),
                      _column('المستخدم / المسؤول', 'User / Responsible'),
                      _column('الصرف المخزني', 'Material issues'),
                      _column('الفاتورة', 'Invoice'),
                      _column('الدفعات', 'Payments'),
                      _column('التكاليف', 'Costs'),
                      _column('العملة', 'Currency'),
                      _column('التفاصيل', 'Details'),
                    ],
                    rows: history
                        .map(
                          (order) => DataRow(
                            cells: [
                              _cell(order['orderNumber'], strong: true),
                              _cell(_dateTime(order['maintenanceDate'])),
                              _cell(
                                order['responsibleUser'] ??
                                    order['createdByName'] ??
                                    '—',
                              ),
                              _cell(_materialIssueText(order)),
                              _cell(order['invoiceNumber']),
                              _cell(_paymentsText(order)),
                              _cell(_costsText(order)),
                              _cell(order['currencyCode']),
                              DataCell(
                                FilledButton.tonalIcon(
                                  key: ValueKey(
                                    'maintenance-history-${order['id']}',
                                  ),
                                  onPressed: () => _showHistoryDetails(order),
                                  icon: const Icon(Icons.visibility_outlined),
                                  label: AppText(t('عرض', 'View')),
                                ),
                              ),
                            ],
                          ),
                        )
                        .toList(growable: false),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  DataColumn _column(String ar, String en) =>
      DataColumn(label: AppText(t(ar, en)));

  DataCell _cell(Object? value, {bool strong = false}) => DataCell(
    ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: AppText(
        _value(value),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: strong ? const TextStyle(fontWeight: FontWeight.w800) : null,
      ),
    ),
  );

  Widget _emptyCard(String message) => Card(
    child: Padding(padding: const EdgeInsets.all(24), child: AppText(message)),
  );

  Future<void> _editSchedule([Map<String, Object?>? existing]) async {
    final access = context.read<AccessController>();
    final action = existing == null ? 'schedule.create' : 'schedule.update';
    final legacy = existing == null
        ? 'maintenance.create'
        : 'maintenance.update';
    if (!access.canPerformAction(
      'maintenance',
      action,
      legacyPermission: legacy,
    )) {
      await PermissionAction.require(context, legacy);
      return;
    }
    if (!mounted) return;

    final title = TextEditingController(text: existing?['title']?.toString());
    final description = TextEditingController(
      text: existing?['description']?.toString(),
    );
    DateTime due =
        DateTime.tryParse(existing?['dueAt']?.toString() ?? '')?.toLocal() ??
        DateTime.now().add(const Duration(days: 1));
    String recurrence = existing?['recurrence']?.toString() ?? 'none';
    int reminderMinutes = _int(existing?['reminderMinutes'], 1440);
    String status = existing?['status']?.toString() ?? 'scheduled';
    final users = access.users.where((user) => user.isActive).toList();
    String? assignedUser = existing?['assignedUserId']?.toString();
    assignedUser ??= _authUserId(access.currentUser);
    final canAssignOther = access.canPerformAction(
      'maintenance',
      'schedule.assign_other',
      legacyPermission: 'maintenance.update',
    );

    final saved = await showAppModuleDialog<bool>(
      context: context,
      title: existing == null
          ? t('جدولة صيانة جديدة', 'New Maintenance Schedule')
          : t('تعديل جدول الصيانة', 'Edit Maintenance Schedule'),
      windowKey: 'maintenance:schedule:${existing?['id'] ?? widget.car.id}',
      maxWidth: 720,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: AppText(
            existing == null
                ? t('جدولة صيانة', 'Schedule Maintenance')
                : t('تعديل الجدولة', 'Edit Schedule'),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: title,
                    decoration: InputDecoration(
                      labelText: t('العنوان', 'Title'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: description,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: t('الوصف', 'Description'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: AppText(
                      t('تاريخ ووقت الاستحقاق', 'Due date & time'),
                    ),
                    subtitle: AppText(_dateTime(due.toIso8601String())),
                    trailing: const Icon(Icons.event_rounded),
                    onTap: () async {
                      final date = await showDatePicker(
                        context: dialogContext,
                        initialDate: due,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 1),
                        ),
                        lastDate: DateTime.now().add(
                          const Duration(days: 3650),
                        ),
                      );
                      if (date == null || !dialogContext.mounted) return;
                      final time = await showTimePicker(
                        context: dialogContext,
                        initialTime: TimeOfDay.fromDateTime(due),
                      );
                      if (time == null) return;
                      setDialogState(() {
                        due = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: recurrence,
                    decoration: InputDecoration(
                      labelText: t('التكرار', 'Recurrence'),
                    ),
                    items:
                        const ['none', 'daily', 'weekly', 'monthly', 'yearly']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: AppText(_recurrenceLabel(value)),
                              ),
                            )
                            .toList(),
                    onChanged: (value) =>
                        setDialogState(() => recurrence = value ?? 'none'),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue:
                        users.any((user) => _authUserId(user) == assignedUser)
                        ? assignedUser
                        : null,
                    decoration: InputDecoration(
                      labelText: t('المستخدم المسند إليه', 'Assigned user'),
                    ),
                    items: users
                        .where(
                          (user) =>
                              canAssignOther ||
                              _authUserId(user) ==
                                  _authUserId(access.currentUser),
                        )
                        .map(
                          (user) => DropdownMenuItem(
                            value: _authUserId(user),
                            child: AppText(
                              user.fullName.trim().isEmpty
                                  ? user.username
                                  : user.fullName,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => assignedUser = value),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    isExpanded: true,
                    initialValue:
                        <int>[
                          0,
                          60,
                          360,
                          1440,
                          2880,
                          10080,
                        ].contains(reminderMinutes)
                        ? reminderMinutes
                        : 1440,
                    decoration: InputDecoration(
                      labelText: t('موعد التذكير', 'Reminder timing'),
                    ),
                    items: const [0, 60, 360, 1440, 2880, 10080]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: AppText(_reminderLabel(value)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => reminderMinutes = value ?? 1440),
                  ),
                  if (existing != null) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: status,
                      decoration: InputDecoration(
                        labelText: t('الحالة', 'Status'),
                      ),
                      items:
                          const ['scheduled', 'due', 'completed', 'cancelled']
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: AppText(_statusLabel(value)),
                                ),
                              )
                              .toList(),
                      onChanged: (value) =>
                          setDialogState(() => status = value ?? status),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: AppText(t('إلغاء', 'Cancel')),
            ),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty || assignedUser == null) return;
                try {
                  await _repository.saveMaintenanceSchedule({
                    if (existing?['id'] != null) 'id': existing!['id'],
                    'carId': widget.car.id,
                    'title': title.text.trim(),
                    'description': description.text.trim(),
                    'dueAt': due.toUtc().toIso8601String(),
                    'recurrence': recurrence,
                    'assignedUserId': assignedUser,
                    'reminderMinutes': reminderMinutes,
                    'status': status,
                    if (existing?['linkedMaintenanceOrderId'] != null)
                      'linkedMaintenanceOrderId':
                          existing!['linkedMaintenanceOrderId'],
                  });
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(
                      content: AppText(userFacingError(error, isArabic: _ar)),
                    ),
                  );
                }
              },
              child: AppText(t('حفظ', 'Save')),
            ),
          ],
        ),
      ),
    );
    title.dispose();
    description.dispose();
    if (saved == true) await _reload();
  }

  Future<void> _deleteSchedule(Map<String, Object?> schedule) async {
    final access = context.read<AccessController>();
    if (!access.canPerformAction(
      'maintenance',
      'schedule.delete',
      legacyPermission: 'maintenance.delete',
    )) {
      await PermissionAction.require(context, 'maintenance.delete');
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context,
      title: t('حذف جدول الصيانة', 'Delete Maintenance Schedule'),
      message: t(
        'سيتم حذف الجدولة فقط ولن يُحذف أي أمر صيانة مرتبط.',
        'Only the schedule will be deleted; linked maintenance orders are preserved.',
      ),
      confirmLabel: t('حذف', 'Delete'),
      destructive: true,
    );
    if (!confirmed) return;
    await _repository.deleteMaintenanceSchedule(schedule['id'].toString());
    await _reload();
  }

  Future<void> _convertSchedule(Map<String, Object?> schedule) async {
    final access = context.read<AccessController>();
    if (!access.canPerformAction(
      'maintenance',
      'schedule.convert',
      legacyPermission: 'maintenance.create',
    )) {
      await PermissionAction.require(context, 'maintenance.create');
      return;
    }
    final before = await _repository.getOrders();
    if (!mounted) return;
    final changed = await showAppWorkspaceDialog<bool>(
      context: context,
      child: AddMaintenanceOrderPage(initialCarId: widget.car.id),
    );
    if (changed != true) return;
    final beforeIds = before.map((order) => order.id).toSet();
    final after = await _repository.getOrders();
    final created =
        after
            .where(
              (order) =>
                  order.carId == widget.car.id && !beforeIds.contains(order.id),
            )
            .toList()
          ..sort((a, b) {
            final aStamp = a.updatedAt ?? DateTime.tryParse(a.maintenanceDate);
            final bStamp = b.updatedAt ?? DateTime.tryParse(b.maintenanceDate);
            if (aStamp == null && bStamp == null) return 0;
            if (aStamp == null) return 1;
            if (bStamp == null) return -1;
            return bStamp.compareTo(aStamp);
          });
    if (created.isNotEmpty) {
      await _repository.linkMaintenanceScheduleToOrder(
        scheduleId: schedule['id'].toString(),
        maintenanceOrderId: created.first.id,
      );
    }
    await _reload();
  }

  Future<void> _showHistoryDetails(Map<String, Object?> order) async {
    final details = _rows(order['customDetails']);
    final access = context.read<AccessController>();
    final canEditHistoryDetails =
        access.canPerformAction(
          'maintenance',
          'history_detail.edit',
          legacyPermission: 'maintenance.update',
        ) &&
        access.canEditField(
          'maintenance',
          'maintenanceHistoryDetails',
          viewPermission: 'maintenance.view',
          writePermission: 'maintenance.update',
        );
    final changed = await showAppModuleDialog<bool>(
      context: context,
      title:
          '${t('تفاصيل الصيانة', 'Maintenance Details')} ${order['orderNumber'] ?? ''}',
      windowKey: 'maintenance:history:${order['id']}',
      maxWidth: 900,
      maxHeight: 760,
      builder: (dialogContext) => AlertDialog(
        title: AppText(order['orderNumber']?.toString() ?? '—'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _Identity(
                      t('التاريخ', 'Date'),
                      _dateTime(order['maintenanceDate']),
                    ),
                    _Identity(
                      t('المسؤول', 'Responsible'),
                      _value(
                        order['responsibleUser'] ?? order['createdByName'],
                      ),
                    ),
                    _Identity(
                      t('المخزن', 'Warehouse'),
                      _value(order['warehouseName']),
                    ),
                    _Identity(
                      t('إذن الصرف', 'Material issue'),
                      _materialIssueText(order),
                    ),
                    _Identity(
                      t('الفاتورة', 'Invoice'),
                      _value(order['invoiceNumber']),
                    ),
                    _Identity(t('الدفعات', 'Payments'), _paymentsText(order)),
                    _Identity(t('التكاليف', 'Costs'), _costsText(order)),
                    _Identity(
                      t('العملة', 'Currency'),
                      _value(order['currencyCode']),
                    ),
                  ],
                ),
                const Divider(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t('تفاصيل حرة مخصصة', 'Custom free-form details'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (canEditHistoryDetails)
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          final saved = await _editHistoryDetail(order);
                          if (saved && dialogContext.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: AppText(t('إضافة تفصيل', 'Add detail')),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (details.isEmpty)
                  AppText(t('لا توجد تفاصيل مخصصة.', 'No custom details.'))
                else
                  ...details.map(
                    (detail) => Card(
                      child: ListTile(
                        title: AppText(detail['title']?.toString() ?? '—'),
                        subtitle: AppText(
                          detail['description']?.toString() ?? '',
                        ),
                        trailing: canEditHistoryDetails
                            ? Wrap(
                                spacing: 2,
                                children: [
                                  IconButton(
                                    tooltip: t('تعديل', 'Edit'),
                                    onPressed: () async {
                                      final saved = await _editHistoryDetail(
                                        order,
                                        detail,
                                      );
                                      if (saved && dialogContext.mounted) {
                                        Navigator.pop(dialogContext, true);
                                      }
                                    },
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: t('حذف', 'Delete'),
                                    onPressed: () async {
                                      await _repository
                                          .deleteMaintenanceHistoryDetail(
                                            detail['id'].toString(),
                                          );
                                      if (dialogContext.mounted) {
                                        Navigator.pop(dialogContext, true);
                                      }
                                    },
                                    icon: Icon(
                                      Icons.delete_outline,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    ),
                  ),
                const Divider(height: 28),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton.icon(
                    key: ValueKey('open-maintenance-${order['id']}'),
                    onPressed: () => _openMaintenance(order),
                    icon: const Icon(Icons.open_in_new),
                    label: AppText(
                      t('فتح أمر الصيانة', 'Open Maintenance Order'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: AppText(t('إغلاق', 'Close')),
          ),
        ],
      ),
    );
    if (changed == true) {
      await _reload();
      if (mounted) {
        final refreshed = await _future;
        final refreshedOrder = _rows(refreshed['maintenanceHistory'])
            .where((row) => row['id']?.toString() == order['id']?.toString())
            .firstOrNull;
        if (refreshedOrder != null && mounted) {
          await _showHistoryDetails(refreshedOrder);
        }
      }
    }
  }

  Future<bool> _editHistoryDetail(
    Map<String, Object?> order, [
    Map<String, Object?>? detail,
  ]) async {
    final access = context.read<AccessController>();
    if (!access.canPerformAction(
          'maintenance',
          'history_detail.edit',
          legacyPermission: 'maintenance.update',
        ) ||
        !access.canEditField(
          'maintenance',
          'maintenanceHistoryDetails',
          viewPermission: 'maintenance.view',
          writePermission: 'maintenance.update',
        )) {
      await PermissionAction.require(context, 'maintenance.update');
      return false;
    }
    if (!mounted) return false;
    final title = TextEditingController(text: detail?['title']?.toString());
    final description = TextEditingController(
      text: detail?['description']?.toString(),
    );
    final saved = await showAppModuleDialog<bool>(
      context: context,
      title: t('تفصيل صيانة مخصص', 'Custom Maintenance Detail'),
      windowKey: 'maintenance:history-detail:${detail?['id'] ?? order['id']}',
      maxWidth: 620,
      builder: (dialogContext) => AlertDialog(
        title: AppText(t('تفصيل مخصص', 'Custom detail')),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: InputDecoration(
                  labelText: t('عنوان مخصص', 'Custom title'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: description,
                minLines: 4,
                maxLines: 10,
                decoration: InputDecoration(
                  labelText: t('وصف مخصص', 'Custom description'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: AppText(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () async {
              if (title.text.trim().isEmpty) return;
              await _repository.saveMaintenanceHistoryDetail({
                if (detail?['id'] != null) 'id': detail!['id'],
                'carId': widget.car.id,
                'maintenanceOrderId': order['id'],
                'title': title.text.trim(),
                'description': description.text.trim(),
                'sortOrder':
                    detail?['sortOrder'] ??
                    _rows(order['customDetails']).length,
              });
              if (dialogContext.mounted) Navigator.pop(dialogContext, true);
            },
            child: AppText(t('حفظ', 'Save')),
          ),
        ],
      ),
    );
    title.dispose();
    description.dispose();
    return saved == true;
  }

  Future<void> _openMaintenance(Map<String, Object?> raw) async {
    if (widget.onOpenMaintenance != null) {
      await widget.onOpenMaintenance!(raw);
      return;
    }
    final order = MaintenanceOrderModel.fromMap(Map<String, dynamic>.from(raw));
    final lines = _rows(raw['items'])
        .map(
          (value) =>
              MaintenanceLineModel.fromMap(Map<String, dynamic>.from(value)),
        )
        .toList(growable: false);
    await showAppModuleDialog<void>(
      context: context,
      title: order.orderNumber,
      windowKey: 'maintenance:details:${order.id}',
      builder: (_) =>
          MaintenanceOrderDetailsDialog(order: order, initialLines: lines),
    );
  }

  String _materialIssueText(Map<String, Object?> order) {
    final issues = _rows(order['materialIssues']);
    if (issues.isNotEmpty) {
      return issues
          .map(
            (issue) =>
                '${_value(issue['reference'])} (${_statusLabel(issue['status'])})',
          )
          .join(' • ');
    }
    return _value(order['stockIssueNumber']);
  }

  String _paymentsText(Map<String, Object?> order) {
    final payments = _rows(order['paymentReferences'] ?? order['payments']);
    if (payments.isEmpty) {
      final paid = order['paidAmount'];
      return paid == null
          ? '—'
          : '${_value(paid)} ${_value(order['currencyCode'])}';
    }
    return payments
        .map(
          (payment) =>
              '${_value(payment['id'] ?? payment['reference'])}: ${_value(payment['amount'])} ${_value(payment['currencyCode'] ?? order['currencyCode'])}',
        )
        .join(' • ');
  }

  String _costsText(Map<String, Object?> order) {
    final currency = _value(order['currencyCode']);
    final parts = order['partsCost'];
    final labor = order['laborCost'];
    final total = order['totalCost'];
    final sale = order['salePrice'];
    final values = <String>[];
    if (parts != null) values.add('${t('مواد', 'Parts')}: ${_value(parts)}');
    if (labor != null) values.add('${t('عمل', 'Labor')}: ${_value(labor)}');
    if (total != null) values.add('${t('كلفة', 'Cost')}: ${_value(total)}');
    if (sale != null) values.add('${t('بيع', 'Sale')}: ${_value(sale)}');
    return values.isEmpty ? '—' : '${values.join(' • ')} $currency';
  }

  String _dateTime(Object? value) {
    final date = value is DateTime
        ? value.toLocal()
        : DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return date == null
        ? _value(value)
        : DateFormat('yyyy/MM/dd HH:mm').format(date);
  }

  String _recurrenceLabel(Object? value) => switch (value?.toString()) {
    'daily' => t('يومي', 'Daily'),
    'weekly' => t('أسبوعي', 'Weekly'),
    'monthly' => t('شهري', 'Monthly'),
    'yearly' => t('سنوي', 'Yearly'),
    _ => t('بدون تكرار', 'No recurrence'),
  };

  String _statusLabel(Object? value) => switch (value?.toString()) {
    'scheduled' => t('مجدول', 'Scheduled'),
    'due' => t('مستحق', 'Due'),
    'completed' => t('مكتمل', 'Completed'),
    'cancelled' => t('ملغي', 'Cancelled'),
    'converted' => t('مرتبط بأمر صيانة', 'Converted'),
    'approved' => t('مصدق', 'Approved'),
    'draft' => t('مسودة', 'Draft'),
    _ => _value(value),
  };

  String _reminderLabel(Object? raw) {
    final minutes = _int(raw, 0);
    if (minutes <= 0) return t('وقت الاستحقاق', 'At due time');
    if (minutes % 1440 == 0) {
      final days = minutes ~/ 1440;
      return t('قبل $days يوم', '$days day(s) before');
    }
    if (minutes % 60 == 0) {
      final hours = minutes ~/ 60;
      return t('قبل $hours ساعة', '$hours hour(s) before');
    }
    return t('قبل $minutes دقيقة', '$minutes minute(s) before');
  }

  String? _authUserId(UserModel? user) {
    if (user == null) return null;
    final cloud = user.cloudAuthUid?.trim();
    if (cloud != null && cloud.isNotEmpty) return cloud;
    final id = user.id.trim();
    return _uuid.hasMatch(id) ? id : null;
  }

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  static int _int(Object? value, int fallback) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

  static String _value(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text.toLowerCase() == 'null' ? '—' : text;
  }

  static List<Map<String, Object?>> _rows(Object? raw) => raw is List
      ? raw
            .whereType<Map>()
            .map((value) => Map<String, Object?>.from(value))
            .toList(growable: false)
      : const <Map<String, Object?>>[];
}

class _Identity extends StatelessWidget {
  const _Identity(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 210,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        AppSelectableText(
          value.trim().isEmpty ? '—' : value,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
