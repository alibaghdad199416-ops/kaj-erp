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
    String tr(String value) => AppTranslation.translateForLocale(
      value,
      Localizations.localeOf(context).languageCode,
    );
    return DefaultTabController(
      initialIndex: initialIndex.clamp(0, 1).toInt(),
      length: 2,
      child: KajCommercialWorkspace(
        title: tr('مركز المبيعات'),
        subtitle: tr(
          'أوامر البيع والتجهيز والفوترة والتحصيل والطباعة ضمن مسار تجاري موحد.',
        ),
        icon: Icons.point_of_sale_rounded,
        metrics: <KajCommercialWorkspaceMetric>[
          KajCommercialWorkspaceMetric(
            label: tr('المسار'),
            value: tr('بيع'),
            icon: Icons.trending_up_rounded,
          ),
          KajCommercialWorkspaceMetric(
            label: tr('التجهيز'),
            value: tr('مخزني'),
            icon: Icons.inventory_2_outlined,
          ),
          KajCommercialWorkspaceMetric(
            label: tr('الفوترة'),
            value: tr('مترابطة'),
            icon: Icons.request_quote_outlined,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppPillTabBar(
              tabs: <AppPillTab>[
                AppPillTab(tr('أوامر البيع'), Icons.edit_note_rounded),
                AppPillTab(tr('الفواتير القديمة'), Icons.point_of_sale_rounded),
              ],
            ),
            const SizedBox(height: 10),
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
