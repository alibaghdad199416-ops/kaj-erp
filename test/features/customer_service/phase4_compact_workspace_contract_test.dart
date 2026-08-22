import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customer service shell uses compact responsive workspace chrome', () {
    final source = File(
      'lib/features/customer_service/pages/customer_service_page.dart',
    ).readAsStringSync();

    expect(source, contains('AppWorkspaceChromeScope.hasTopBarOf(context)'));
    expect(source, contains('constraints.maxWidth < 1080'));
    expect(source, contains('constraints.maxWidth < 980'));
    expect(source, contains('visualDensity: VisualDensity.compact'));
    expect(source, contains('ListView.separated('));
    expect(source, contains('padding: const EdgeInsets.only(top: 48)'));
  });

  test('opportunity cards stack on narrow widths and retain all actions', () {
    final source = File(
      'lib/features/customer_service/widgets/opportunity_card.dart',
    ).readAsStringSync();

    expect(source, contains('constraints.maxWidth < 920'));
    expect(source, contains('radius: 19'));
    expect(source, contains('EdgeInsets.fromLTRB(10, 8, 9, 8)'));
    expect(source, contains('BoxConstraints.tightFor(width: 34, height: 34)'));
    expect(source, contains('onPressed: onLost'));
    expect(source, contains('onPressed: onWon'));
    expect(source, contains('onPressed: () => _openMaintenance(context)'));
    expect(source, contains('onPressed: onEdit'));
    expect(source, contains('onPressed: onDelete'));
  });
}
