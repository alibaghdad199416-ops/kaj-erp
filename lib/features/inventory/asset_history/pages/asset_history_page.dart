import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/exporting/excel_export_service.dart';
import 'package:quality_line_erp/core/exporting/export_document.dart';
import 'package:quality_line_erp/core/exporting/pdf_export_service.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/inventory/asset_history/models/asset_history_event.dart';
import 'package:quality_line_erp/features/inventory/asset_history/repositories/asset_history_repository.dart';
import 'package:quality_line_erp/core/widgets/app_responsive.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/filtering/unified_query_toolbar.dart';

class AssetHistoryPage extends StatefulWidget {
  const AssetHistoryPage.car({super.key, required this.assetId}) : isCar = true;
  const AssetHistoryPage.product({super.key, required this.assetId})
    : isCar = false;

  final String assetId;
  final bool isCar;

  String _eventTitleEn(AssetHistoryEvent event) =>
      switch (event.eventType ?? '') {
        'created' => 'Vehicle created',
        'purchase_confirmed' => 'Purchase received',
        'purchase_cancelled' => 'Purchase receipt reversed',
        'reserved' => 'Vehicle reserved',
        'reservation_cancelled' => 'Reservation cancelled',
        'sale_confirmed' => 'Sales delivery',
        'sale_cancelled' => 'Sales delivery reversed',
        'transferred' => 'Warehouse transfer',
        'opening' => 'Opening balance',
        'purchase' => 'Purchase receipt',
        'purchase_cancel' => 'Purchase receipt reversal',
        'sale' => 'Sales issue',
        'sale_cancel' => 'Sales issue reversal',
        'transfer_in' => 'Transfer in',
        'transfer_out' => 'Transfer out',
        'maintenance_out' => 'Maintenance issue',
        'maintenance_return' => 'Maintenance issue reversal',
        'adjustment_in' => 'Positive adjustment',
        'adjustment_out' => 'Negative adjustment',
        _ => 'Inventory event',
      };

  String _eventDetailsEn(AssetHistoryEvent event) {
    final parts = <String>[];
    if ((event.statusBefore ?? '').isNotEmpty ||
        (event.statusAfter ?? '').isNotEmpty) {
      parts.add(
        'Status: ${event.statusBefore ?? '-'} -> ${event.statusAfter ?? '-'}',
      );
    }
    if ((event.warehouseBefore ?? '').isNotEmpty ||
        (event.warehouseAfter ?? '').isNotEmpty) {
      parts.add(
        'Warehouse: ${event.warehouseBefore ?? '-'} -> ${event.warehouseAfter ?? '-'}',
      );
    }
    if (parts.isEmpty) {
      var value = event.details;
      value = value
          .replaceAll('النوع:', 'Type:')
          .replaceAll('الكمية:', 'Quantity:')
          .replaceAll('المخزن:', 'Warehouse:')
          .replaceAll('كلفة الوحدة:', 'Unit cost:')
          .replaceAll('الكلفة الإجمالية:', 'Total cost:');
      return value;
    }
    return parts.join(' | ');
  }

  String _eventDetailsUi(AssetHistoryEvent event, bool arabic) {
    if (event.quantity != null ||
        event.sourceName != null ||
        event.destinationName != null ||
        event.performedBy != null) {
      final parts = <String>[
        if (event.quantity != null)
          '${arabic ? 'الكمية' : 'Quantity'}: ${event.quantity}',
        if ((event.sourceName ?? '').isNotEmpty)
          '${arabic ? 'من' : 'From'}: ${event.sourceName}',
        if ((event.destinationName ?? '').isNotEmpty)
          '${arabic ? 'إلى' : 'To'}: ${event.destinationName}',
        if ((event.performedBy ?? '').isNotEmpty)
          '${arabic ? 'المنفذ' : 'Performed by'}: ${event.performedBy}',
        if (event.unitCost != null)
          '${arabic ? 'كلفة الوحدة' : 'Unit cost'}: ${event.unitCost}',
        if (event.totalCost != null)
          '${arabic ? 'الكلفة الإجمالية' : 'Total cost'}: ${event.totalCost}',
      ];
      return parts.join('\n');
    }
    return arabic ? event.details : _eventDetailsEn(event);
  }

  @override
  State<AssetHistoryPage> createState() => _AssetHistoryPageState();
}

class _AssetHistoryPageState extends State<AssetHistoryPage> {
  final UnifiedQueryController _queryController = UnifiedQueryController();
  late Future<List<AssetHistoryEvent>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<AssetHistoryEvent>> _load() {
    final repository = AssetHistoryRepository();
    return widget.isCar
        ? repository.carHistory(widget.assetId)
        : repository.productHistory(widget.assetId);
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  void _retry() => setState(() => _future = _load());

  String _eventType(AssetHistoryEvent event) =>
      event.eventType?.trim().isNotEmpty == true
      ? event.eventType!.trim()
      : event.title;

  List<UnifiedQueryFilterOption> _filters(
    BuildContext context,
    List<AssetHistoryEvent> events,
  ) {
    final types =
        events.map(_eventType).where((e) => e.isNotEmpty).toSet().toList()
          ..sort();
    final statuses =
        events
            .expand((e) => [e.statusBefore ?? '', e.statusAfter ?? ''])
            .where((e) => e.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return [
      for (final value in types.take(30))
        UnifiedQueryFilterOption(
          token: UnifiedFilterToken(
            key: 'eventType',
            label: context.l10n.isArabic ? 'نوع الحركة' : 'Event type',
            value: value,
            valueLabel: value,
          ),
          icon: Icons.category_outlined,
        ),
      for (final value in statuses.take(30)) ...[
        UnifiedQueryFilterOption(
          token: UnifiedFilterToken(
            key: 'statusBefore',
            label: context.l10n.isArabic ? 'الحالة السابقة' : 'Previous status',
            value: value,
            valueLabel: value,
          ),
          icon: Icons.flag_outlined,
        ),
        UnifiedQueryFilterOption(
          token: UnifiedFilterToken(
            key: 'statusAfter',
            label: context.l10n.isArabic ? 'الحالة اللاحقة' : 'New status',
            value: value,
            valueLabel: value,
          ),
          icon: Icons.flag_outlined,
        ),
      ],
    ];
  }

  List<UnifiedQuerySortOption> _sorts(BuildContext context) => [
    UnifiedQuerySortOption(
      rule: UnifiedSortRule(
        field: 'date',
        label: context.l10n.isArabic ? 'التاريخ' : 'Date',
      ),
      icon: Icons.schedule_outlined,
    ),
    UnifiedQuerySortOption(
      rule: UnifiedSortRule(
        field: 'quantity',
        label: context.l10n.isArabic ? 'الكمية' : 'Quantity',
      ),
      icon: Icons.numbers_outlined,
    ),
    UnifiedQuerySortOption(
      rule: UnifiedSortRule(
        field: 'totalCost',
        label: context.l10n.isArabic ? 'الكلفة الإجمالية' : 'Total cost',
      ),
      icon: Icons.payments_outlined,
    ),
    UnifiedQuerySortOption(
      rule: UnifiedSortRule(
        field: 'event',
        label: context.l10n.isArabic ? 'الحركة' : 'Event',
      ),
      icon: Icons.swap_horiz_outlined,
    ),
  ];

  List<AssetHistoryEvent> _filtered(List<AssetHistoryEvent> events) {
    final state = _queryController.state;
    final fieldValues = <String, Set<String>>{};
    for (final token in state.filters) {
      final values = fieldValues.putIfAbsent(token.key, () => <String>{});
      values.add(token.value.toString());
    }
    return UnifiedFilterEngine.apply(
      events,
      criteria: UnifiedFilterCriteria(
        searchText: state.search,
        fieldValues: fieldValues,
      ),
      adapter: UnifiedFilterAdapter<AssetHistoryEvent>(
        searchableText: (e) => [
          e.title,
          e.details,
          e.reference,
          e.referenceDocumentNumber,
          e.productName,
          e.sourceName,
          e.destinationName,
          e.performedBy,
          e.eventType,
          e.statusBefore,
          e.statusAfter,
        ],
        fieldValues: {
          'eventType': _eventType,
          'statusBefore': (e) => e.statusBefore ?? '',
          'statusAfter': (e) => e.statusAfter ?? '',
        },
      ),
      sorts: [
        for (final rule in state.sorts)
          UnifiedSortCriterion<AssetHistoryEvent>(
            key: rule.field,
            direction: rule.descending
                ? UnifiedSortDirection.descending
                : UnifiedSortDirection.ascending,
            value: (e) {
              switch (rule.field) {
                case 'date':
                  return e.date ?? DateTime.fromMillisecondsSinceEpoch(0);
                case 'quantity':
                  return e.quantity ?? 0;
                case 'totalCost':
                  return e.totalCost ?? 0;
                case 'event':
                  return e.title.toLowerCase();
                default:
                  return e.title.toLowerCase();
              }
            },
          ),
      ],
    );
  }

  ExportDocument _document(
    BuildContext context,
    List<AssetHistoryEvent> events,
  ) {
    final arabic = context.l10n.isArabic;
    return ExportDocument(
      title: arabic ? 'سجل الأصل' : 'Asset History',
      subtitle: widget.assetId,
      language: arabic ? 'ar' : 'en',
      columns: const <ExportColumn>[
        ExportColumn(
          key: 'date',
          label: 'Date / Time',
          type: ExportValueType.dateTime,
        ),
        ExportColumn(key: 'event', label: 'Event'),
        ExportColumn(key: 'product', label: 'Product'),
        ExportColumn(
          key: 'quantity',
          label: 'Quantity',
          type: ExportValueType.decimal,
        ),
        ExportColumn(key: 'from', label: 'From'),
        ExportColumn(key: 'to', label: 'To'),
        ExportColumn(key: 'performedBy', label: 'Performed by'),
        ExportColumn(
          key: 'unitCost',
          label: 'Unit cost',
          type: ExportValueType.money,
        ),
        ExportColumn(
          key: 'totalCost',
          label: 'Total cost',
          type: ExportValueType.money,
        ),
        ExportColumn(key: 'reference', label: 'Reference'),
        ExportColumn(key: 'details', label: 'Details', width: 2),
      ],
      rows: events
          .map(
            (event) => <Object?>[
              event.date,
              widget._eventTitleEn(event),
              event.productName ?? '',
              event.quantity,
              event.sourceName ?? event.warehouseBefore ?? '',
              event.destinationName ?? event.warehouseAfter ?? '',
              event.performedBy ?? '',
              event.unitCost,
              event.totalCost,
              event.referenceDocumentNumber ?? event.reference ?? '',
              widget._eventDetailsEn(event),
            ],
          )
          .toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AppResponsive.dialogWidth(context, 720),
      height: AppResponsive.dialogHeight(context, 620),
      child: FutureBuilder<List<AssetHistoryEvent>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppText(
                    userFacingError(
                      snapshot.error!,
                      isArabic: context.l10n.isArabic,
                      arabicFallback: 'تعذر تحميل سجل الأصل.',
                      englishFallback: 'Unable to load the asset history.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: AppText(
                      context.l10n.isArabic ? 'إعادة المحاولة' : 'Retry',
                    ),
                  ),
                ],
              ),
            );
          }
          final events = snapshot.data ?? const <AssetHistoryEvent>[];
          final arabic = context.l10n.isArabic;
          final visible = _filtered(events);
          return Column(
            children: [
              UnifiedQueryToolbar(
                controller: _queryController,
                searchHint: arabic
                    ? 'بحث في سجل الأصل...'
                    : 'Search asset history...',
                filters: _filters(context, events),
                sorts: _sorts(context),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: visible.isEmpty
                          ? null
                          : () => ExcelExportService().save(
                              _document(context, visible),
                            ),
                      icon: const Icon(Icons.table_view_outlined),
                      label: const AppText('Excel'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: visible.isEmpty
                          ? null
                          : () => PdfExportService().save(
                              _document(context, visible),
                            ),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const AppText('PDF'),
                    ),
                  ],
                ),
              ),
              if (events.isEmpty)
                Expanded(
                  child: Center(
                    child: AppText(
                      arabic
                          ? 'لا توجد حركات مسجلة حتى الآن.'
                          : 'No history has been recorded yet.',
                    ),
                  ),
                )
              else if (visible.isEmpty)
                Expanded(
                  child: Center(
                    child: AppText(
                      arabic
                          ? 'لا توجد نتائج مطابقة للبحث أو الفلاتر.'
                          : 'No results match the current query.',
                    ),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: [
                          DataColumn(
                            label: AppText(arabic ? 'التاريخ' : 'Date'),
                          ),
                          DataColumn(
                            label: AppText(arabic ? 'الحركة' : 'Event'),
                          ),
                          DataColumn(
                            label: AppText(arabic ? 'التفاصيل' : 'Details'),
                          ),
                          DataColumn(
                            label: AppText(arabic ? 'المرجع' : 'Reference'),
                          ),
                        ],
                        rows: visible
                            .map(
                              (event) => DataRow(
                                cells: [
                                  DataCell(
                                    AppText(
                                      event.date == null
                                          ? '—'
                                          : DateFormat(
                                              'yyyy/MM/dd – HH:mm',
                                            ).format(event.date!.toLocal()),
                                    ),
                                  ),
                                  DataCell(AppText(event.title)),
                                  DataCell(
                                    SizedBox(
                                      width: 320,
                                      child: AppText(
                                        widget._eventDetailsUi(event, arabic),
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                  DataCell(AppText(event.reference ?? '—')),
                                ],
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
