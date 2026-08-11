import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/printing/vehicle_service_card_pdf_service.dart';
import 'package:quality_line_erp/core/widgets/app_module_dialog.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_model.dart';
import 'package:quality_line_erp/features/maintenance/data/maintenance_repository.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';
import 'package:quality_line_erp/features/maintenance/pages/maintenance_order_details_dialog.dart';

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
  late final Future<Map<String, Object?>> _future =
      widget.cardLoader?.call(widget.car) ??
      MaintenanceRepository().getVehicleServiceCard(widget.car.id);

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
      final raw = card['maintenanceHistory'];
      final history = raw is List
          ? raw
                .whereType<Map>()
                .map((value) => Map<String, Object?>.from(value))
                .toList()
          : const <Map<String, Object?>>[];
      final ar = context.l10n.isArabic;
      String t(String arText, String enText) => ar ? arText : enText;
      return Scaffold(
        appBar: AppBar(
          title: AppText(t('بطاقة خدمة المركبة', 'Vehicle Service Card')),
          actions: [
            IconButton(
              tooltip: t('طباعة PDF', 'Print PDF'),
              onPressed: () => const VehicleServiceCardPdfService().printCard(
                card: card,
                arabic: ar,
              ),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
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
                    _Identity(
                      t('رقم المركبة', 'Vehicle No.'),
                      widget.car.carNumber,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              t('السجل الزمني للصيانة', 'Chronological Maintenance History'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (history.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AppText(
                    t(
                      'لا يوجد سجل صيانة لهذه المركبة.',
                      'No maintenance history for this vehicle.',
                    ),
                  ),
                ),
              )
            else
              ...history.map(
                (order) => Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.car_repair_outlined),
                    title: AppText(order['orderNumber']?.toString() ?? '—'),
                    subtitle: AppText(
                      '${order['maintenanceDate'] ?? ''} • ${order['workflowStage'] ?? ''}',
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          _Identity(
                            t('الفرصة', 'Opportunity'),
                            order['opportunityNumber']?.toString() ?? '—',
                          ),
                          _Identity(
                            t('العميل', 'Customer'),
                            order['customerName']?.toString() ?? '—',
                          ),
                          _Identity(
                            t('الحالة', 'Status'),
                            '${order['workflowStage'] ?? '—'} / ${order['status'] ?? '—'}',
                          ),
                          _Identity(
                            t('نوع التسعير', 'Pricing type'),
                            order['pricingType']?.toString() ?? '—',
                          ),
                          _Identity(
                            t('المخزن', 'Warehouse'),
                            order['warehouseName']?.toString() ?? '—',
                          ),
                          _Identity(
                            t('إذن الصرف', 'Stock issue'),
                            '${order['stockIssueNumber'] ?? '—'} / ${order['stockIssueStatus'] ?? '—'}',
                          ),
                          _Identity(
                            t('فاتورة الصيانة', 'Maintenance invoice'),
                            '${order['invoiceNumber'] ?? '—'} / ${order['invoiceStatus'] ?? '—'}',
                          ),
                          _Identity(
                            t('حالة الدفع', 'Payment status'),
                            '${order['paidAmount'] ?? 0} ${order['currencyCode'] ?? ''} • ${order['paymentStatus'] ?? '—'}',
                          ),
                        ],
                      ),
                      const Divider(),
                      ..._rows(order['items']).map(
                        (item) => ListTile(
                          dense: true,
                          leading: Icon(
                            item['lineType'] == 'service'
                                ? Icons.miscellaneous_services
                                : Icons.inventory_2_outlined,
                          ),
                          title: AppText(item['name']?.toString() ?? '—'),
                          subtitle: AppText(
                            '${t('الكمية', 'Quantity')}: ${item['quantity'] ?? 0} • ${t('سعر العميل', 'Customer price')}: ${item['unitPrice'] ?? 0} ${order['currencyCode'] ?? ''} • ${item['warehouseName'] ?? ''}',
                          ),
                        ),
                      ),
                      if ((order['notes']?.toString().trim() ?? '').isNotEmpty)
                        ListTile(title: AppText(order['notes'].toString())),
                      if ((order['cancelReason']?.toString().trim() ?? '')
                          .isNotEmpty)
                        ListTile(
                          leading: const Icon(Icons.cancel_outlined),
                          title: AppText(
                            '${t('سبب الإلغاء', 'Cancellation reason')}: ${order['cancelReason']}',
                          ),
                        ),
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
          ],
        ),
      );
    },
  );

  static List<Map<String, Object?>> _rows(Object? raw) => raw is List
      ? raw
            .whereType<Map>()
            .map((value) => Map<String, Object?>.from(value))
            .toList(growable: false)
      : const [];

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
}

class _Identity extends StatelessWidget {
  const _Identity(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
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
