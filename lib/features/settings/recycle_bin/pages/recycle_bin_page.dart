import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/exporting/excel_export_service.dart';
import 'package:quality_line_erp/core/exporting/binary_download_service.dart';
import 'package:quality_line_erp/core/exporting/export_document.dart';
import 'package:quality_line_erp/core/exporting/pdf_export_service.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_full_page_route.dart';
import 'package:quality_line_erp/design_system/kaj_admin_stage8_components.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';
import 'package:quality_line_erp/features/settings/access/widgets/permission_action.dart';
import 'package:quality_line_erp/features/settings/access/models/permission_codes.dart';
import '../models/recycle_bin_item.dart';
import '../repositories/recycle_bin_repository.dart';

class RecycleBinPage extends StatefulWidget {
  const RecycleBinPage({super.key});

  @override
  State<RecycleBinPage> createState() => _RecycleBinPageState();
}

class _RecycleBinPageState extends State<RecycleBinPage> {
  final _repository = RecycleBinRepository();
  final _search = TextEditingController();
  final _dateTime = DateFormat('yyyy-MM-dd HH:mm');
  Timer? _debounce;
  List<RecycleBinItem> _items = const [];
  bool _loading = true;
  bool _exporting = false;
  String _entityType = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await _repository.load(
        query: _search.text,
        entityType: _entityType,
      );
      if (!mounted) return;
      setState(() => _items = items);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<bool> _confirm(
    String title,
    String body, {
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: AppText(title),
            content: AppText(body),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: AppText(context.l10n.text('cancel')),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.error,
                      )
                    : null,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: AppText(
                  destructive
                      ? context.l10n.text('delete')
                      : (context.l10n.isArabic ? 'استعادة' : 'Restore'),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _restore(RecycleBinItem item) async {
    final access = context.read<AccessController>();
    if (!access.canEditField(
      'settings',
      'recycleBin',
      viewPermission: PermissionCodes.recycleBinView,
    ))
      return;
    if (!await PermissionAction.require(
      context,
      PermissionCodes.recycleBinRestore,
    )) {
      return;
    }
    if (!mounted) return;
    final arabic = context.l10n.isArabic;
    final ok = await _confirm(
      arabic ? 'استعادة المحذوفات' : 'Restore deleted data',
      arabic
          ? 'سيتم استعادة السجل وكامل دفعة الارتباطات التابعة له (${item.relatedCount} سجل).'
          : 'The record and its related deletion batch (${item.relatedCount} records) will be restored.',
    );
    if (!ok || !mounted) return;
    try {
      await _repository.restore(item);
      await _load();
      _message(
        arabic
            ? 'تمت استعادة السجل وروابطه بنجاح.'
            : 'The record and its relationships were restored.',
      );
    } catch (error) {
      _message(error.toString(), error: true);
    }
  }

  Future<void> _purge(RecycleBinItem item) async {
    final access = context.read<AccessController>();
    if (!access.canEditField(
      'settings',
      'recycleBin',
      viewPermission: PermissionCodes.recycleBinView,
    ))
      return;
    if (!await PermissionAction.require(
      context,
      PermissionCodes.recycleBinPurge,
    )) {
      return;
    }
    if (!mounted) return;
    final arabic = context.l10n.isArabic;
    final ok = await _confirm(
      arabic ? 'حذف نهائي' : 'Permanent deletion',
      arabic
          ? 'سيتم حذف السجل وكامل دفعة الارتباطات (${item.relatedCount} سجل) نهائياً، ولا يمكن التراجع.'
          : 'The record and its deletion batch (${item.relatedCount} records) will be permanently removed. This cannot be undone.',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await _repository.permanentlyDelete(item);
      await _load();
      _message(
        arabic
            ? 'تم الحذف النهائي لدفعة المحذوفات.'
            : 'The deletion batch was permanently removed.',
      );
    } catch (error) {
      _message(error.toString(), error: true);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: AppText(text),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  String _typeLabel(String value, {bool? isArabic}) {
    const ar = <String, String>{
      'cars': 'السيارات',
      'products': 'المنتجات',
      'customers': 'العملاء',
      'suppliers': 'الموردون',
      'sales': 'المبيعات',
      'purchases': 'المشتريات',
      'maintenanceOrders': 'أوامر الصيانة',
      'expenses': 'المصاريف',
      'warehouseTransfers': 'نقل المخزون',
      'erp_sales_orders_cloud': 'أوامر البيع',
      'erp_sales_order_items_cloud': 'بنود أوامر البيع',
      'erp_purchase_orders_cloud': 'أوامر الشراء',
      'erp_purchase_order_items_cloud': 'بنود أوامر الشراء',
      'erp_commercial_workflow_documents': 'مستندات الدورة التجارية',
      'erp_inventory_movements_cloud': 'حركات المخزون',
      'erp_inventory_movements': 'حركات المخزون',
      'erp_inventory': 'المواد المخزنية',
      'erp_warehouse_stock': 'أرصدة المخازن',
      'erp_inventory_cost_layers': 'وجبات كلفة المخزون',
      'erp_inventory_fifo_consumptions': 'استهلاك وجبات FIFO',
      'erp_cloud_journals': 'القيود المحاسبية',
      'erp_journal_entries': 'القيود المحاسبية',
      'erp_journal_lines': 'تفاصيل القيود المحاسبية',
      'erp_cloud_records': 'السجلات التشغيلية',
      'erp_operational_periods': 'الفترات التشغيلية',
    };
    const en = <String, String>{
      'cars': 'Cars',
      'products': 'Products',
      'customers': 'Customers',
      'suppliers': 'Suppliers',
      'sales': 'Sales',
      'purchases': 'Purchases',
      'maintenanceOrders': 'Maintenance orders',
      'expenses': 'Expenses',
      'warehouseTransfers': 'Warehouse transfers',
      'erp_sales_orders_cloud': 'Sales orders',
      'erp_sales_order_items_cloud': 'Sales order items',
      'erp_purchase_orders_cloud': 'Purchase orders',
      'erp_purchase_order_items_cloud': 'Purchase order items',
      'erp_commercial_workflow_documents': 'Commercial workflow documents',
      'erp_inventory_movements_cloud': 'Inventory movements',
      'erp_inventory_movements': 'Inventory movements',
      'erp_inventory': 'Inventory items',
      'erp_warehouse_stock': 'Warehouse balances',
      'erp_inventory_cost_layers': 'Inventory cost layers',
      'erp_inventory_fifo_consumptions': 'FIFO layer consumption',
      'erp_cloud_journals': 'Accounting journals',
      'erp_journal_entries': 'Accounting journal entries',
      'erp_journal_lines': 'Accounting journal lines',
      'erp_cloud_records': 'Operational records',
      'erp_operational_periods': 'Operational periods',
    };
    return ((isArabic ?? context.l10n.isArabic) ? ar : en)[value] ?? value;
  }

  String _modeLabel(String value, {bool? isArabic}) {
    final hard = value.toLowerCase() == 'hard';
    if (isArabic ?? context.l10n.isArabic) {
      return hard ? 'حذف فعلي' : 'حذف منطقي';
    }
    return hard ? 'Hard delete' : 'Soft delete';
  }

  ExportDocument _report() {
    const exportArabic = false;
    return ExportDocument(
      title: 'Recycle Bin Report',
      subtitle: 'Audit report of deleted records and related batches',
      language: 'en',
      generatedAt: DateTime.now(),
      metadata: {
        'Result count': _items.length,
        'Type filter': _entityType.isEmpty
            ? 'All'
            : _typeLabel(_entityType, isArabic: exportArabic),
        'Search': _search.text.trim(),
      },
      columns: const [
        ExportColumn(key: 'title', label: 'Title', width: 1.5),
        ExportColumn(key: 'type', label: 'Type', width: 1.2),
        ExportColumn(key: 'source', label: 'Source table', width: 1.3),
        ExportColumn(key: 'mode', label: 'Delete mode'),
        ExportColumn(
          key: 'deletedAt',
          label: 'Deleted at',
          type: ExportValueType.dateTime,
          width: 1.2,
        ),
        ExportColumn(key: 'deletedBy', label: 'Deleted by', width: 1.2),
        ExportColumn(
          key: 'related',
          label: 'Related',
          type: ExportValueType.integer,
        ),
        ExportColumn(key: 'reason', label: 'Reason', width: 1.5),
      ],
      rows: _items
          .map(
            (item) => <Object?>[
              item.title,
              _typeLabel(item.entityType, isArabic: exportArabic),
              item.sourceTable,
              _modeLabel(item.deletionMode, isArabic: exportArabic),
              item.deletedAt?.toLocal(),
              item.deletedBy ?? '-',
              item.relatedCount,
              item.deleteReason ?? '-',
            ],
          )
          .toList(growable: false),
    );
  }

  Future<void> _exportPdf() async {
    if (_items.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    try {
      await PdfExportService().preview(
        _report(),
        pageFormat: ExportPageFormat.a4Landscape,
      );
    } catch (error) {
      _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportExcel() async {
    if (_items.isEmpty || _exporting) return;
    final successMessage = context.l10n.isArabic
        ? 'تم إنشاء تقرير Excel.'
        : 'Excel report created.';
    setState(() => _exporting = true);
    try {
      final bytes = await ExcelExportService().build(_report());
      await BinaryDownloadService.save(
        fileName: 'recycle_bin_${DateTime.now().millisecondsSinceEpoch}.xlsx',
        bytes: bytes,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted) return;
      _message(successMessage);
    } catch (error) {
      if (!mounted) return;
      _message(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _showDetails(RecycleBinItem item) {
    final arabic = context.l10n.isArabic;
    final pretty = const JsonEncoder.withIndent('  ').convert(item.payload);
    return showAppFullPageRoute<void>(
      context: context,
      title: arabic ? 'تفاصيل السجل المحذوف' : 'Deleted record details',
      maxWidth: 1080,
      maxHeight: 780,
      minWidth: 520,
      minHeight: 420,
      builder: (dialogContext) => Scaffold(
        appBar: AppBar(title: AppText(item.title)),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _InfoChip(
                    label: arabic ? 'النوع' : 'Type',
                    value: _typeLabel(item.entityType, isArabic: arabic),
                  ),
                  _InfoChip(
                    label: arabic ? 'المصدر' : 'Source',
                    value: item.sourceTable,
                  ),
                  _InfoChip(
                    label: arabic ? 'الحذف' : 'Deletion',
                    value: _modeLabel(item.deletionMode, isArabic: arabic),
                  ),
                  _InfoChip(
                    label: arabic ? 'الوقت' : 'Time',
                    value: item.deletedAt == null
                        ? '—'
                        : _dateTime.format(item.deletedAt!.toLocal()),
                  ),
                  _InfoChip(
                    label: arabic ? 'الارتباطات' : 'Related',
                    value: '${item.relatedCount}',
                  ),
                  if (item.deletedBy != null)
                    _InfoChip(
                      label: arabic ? 'حُذف بواسطة' : 'Deleted by',
                      value: item.deletedBy!,
                    ),
                ],
              ),
              if (item.deleteReason != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: AppText(arabic ? 'سبب الحذف' : 'Deletion reason'),
                    subtitle: AppText(item.deleteReason!),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: AppSelectableText(
                      pretty,
                      textDirection: ui.TextDirection.ltr,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              AppText(
                '${arabic ? 'معرف الدفعة' : 'Batch ID'}: ${item.deletionBatchId ?? '-'}\n'
                '${arabic ? 'السجل الجذر' : 'Root record'}: ${item.rootSourceTable ?? '-'} / ${item.rootRecordId ?? '-'}',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessController>();
    if (!access.canViewField(
      'settings',
      'recycleBin',
      viewPermission: PermissionCodes.recycleBinView,
    ))
      return const SizedBox.shrink();
    final canExport = access.hasPermission(PermissionCodes.reportsExport);
    final types =
        _items
            .map((item) => item.entityType)
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          KajAdminWorkspace(
            title: context.l10n.isArabic
                ? 'سلة المحذوفات والاستعادة'
                : 'Recycle Bin & Recovery',
            subtitle: context.l10n.isArabic
                ? 'مراجعة السجلات المحذوفة واستعادتها أو حذفها نهائياً مع تتبع الارتباطات.'
                : 'Review deleted records, restore them, or permanently purge complete deletion batches.',
            icon: Icons.delete_sweep_outlined,
            metrics: <KajAdminMetricData>[
              KajAdminMetricData(
                label: context.l10n.isArabic ? 'السجلات' : 'Records',
                value: _items.length.toString(),
                icon: Icons.inventory_2_outlined,
              ),
              KajAdminMetricData(
                label: context.l10n.isArabic ? 'التصفية' : 'Filter',
                value: _entityType.isEmpty
                    ? (context.l10n.isArabic ? 'الكل' : 'All')
                    : _typeLabel(_entityType),
                icon: Icons.filter_alt_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 360,
                child: TextField(
                  controller: _search,
                  onChanged: _searchChanged,
                  decoration: InputDecoration(
                    labelText: context.l10n.isArabic
                        ? 'البحث في سلة المحذوفات'
                        : 'Search recycle bin',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 250,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _entityType,
                  decoration: InputDecoration(
                    labelText: context.l10n.isArabic
                        ? 'نوع السجل'
                        : 'Record type',
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: AppText(
                        context.l10n.isArabic ? 'الكل' : 'All',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...types.map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: AppText(
                          _typeLabel(type),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) async {
                    setState(() => _entityType = value ?? '');
                    await _load();
                  },
                ),
              ),
              if (canExport)
                OutlinedButton.icon(
                  onPressed: _items.isEmpty || _exporting ? null : _exportPdf,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: AppText(
                    context.l10n.isArabic ? 'تقرير PDF' : 'PDF report',
                  ),
                ),
              if (canExport)
                OutlinedButton.icon(
                  onPressed: _items.isEmpty || _exporting ? null : _exportExcel,
                  icon: const Icon(Icons.table_view_outlined),
                  label: AppText(
                    context.l10n.isArabic ? 'تقرير Excel' : 'Excel report',
                  ),
                ),
              Chip(
                avatar: const Icon(Icons.inventory_2_outlined, size: 18),
                label: AppText(
                  '${context.l10n.isArabic ? 'النتائج' : 'Results'}: ${_items.length}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_loading)
            KajAdminState(
              kind: KajAdminStateKind.loading,
              title: context.l10n.isArabic
                  ? 'جاري تحميل المحذوفات'
                  : 'Loading deleted records',
              message: context.l10n.isArabic
                  ? 'يتم جلب السجلات ودفعات الارتباطات المحذوفة.'
                  : 'Fetching deleted records and relationship batches.',
            )
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: AppText(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            )
          else if (_items.isEmpty)
            KajAdminState(
              kind: KajAdminStateKind.empty,
              title: context.l10n.isArabic
                  ? 'سلة المحذوفات فارغة'
                  : 'Recycle bin is empty',
              message: context.l10n.isArabic
                  ? 'لا توجد سجلات محذوفة مطابقة لخيارات البحث الحالية.'
                  : 'No deleted records match the current search and filter settings.',
            )
          else
            ..._items.map(
              (item) => Card(
                child: ListTile(
                  onTap: () => _showDetails(item),
                  leading: CircleAvatar(
                    child: Icon(
                      item.isBatch
                          ? Icons.account_tree_outlined
                          : Icons.delete_outline,
                    ),
                  ),
                  title: AppText(item.title),
                  subtitle: AppText(
                    '${_typeLabel(item.entityType)} • ${item.deletedAt == null ? '—' : _dateTime.format(item.deletedAt!.toLocal())}\n'
                    '${_modeLabel(item.deletionMode)} • ${context.l10n.isArabic ? 'الارتباطات' : 'Related'}: ${item.relatedCount}',
                  ),
                  isThreeLine: true,
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: context.l10n.isArabic
                            ? 'عرض التفاصيل'
                            : 'View details',
                        onPressed: () => _showDetails(item),
                        icon: const Icon(Icons.visibility_outlined),
                      ),
                      IconButton(
                        tooltip: context.l10n.isArabic ? 'استعادة' : 'Restore',
                        onPressed: () => _restore(item),
                        icon: const Icon(Icons.restore),
                      ),
                      IconButton(
                        tooltip: context.l10n.isArabic
                            ? 'حذف نهائي'
                            : 'Delete permanently',
                        onPressed: () => _purge(item),
                        icon: const Icon(
                          Icons.delete_forever,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) =>
      Chip(label: AppText('$label: ${value.isEmpty ? '-' : value}'));
}
