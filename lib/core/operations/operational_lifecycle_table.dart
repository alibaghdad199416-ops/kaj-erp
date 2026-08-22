import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/operations/operational_line_lifecycle.dart';

typedef OperationalLifecycleTextBuilder =
    String Function(OperationalLineLifecycle line);

typedef OperationalLifecycleQuantityFormatter = String Function(double value);

/// Shared operational quantity table for sales, purchases and maintenance.
///
/// The widget deliberately accepts raw line/reconciliation rows and delegates
/// every quantity calculation to [OperationalLineLifecycle]. Consumers may
/// normalize display-only labels, but must not recalculate requested,
/// logistics, invoiced or remaining quantities in feature widgets.
class OperationalLifecycleTable extends StatelessWidget {
  const OperationalLifecycleTable({
    super.key,
    required this.rows,
    required this.itemLabel,
    required this.descriptionLabel,
    required this.requestedLabel,
    required this.logisticsLabel,
    required this.invoicedLabel,
    required this.remainingLogisticsLabel,
    required this.remainingInvoiceLabel,
    required this.emptyLabel,
    this.itemTextBuilder,
    this.descriptionTextBuilder,
    this.quantityFormatter = _defaultQuantityFormatter,
  });

  final Iterable<Map<String, Object?>> rows;
  final String itemLabel;
  final String descriptionLabel;
  final String requestedLabel;
  final String logisticsLabel;
  final String invoicedLabel;
  final String remainingLogisticsLabel;
  final String remainingInvoiceLabel;
  final String emptyLabel;
  final OperationalLifecycleTextBuilder? itemTextBuilder;
  final OperationalLifecycleTextBuilder? descriptionTextBuilder;
  final OperationalLifecycleQuantityFormatter quantityFormatter;

  static String _defaultQuantityFormatter(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    final text = value.toStringAsFixed(6);
    return text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final lines = OperationalLineLifecycle.fromRows(rows);
    if (lines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(emptyLabel),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: <DataColumn>[
          DataColumn(label: Text(itemLabel)),
          DataColumn(label: Text(descriptionLabel)),
          DataColumn(label: Text(requestedLabel), numeric: true),
          DataColumn(label: Text(logisticsLabel), numeric: true),
          DataColumn(label: Text(invoicedLabel), numeric: true),
          DataColumn(label: Text(remainingLogisticsLabel), numeric: true),
          DataColumn(label: Text(remainingInvoiceLabel), numeric: true),
        ],
        rows: lines
            .map(
              (line) => DataRow(
                cells: <DataCell>[
                  DataCell(
                    Text(
                      itemTextBuilder?.call(line) ??
                          (line.itemId.isEmpty ? '—' : line.itemId),
                    ),
                  ),
                  DataCell(
                    Text(
                      descriptionTextBuilder?.call(line) ??
                          (line.description.isEmpty ? '—' : line.description),
                    ),
                  ),
                  _quantityCell(line.requestedQuantity),
                  _quantityCell(line.logisticsQuantity),
                  _quantityCell(line.invoicedQuantity),
                  _quantityCell(line.remainingLogisticsQuantity),
                  _quantityCell(line.remainingInvoiceQuantity),
                ],
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  DataCell _quantityCell(double value) => DataCell(
    Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Text(quantityFormatter(value)),
    ),
  );
}
