import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  expect(startIndex, isNonNegative, reason: 'Missing start marker: $start');
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(endIndex, isNonNegative, reason: 'Missing end marker: $end');
  return source.substring(startIndex, endIndex);
}

void main() {
  test('purchase receipt UI creates a draft without implicit approval', () {
    final source = File(
      'lib/features/purchases/pages/purchase_workflow_page.dart',
    ).readAsStringSync();
    final receiptAction = _between(
      source,
      'Future<void> _receipt(String id) async {',
      'Future<void> _addPayment(',
    );

    expect(receiptAction, contains('_repository.createReceiptDraftMulti('));
    expect(receiptAction, isNot(contains('approveReceipt(')));
  });

  test('purchase repository keeps draft creation and approval separate', () {
    final source = File(
      'lib/features/purchases/repositories/purchase_workflow_repository.dart',
    ).readAsStringSync();
    final createDraft = _between(
      source,
      'Future<String> createReceiptDraftMulti({',
      'Future<List<Map<String, Object?>>> listOrders()',
    );

    expect(createDraft, contains("'erp_r49_create_purchase_receipt_multi'"));
    expect(createDraft, isNot(contains('approveReceipt(')));
    expect(
      source,
      contains(
        "Future<void> approveReceipt(String receiptId) =>\n      _void('erp_phase2_approve_purchase_receipt'",
      ),
    );
  });

  test('database receipt creation is draft-only and approval owns inventory', () {
    final source = File(
      'supabase/migrations/20260728000700_multi_warehouse_commercial_documents.sql',
    ).readAsStringSync();
    final createDraft = _between(
      source,
      'create or replace function public.erp_create_cloud_purchase_receipt_multi(',
      '-- Backward-compatible one-warehouse wrappers.',
    );
    final approve = _between(
      source,
      'create or replace function public.erp_approve_cloud_purchase_receipt(',
      'create or replace function public.erp_approve_cloud_sales_delivery(',
    );

    expect(
      createDraft,
      contains("'create_receipt',null,'draft'"),
      reason: 'Receipt creation must audit a draft transition only.',
    );
    expect(createDraft, isNot(contains('erp_inventory_insert_movement(')));
    expect(createDraft, isNot(contains("set status='approved'")));
    expect(createDraft, isNot(contains('inventoryPostedAt')));

    expect(approve, contains('erp_inventory_insert_movement('));
    expect(approve, contains("set status='approved'"));
    expect(approve, contains("'inventoryPostedAt'"));
  });
}
