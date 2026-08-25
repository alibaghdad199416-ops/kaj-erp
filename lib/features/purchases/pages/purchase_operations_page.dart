import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_lazy_tab_view.dart';
import 'package:quality_line_erp/core/widgets/app_pill_tab_bar.dart';
import 'package:quality_line_erp/design_system/kaj_commercial_stage6_components.dart';
import 'package:quality_line_erp/features/purchases/pages/purchase_workflow_page.dart';
import 'purchases_page.dart';

class PurchaseOperationsPage extends StatelessWidget {
  const PurchaseOperationsPage({super.key, this.initialIndex = 0});
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
        title: tr('مركز المشتريات'),
        subtitle: tr(
          'أوامر الشراء والاستلام والفوترة والدفع والطباعة ضمن مسار تجاري موحد.',
        ),
        icon: Icons.shopping_cart_checkout_rounded,
        metrics: <KajCommercialWorkspaceMetric>[
          KajCommercialWorkspaceMetric(
            label: tr('المسار'),
            value: tr('شراء'),
            icon: Icons.shopping_bag_outlined,
          ),
          KajCommercialWorkspaceMetric(
            label: tr('الاستلام'),
            value: tr('مخزني'),
            icon: Icons.move_to_inbox_outlined,
          ),
          KajCommercialWorkspaceMetric(
            label: tr('الدفع'),
            value: tr('مترابط'),
            icon: Icons.account_balance_wallet_outlined,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppPillTabBar(
              tabs: <AppPillTab>[
                AppPillTab(tr('أوامر الشراء'), Icons.edit_note_rounded),
                AppPillTab(tr('الفواتير القديمة'), Icons.receipt_long_rounded),
              ],
            ),
            const SizedBox(height: 10),
            const Expanded(
              child: AppLazyTabView(
                children: <Widget>[PurchaseWorkflowPage(), PurchasesPage()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
