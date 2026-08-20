import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String path) => File(
  path,
).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');

void main() {
  test(
    'commercial shell yields duplicate identity chrome to the module top bar',
    () {
      final source = _source(
        'lib/design_system/kaj_commercial_stage6_components.dart',
      );

      expect(source, contains('AppWorkspaceChromeScope.hasTopBarOf(context)'));
      expect(source, contains('final shellOwnsIdentity'));
      expect(source, contains('Expanded(child: child)'));
    },
  );

  test(
    'sales and purchase workflow controls remain horizontal without forced scrolling',
    () {
      final source = _source(
        'lib/core/widgets/commercial_workflow_filter_bar.dart',
      );

      expect(source, contains('constraints.maxWidth < 980'));
      expect(source, contains('Expanded(flex: 5, child: search)'));
      expect(source, contains('Expanded(\n                flex: 7'));
      expect(
        source,
        contains('materialTapTargetSize: MaterialTapTargetSize.shrinkWrap'),
      );
      expect(source, isNot(contains('AppHorizontalStrip')));
    },
  );

  test(
    'commercial order cards become dense desktop rows and stack safely when narrow',
    () {
      final source = _source(
        'lib/core/widgets/commercial_workflow_order_card.dart',
      );

      expect(source, contains('constraints.maxWidth < 980'));
      expect(source, contains('SizedBox(width: 270, child: header)'));
      expect(source, contains('BoxConstraints(maxWidth: 210)'));
      expect(source, contains('BoxConstraints(minWidth: 108, maxWidth: 178)'));
      expect(source, contains('padding: const EdgeInsets.only(bottom: 7)'));
    },
  );

  test(
    'legacy sales and purchase invoice tabs use the compact archive toolbar',
    () {
      final sales = _source('lib/features/sales/pages/sales_page.dart');
      final purchases = _source(
        'lib/features/purchases/pages/purchases_page.dart',
      );

      for (final source in <String>[sales, purchases]) {
        expect(source, contains('LegacyCommercialArchiveToolbar('));
        expect(source, contains('padding: const EdgeInsets.only(top: 48)'));
      }
      expect(sales, isNot(contains('SalesStatistics(')));
    },
  );

  test(
    'legacy commercial cards retain all data and actions at tighter density',
    () {
      final saleCard = _source('lib/features/sales/widgets/sale_card.dart');
      final purchaseCard = _source(
        'lib/features/purchases/widgets/purchase_card.dart',
      );

      for (final source in <String>[saleCard, purchaseCard]) {
        expect(source, contains('margin: const EdgeInsets.only(bottom: 7)'));
        expect(
          source,
          contains('BoxConstraints(minWidth: 108, maxWidth: 200)'),
        );
        expect(source, contains("AppTranslation.translate('طباعة')"));
        expect(source, contains("AppTranslation.translate('حذف')"));
      }
    },
  );
}
