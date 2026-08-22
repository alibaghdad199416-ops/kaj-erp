import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260814160140_r69_financial_family_runtime_convergence.sql',
  ).readAsStringSync();
  final proof = File(
    'supabase/tests/verify_r69_financial_family_runtime_convergence.sql',
  ).readAsStringSync();

  test('cash transfer and cash transaction entry points converge on R69', () {
    expect(migration, contains('erp_r69_delete_financial_transaction_family'));
    expect(
      migration,
      contains('v_result:=public.erp_r69_delete_financial_transaction_family('),
    );
    expect(
      migration,
      contains('perform public.erp_delete_cloud_cash_transfer('),
    );
    expect(migration, contains("lower(coalesce(data->>'referenceType',''))"));
  });

  test('resolver is relational, locks first, and enforces postcondition', () {
    expect(migration, contains("p.value->>'transferId'=v_transfer"));
    expect(migration, contains("c.data->>'paymentTransferId'=v_transfer"));
    expect(migration, contains('for update;'));
    expect(migration, contains('financial_family_incomplete_or_ambiguous'));
    expect(migration, contains('financial_family_postcondition_failed'));
    expect(migration, isNot(contains('transactionDate::date')));
  });

  test(
    'rollback proof matches real legacy topology and both FX directions',
    () {
      expect(proof, contains("(1,'USD','IQD')"));
      expect(proof, contains("(2,'IQD','USD')"));
      expect(proof, contains("'paymentChainVersion','v757'"));
      expect(proof, contains("'paymentTransferId',transfer"));
      expect(
        proof,
        contains("erp_delete_cloud_cash_transfer(c,'r69-transfer-1')"),
      );
      expect(
        proof,
        contains("erp_delete_cloud_accounting_entry(c,'r69-fx-out-journal-2')"),
      );
      expect(proof, contains('payment_has_active_allocations'));
      expect(proof, contains('R69 active family artifact remained'));
      expect(proof, contains('rollback;'));
    },
  );

  test('R67 proof owns its rollback fixtures', () {
    final r67 = File(
      'supabase/tests/verify_r67_cancelled_order_purge.sql',
    ).readAsStringSync();
    expect(r67, contains("'R67-QA-MAINT'"));
    expect(r67, contains("'R67-QA-SALES'"));
    expect(r67, contains("'R67-QA-PURCHASE'"));
    expect(r67, contains('rollback;'));
  });
}
