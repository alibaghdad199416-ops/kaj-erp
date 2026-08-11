import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/printing/vehicle_service_card_pdf_service.dart';
import 'package:quality_line_erp/features/inventory/cars/models/car_model.dart';
import 'package:quality_line_erp/features/maintenance/data/maintenance_repository.dart';

class VehicleServiceCardPage extends StatefulWidget {
  const VehicleServiceCardPage({super.key, required this.car});
  final CarModel car;

  @override
  State<VehicleServiceCardPage> createState() => _VehicleServiceCardPageState();
}

class _VehicleServiceCardPageState extends State<VehicleServiceCardPage> {
  late final Future<Map<String, Object?>> _future = MaintenanceRepository()
      .getVehicleServiceCard(widget.car.id);

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
                      ListTile(
                        title: AppText(
                          '${t('العميل', 'Customer')}: ${order['customerName'] ?? '—'}',
                        ),
                      ),
                      ListTile(
                        title: AppText(
                          '${t('قيمة الخدمة', 'Service amount')}: ${order['salePrice'] ?? 0} ${order['currencyCode'] ?? ''}',
                        ),
                      ),
                      if ((order['notes']?.toString().trim() ?? '').isNotEmpty)
                        ListTile(title: AppText(order['notes'].toString())),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
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
