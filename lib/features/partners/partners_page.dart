import 'package:flutter/material.dart';
import 'package:quality_line_erp/features/business_partners/pages/business_partners_page.dart';

/// Compatibility entry point for the unified ERP partners module.
class PartnersPage extends StatelessWidget {
  const PartnersPage({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  Widget build(BuildContext context) =>
      BusinessPartnersPage(initialIndex: initialIndex);
}
