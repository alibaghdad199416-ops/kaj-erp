import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260814150503_r68_governed_bulk_and_financial_family_delete.sql',
  ).readAsStringSync();

  test('Recycle Bin keeps single purge and adds one governed bulk RPC', () {
    final repository = File(
      'lib/features/settings/recycle_bin/repositories/recycle_bin_repository.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/settings/recycle_bin/pages/recycle_bin_page.dart',
    ).readAsStringSync();

    expect(repository, contains("'erp_recycle_bin_purge_by_archive'"));
    expect(repository, contains("'erp_r68_empty_recycle_bin'"));
    expect(page, contains('Empty Recycle Bin'));
    expect(page, contains('تفريغ سلة المهملات'));
    expect(page, contains('_loadGeneration'));
    expect(migration, contains("u.company_id=p_company_id"));
    expect(migration, contains("'skippedCount'"));
  });

  test('notifications keep single delete and clear only recipient states', () {
    final repository = File(
      'lib/features/notifications/repositories/notification_center_repository.dart',
    ).readAsStringSync();
    final page = File(
      'lib/features/notifications/pages/notification_center_page.dart',
    ).readAsStringSync();

    expect(repository, contains("'erp_r66_delete_cloud_notification'"));
    expect(repository, contains("'erp_r68_clear_cloud_notifications'"));
    expect(page, contains('Clear All Notifications'));
    expect(page, contains('مسح جميع الإشعارات'));
    expect(migration, contains('erp_notification_user_states'));
    expect(
      migration,
      isNot(contains('delete from public.erp_enterprise_notifications')),
    );
  });

  test('cashbox and payment-origin journal converge on family deletion', () {
    final accounting = File(
      'supabase/migrations/20260804193000_v731_preserved_payment_reallocation.sql',
    ).readAsStringSync();

    expect(migration, contains('erp_r68_delete_financial_transaction_family'));
    expect(
      migration,
      contains('perform public.erp_r68_delete_financial_transaction_family('),
    );
    expect(accounting, contains('erp_delete_cloud_cash_transaction'));
    expect(migration, contains('payment_linked_to_active_invoice'));
    expect(migration, contains('payment_has_active_allocations'));
    expect(migration, contains('payment_linked_to_active_maintenance_invoice'));
    expect(migration, contains("'transactionFamilyId'"));
    expect(migration, contains("'paymentTransferId'"));
    expect(migration, contains('erp_cash_transfers'));
    expect(migration, contains('erp_journal_lines'));
  });

  test('rollback proof covers four currencies, denial, and idempotency', () {
    final proof = File(
      'supabase/tests/verify_r68_governed_bulk_financial_family.sql',
    ).readAsStringSync();

    expect(proof, contains("(1,'USD','USD')"));
    expect(proof, contains("(2,'IQD','IQD')"));
    expect(proof, contains("(3,'IQD','USD')"));
    expect(proof, contains("(4,'USD','IQD')"));
    expect(proof, contains('payment_has_active_allocations'));
    expect(proof, contains('payment_linked_to_active_invoice'));
    expect(proof, contains("'alreadyDeleted'"));
    expect(proof, contains('rollback;'));
  });
}
