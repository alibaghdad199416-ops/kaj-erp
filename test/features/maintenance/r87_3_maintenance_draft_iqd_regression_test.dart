import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/utils/thousands_input_formatter.dart';

void main() {
  test('IQD-sized formatted amounts remain parseable', () {
    expect(ThousandsInputFormatter.parse('2,500,000'), 2500000);
    expect(ThousandsInputFormatter.parse('12,345,678.50'), 12345678.50);
  });

  test(
    'maintenance form uses thousands-aware parsing for persisted values',
    () {
      final source = File(
        'lib/features/maintenance/pages/add_maintenance_order_page.dart',
      ).readAsStringSync();

      expect(
        source,
        contains('salePrice: ThousandsInputFormatter.parse(_price.text) ?? 0'),
      );
      expect(
        source,
        contains(
          'unitPrice: ThousandsInputFormatter.parse(line.unitPrice.text) ?? 0',
        ),
      );
      expect(source, isNot(contains("double.tryParse(_price.text.trim())")));
    },
  );

  test(
    'order drafts render from core persisted data before reconciliation',
    () {
      final source = File(
        'lib/features/maintenance/pages/maintenance_order_details_dialog.dart',
      ).readAsStringSync();

      expect(source, contains('if (_isOrderDraft) {'));
      expect(source, contains('unawaited(_loadDraftCoreLines());'));
      expect(
        source,
        contains('final lines = await _repository.getOrderLines(_order.id);'),
      );
      expect(
        source,
        contains('_isOrderDraft ? _loadDraftCoreLines() : _loadDetails()'),
      );
    },
  );
}
