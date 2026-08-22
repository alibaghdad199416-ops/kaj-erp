import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/widgets/app_lazy_tab_view.dart';
import 'package:quality_line_erp/core/widgets/app_pill_tab_bar.dart';
import 'package:quality_line_erp/design_system/kaj_commercial_stage6_components.dart';
import 'package:quality_line_erp/features/purchases/pages/purchase_workflow_page.dart';
import 'purchases_page.dart';

class PurchaseOperationsPage extends StatelessWidget {
  const PurchaseOperationsPage({
    super.key,
    this.initialIndex = 0,
    this.initialOrderId,
  });
  final int initialIndex;
  final String? initialOrderId;

  @override
  Widget build(BuildContext context) {
    final ar = context.l10n.isArabic;
    String t(String arabic, String english) => ar ? arabic : english;

    return DefaultTabController(
      initialIndex: initialIndex.clamp(0, 1).toInt(),
      length: 2,
      child: KajCommercialWorkspace(
        title: t('مركز المشتريات', 'Purchase center'),
        subtitle: t(
          'أوامر الشراء والاستلام والفوترة والدفع والطباعة ضمن مسار تجاري موحد.',
          'Purchase orders, warehouse receiving, invoicing, payment and printing in one unified commercial workflow.',
        ),
        icon: Icons.shopping_cart_checkout_rounded,
        metrics: <KajCommercialWorkspaceMetric>[
          KajCommercialWorkspaceMetric(
            label: t('المسار', 'Workflow'),
            value: t('شراء', 'Purchasing'),
            icon: Icons.shopping_bag_outlined,
          ),
          KajCommercialWorkspaceMetric(
            label: t('الاستلام', 'Receiving'),
            value: t('مخزني', 'Warehouse'),
            icon: Icons.move_to_inbox_outlined,
          ),
          KajCommercialWorkspaceMetric(
            label: t('الدفع', 'Payment'),
            value: t('مترابط', 'Linked'),
            icon: Icons.account_balance_wallet_outlined,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppPillTabBar(
              tabs: <AppPillTab>[
                AppPillTab(
                  t('أوامر الشراء', 'Purchase orders'),
                  Icons.edit_note_rounded,
                ),
                AppPillTab(
                  t('الفواتير القديمة', 'Legacy invoices'),
                  Icons.receipt_long_rounded,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: AppLazyTabView(
                children: <Widget>[
                  PurchaseWorkflowPage(initialOrderId: initialOrderId),
                  const PurchasesPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
