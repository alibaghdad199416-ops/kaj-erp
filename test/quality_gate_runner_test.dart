import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/testing/quality_gate.dart';

void main() {
  test('quality gates report every pass and failure', () async {
    final results = await const QualityGateRunner().run({
      'passing': () {},
      'failing': () => throw StateError('blocked'),
    });

    expect(results, hasLength(2));
    expect(results.first.passed, isTrue);
    expect(results.last.passed, isFalse);
    expect(results.last.details, contains('blocked'));
  });
}
