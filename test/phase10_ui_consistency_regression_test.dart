import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'shared workspace primitives keep full-height and horizontal behavior',
    () {
      final entityPage = File(
        'lib/core/widgets/app_entity_page.dart',
      ).readAsStringSync();
      final horizontalStrip = File(
        'lib/core/widgets/app_horizontal_strip.dart',
      ).readAsStringSync();
      final pillTabs = File(
        'lib/core/widgets/app_pill_tab_bar.dart',
      ).readAsStringSync();

      expect(entityPage, contains('fillAvailableHeight'));
      expect(entityPage, contains('Expanded(child: bodyPanel)'));
      expect(entityPage, isNot(contains('FlexFit.loose')));
      expect(horizontalStrip, contains('LayoutBuilder('));
      expect(horizontalStrip, contains('scrollDirection: Axis.horizontal'));
      expect(pillTabs, contains('isScrollable: true'));
      expect(pillTabs, contains('tabAlignment: TabAlignment.start'));
    },
  );

  test(
    'accounting and settings remain one full active workspace with horizontal selectors',
    () {
      final accounting = File(
        'lib/features/accounting/pages/accounting_center_page.dart',
      ).readAsStringSync();
      final settingsHub = File(
        'lib/features/settings/pages/settings_hub_page.dart',
      ).readAsStringSync();
      final settings = File(
        'lib/features/settings/pages/settings_page.dart',
      ).readAsStringSync();

      expect(
        accounting,
        contains("ValueKey('accounting-section-horizontal-nav')"),
      );
      expect(accounting, contains('scrollDirection: Axis.horizontal'));
      expect(
        accounting,
        contains("ValueKey('accounting-active-section-full-viewport')"),
      );
      expect(
        settingsHub,
        contains("ValueKey('settings-primary-horizontal-sections')"),
      );
      expect(
        settingsHub,
        contains("ValueKey('settings-active-section-full-viewport')"),
      );
      expect(settingsHub, contains('fillAvailableHeight: true'));
      expect(
        settings,
        contains("ValueKey('system-model-horizontal-sections')"),
      );
      expect(
        settings,
        contains("ValueKey('system-model-active-section-viewport')"),
      );
    },
  );

  test(
    'dashboard keeps compact empty trend and suppresses mixed-currency chart',
    () {
      final dashboard = File(
        'lib/features/dashboard/pages/dashboard_page.dart',
      ).readAsStringSync();

      expect(dashboard, contains('mixedCurrencies: _hasMultipleCurrencies'));
      expect(dashboard, contains('The combined chart is hidden'));
      expect(
        dashboard,
        contains("ValueKey('dashboard-mixed-currency-trend-suppressed')"),
      );
      expect(dashboard, contains('if (points.isEmpty) ...['));
      expect(dashboard, contains('compact: true'));
      expect(dashboard, isNot(contains('height: points.isEmpty ?')));
    },
  );

  test(
    'phase 10 removes oversized legacy empty-state padding from operational workspaces',
    () {
      final cashbox = File(
        'lib/features/accounting/cashbox/pages/cashbox_page.dart',
      ).readAsStringSync();
      final search = File(
        'lib/features/global_search/pages/global_search_page.dart',
      ).readAsStringSync();
      final periods = File(
        'lib/features/settings/operational_periods/pages/operational_periods_page.dart',
      ).readAsStringSync();
      final users = File(
        'lib/features/settings/access/pages/users_page.dart',
      ).readAsStringSync();

      expect(cashbox, isNot(contains('EdgeInsets.all(60)')));
      expect(search, isNot(contains('vertical: 56')));
      expect(periods, isNot(contains('EdgeInsets.all(40)')));
      expect(users, isNot(contains('EdgeInsets.all(50)')));
    },
  );

  test(
    'numeric form validation remains bilingual in inventory and cashbox',
    () {
      final inventory = File(
        'lib/features/inventory/pages/add_inventory_page.dart',
      ).readAsStringSync();
      final cashbox = File(
        'lib/features/accounting/cashbox/pages/cashbox_page.dart',
      ).readAsStringSync();

      expect(inventory, contains("'Enter a valid numeric value'"));
      expect(inventory, contains("'The value cannot be negative'"));
      expect(cashbox, contains("'Enter a value greater than zero'"));
      expect(cashbox, contains("return ar ? 'تحويل مصرفي' : 'Bank transfer';"));
    },
  );
}
