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

class AssetHistoryPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final repository = AssetHistoryRepository();
    final future = isCar
        ? repository.carHistory(assetId)
        : repository.productHistory(assetId);
    return SizedBox(
      width: AppResponsive.dialogWidth(context, 720),
      height: AppResponsive.dialogHeight(context, 560),
      child: FutureBuilder<List<AssetHistoryEvent>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: AppText(
                userFacingError(
                  snapshot.error!,
                  isArabic: context.l10n.isArabic,
                  arabicFallback: 'تعذر تحميل سجل الأصل.',
                  englishFallback: 'Unable to load the asset history.',
                ),
              ),
            );
          }
          final events = snapshot.data ?? const <AssetHistoryEvent>[];
          if (events.isEmpty) {
            return Center(
              child: AppText(
                context.l10n.isArabic
                    ? 'لا توجد حركات مسجلة حتى الآن.'
                    : 'No history has been recorded yet.',
              ),
            );
          }
          final arabic = context.l10n.isArabic;
          final document = ExportDocument(
            title: 'Asset History',
            subtitle: assetId,
            language: 'en',
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
                    _eventTitleEn(event),
                    event.productName ?? '',
                    event.quantity,
                    event.sourceName ?? event.warehouseBefore ?? '',
                    event.destinationName ?? event.warehouseAfter ?? '',
                    event.performedBy ?? '',
                    event.unitCost,
                    event.totalCost,
                    event.referenceDocumentNumber ?? event.reference ?? '',
                    _eventDetailsEn(event),
                  ],
                )
                .toList(growable: false),
          );
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => ExcelExportService().save(document),
                      icon: const Icon(Icons.table_view_outlined),
                      label: AppText(arabic ? 'Excel' : 'Excel'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => PdfExportService().save(document),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: const AppText('PDF'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: [
                        DataColumn(label: AppText(arabic ? 'التاريخ' : 'Date')),
                        DataColumn(label: AppText(arabic ? 'الحركة' : 'Event')),
                        DataColumn(
                          label: AppText(arabic ? 'التفاصيل' : 'Details'),
                        ),
                        DataColumn(
                          label: AppText(arabic ? 'المرجع' : 'Reference'),
                        ),
                      ],
                      rows: events
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
                                      _eventDetailsUi(event, arabic),
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
