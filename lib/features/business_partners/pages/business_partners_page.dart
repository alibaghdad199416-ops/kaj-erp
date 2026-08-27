import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_pill_tab_bar.dart';
import 'package:quality_line_erp/core/widgets/app_lazy_tab_view.dart';
import 'package:quality_line_erp/features/business_partners/customers/pages/customers_page.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/pages/suppliers_page.dart';

class BusinessPartnersPage extends StatelessWidget {
  const BusinessPartnersPage({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    String t(String arText, String enText) => ar ? arText : enText;
    return DefaultTabController(
      initialIndex: initialIndex.clamp(0, 1).toInt(),
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(12, 2, 12, 6),
            child: AppPillTabBar(
              tabs: [
                AppPillTab(t('العملاء', 'Customers'), Icons.groups_2_rounded),
                AppPillTab(
                  t('الموردون', 'Suppliers'),
                  Icons.local_shipping_rounded,
                ),
              ],
            ),
          ),
          Expanded(
            child: AppLazyTabView(children: [CustomersPage(), SuppliersPage()]),
          ),
        ],
      ),
    );
  }
}
