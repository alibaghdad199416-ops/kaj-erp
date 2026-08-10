import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/widgets/compact_metric_pill.dart';

class CustomersStatistics extends StatelessWidget {
  const CustomersStatistics({
    super.key,
    required this.totalCustomers,
    required this.visibleCustomers,
  });

  final int totalCustomers;
  final int visibleCustomers;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CompactMetricPill(
          icon: Icons.groups_2_outlined,
          label: 'إجمالي العملاء',
          value: '$totalCustomers',
        ),
        const SizedBox(width: 7),
        CompactMetricPill(
          icon: Icons.filter_alt_outlined,
          label: 'النتائج الظاهرة',
          value: '$visibleCustomers',
        ),
      ],
    );
  }
}
