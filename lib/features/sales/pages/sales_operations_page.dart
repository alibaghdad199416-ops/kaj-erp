import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_lazy_tab_view.dart';
import 'package:quality_line_erp/core/widgets/app_pill_tab_bar.dart';
import 'package:quality_line_erp/design_system/kaj_commercial_stage6_components.dart';
import 'package:quality_line_erp/features/sales/workflow/pages/sales_workflow_page.dart';
import 'sales_page.dart';

class SalesOperationsPage extends StatelessWidget {
  const SalesOperationsPage({super.key, this.initialIndex = 0});
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    String t(String arabic, String english) => ar ? arabic : english;

    return DefaultTabController(
      initialIndex: initialIndex.clamp(0, 1).toInt(),
      length: 2,
      child: KajCommercialWorkspace(
        title: t('مركز المبيعات', 'Sales center'),
        subtitle: t(
          'أوامر البيع والتجهيز والفوترة والتحصيل والطباعة ضمن مسار تجاري موحد.',
          'Sales orders, warehouse fulfillment, invoicing, collection and printing in one unified commercial workflow.',
        ),
        icon: Icons.point_of_sale_rounded,
        metrics: <KajCommercialWorkspaceMetric>[
          KajCommercialWorkspaceMetric(
            label: t('المسار', 'Workflow'),
            value: t('بيع', 'Sales'),
            icon: Icons.trending_up_rounded,
          ),
          KajCommercialWorkspaceMetric(
            label: t('التجهيز', 'Fulfillment'),
            value: t('مخزني', 'Warehouse'),
            icon: Icons.inventory_2_outlined,
          ),
          KajCommercialWorkspaceMetric(
            label: t('الفوترة', 'Invoicing'),
            value: t('مترابطة', 'Linked'),
            icon: Icons.request_quote_outlined,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppPillTabBar(
              tabs: <AppPillTab>[
                AppPillTab(t('أوامر البيع', 'Sales orders'), Icons.edit_note_rounded),
                AppPillTab(
                  t('الفواتير القديمة', 'Legacy invoices'),
                  Icons.point_of_sale_rounded,
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Expanded(
              child: AppLazyTabView(
                children: <Widget>[SalesWorkflowPage(), SalesPage()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
