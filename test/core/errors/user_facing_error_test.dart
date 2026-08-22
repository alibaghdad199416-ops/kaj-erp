import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/cloud/workflow_operation_exception.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';

void main() {
  test('maps wrapped car delivery failure without leaking RPC diagnostics', () {
    const error = WorkflowOperationException(
      operation: 'erp_r49_create_sales_delivery_multi',
      message: 'car_not_available',
      code: 'P0001',
      details: 'vehicle 5fb4c9d2-93c5-4efa-9900-c6021ffadbfd',
    );

    final message = userFacingError(error, isArabic: false);

    expect(message, contains('vehicle is not available'));
    expect(message, isNot(contains('erp_r49')));
    expect(message, isNot(contains('5fb4c9d2')));
  });

  test('maps commercial over-fulfilment to an actionable message', () {
    const error = WorkflowOperationException(
      operation: 'delivery',
      message: 'commercial_over_fulfillment',
    );

    expect(
      userFacingError(error, isArabic: false),
      contains('exceeds the remaining sales-order quantity'),
    );
  });

  test('maps car warehouse mismatch without exposing P0001', () {
    const error = WorkflowOperationException(
      operation: 'invoice',
      message: 'car_warehouse_mismatch',
      code: 'P0001',
    );

    final message = userFacingError(error, isArabic: false);
    expect(message, contains('different warehouse'));
    expect(message, isNot(contains('P0001')));
  });

  test('maps missing approved delivery to the required lifecycle stage', () {
    const error = WorkflowOperationException(
      operation: 'invoice',
      message: 'approved_sales_delivery_required',
      code: 'P0001',
    );

    expect(
      userFacingError(error, isArabic: false),
      contains('approved delivery is required'),
    );
  });

  test('keeps purchase receipt errors distinct from sales delivery', () {
    const error = WorkflowOperationException(
      operation: 'purchase invoice',
      message: 'receipt_not_approved',
      code: 'P0001',
    );
    final message = userFacingError(error, isArabic: false);
    expect(message, contains('approved receipt'));
    expect(message, isNot(contains('delivery')));
  });

  test('maps remaining P0 business conditions without raw diagnostics', () {
    const cases = <String, String>{
      'over_receipt': 'remaining purchase-order quantity',
      'invoice_already_posted': 'already posted',
      'account_binding_missing': 'accounting binding',
      'payment_allocation_invalid': 'payment allocation',
      'invalid_transition': 'current state',
    };
    for (final entry in cases.entries) {
      final message = userFacingError(
        WorkflowOperationException(
          operation: 'erp_raw_rpc',
          message: entry.key,
          code: 'P0001',
        ),
        isArabic: false,
      );
      expect(message, contains(entry.value));
      expect(message, isNot(contains('P0001')));
      expect(message, isNot(contains('erp_raw_rpc')));
    }
  });
}
