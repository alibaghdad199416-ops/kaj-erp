import 'package:flutter/material.dart';
import 'package:quality_line_erp/core/operations/operational_line_lifecycle.dart';
import 'package:quality_line_erp/core/utils/erp_display_formatter.dart';

/// Compact shared lifecycle table for operational document lines.
///
/// Sales, purchases and maintenance pass typed [OperationalLineLifecycle]
/// rows. No business quantity arithmetic is allowed in the widget.
class OperationalLifecycleTable extends StatelessWidget {
  const OperationalLifecycleTable({
    super.key,
    required this.lines,
    required this.emptyLabel,
    required this.itemLabel,
    required this.requestedLabel,
    required this.executedLabel,
    required this.invoicedLabel,
    required this.remainingLogisticsLabel,
    required this.remainingInvoiceLabel,
  });

  final List<OperationalLineLifecycle> lines;
  final String emptyLabel;
  final String itemLabel;
  final String requestedLabel;
  final String executedLabel;
  final String invoicedLabel;
  final String remainingLogisticsLabel;
  final String remainingInvoiceLabel;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Center(child: Text(emptyLabel)),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: <DataColumn>[
          DataColumn(label: Text(itemLabel)),
          DataColumn(label: Text(requestedLabel), numeric: true),
          DataColumn(label: Text(executedLabel), numeric: true),
          DataColumn(label: Text(invoicedLabel), numeric: true),
          DataColumn(label: Text(remainingLogisticsLabel), numeric: true),
          DataColumn(label: Text(remainingInvoiceLabel), numeric: true),
        ],
        rows: lines.map((line) {
          final item = line.description.trim().isNotEmpty
              ? line.description.trim()
              : line.itemId;
          return DataRow(
            cells: <DataCell>[
              DataCell(Text(item.isEmpty ? '—' : item)),
              _quantity(line.requestedQuantity),
              DataCell(
                Text(
                  line.requiresLogistics
                      ? ErpDisplayFormatter.formatQuantity(
                          line.logisticsQuantity,
                        )
                      : '—',
                ),
              ),
              _quantity(line.invoicedQuantity),
              DataCell(
                Text(
                  line.requiresLogistics
                      ? ErpDisplayFormatter.formatQuantity(
                          line.remainingLogisticsQuantity,
                        )
                      : '—',
                ),
              ),
              _quantity(line.remainingInvoiceQuantity),
            ],
          );
        }).toList(growable: false),
      ),
    );
  }

  static DataCell _quantity(num value) => DataCell(
    Text(ErpDisplayFormatter.formatQuantity(value)),
  );
}
