import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_pill_tab_bar.dart';
import 'package:quality_line_erp/core/widgets/app_lazy_tab_view.dart';
import 'package:quality_line_erp/core/widgets/app_workspace_chrome_scope.dart';
import 'package:quality_line_erp/design_system/kaj_relationship_stage5_components.dart';
import 'package:quality_line_erp/features/business_partners/customers/pages/customers_page.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/pages/suppliers_page.dart';

class BusinessPartnersPage extends StatelessWidget {
  const BusinessPartnersPage({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    final shellOwnsIdentity = AppWorkspaceChromeScope.hasTopBarOf(context);
    String t(String arText, String enText) => ar ? arText : enText;
    return DefaultTabController(
      initialIndex: initialIndex.clamp(0, 1).toInt(),
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!shellOwnsIdentity)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 6),
              child: KajRelationshipHero(
                eyebrow: t('علاقات مؤسسية موحدة', 'UNIFIED RELATIONSHIPS'),
                icon: Icons.handshake_rounded,
                title: t('مركز الشركاء التجاريين', 'Business partner center'),
                subtitle: t(
                  'ملف موحد للعملاء والموردين يجمع الهوية والاتصال والحسابات والدفعات والمستندات في تجربة مؤسسية راقية.',
                  'A unified customer and supplier profile combining identity, communication, accounts, payments, and documents in one refined workspace.',
                ),
              ),
            ),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              12,
              shellOwnsIdentity ? 6 : 2,
              12,
              5,
            ),
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
