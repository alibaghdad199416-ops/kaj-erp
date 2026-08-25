import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/features/business_partners/customers/models/customer_model.dart';
import 'package:quality_line_erp/features/settings/operational_periods/models/operational_period.dart';
import 'package:quality_line_erp/features/settings/access/models/audit_log_model.dart';
import 'package:quality_line_erp/features/accounting/models/account_statement_line_model.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_transaction_model.dart';
import 'package:quality_line_erp/features/accounting/models/account_model.dart';
import 'package:quality_line_erp/features/accounting/cashbox/models/cash_account_model.dart';
import 'package:quality_line_erp/features/accounting/models/journal_entry_model.dart';
import 'package:quality_line_erp/features/customer_service/models/opportunity_model.dart';
import 'package:quality_line_erp/features/business_partners/suppliers/models/supplier_model.dart';
import 'package:quality_line_erp/features/inventory/models/inventory_model.dart';
import 'package:quality_line_erp/features/inventory/models/warehouse_model.dart';
import 'package:quality_line_erp/features/settings/models/branch_model.dart';
import 'package:quality_line_erp/features/maintenance/models/maintenance_order_model.dart';

void main() {
  group('authoritative financial read models', () {
    test('missing currency is never silently relabeled as USD or IQD', () {
      final opportunity = OpportunityModel.fromMap(<String, dynamic>{
        'id': 'opp-1',
        'createdAt': '2026-08-10T00:00:00Z',
      });
      final account = AccountModel.fromMap(<String, dynamic>{
        'id': 'acc-1',
        'createdAt': '2026-08-10T00:00:00Z',
      });
      final journal = JournalEntryModel.fromMap(<String, dynamic>{
        'id': 'je-1',
        'entryDate': '2026-08-10T00:00:00Z',
        'createdAt': '2026-08-10T00:00:00Z',
      });

      expect(opportunity.currency, isEmpty);
      expect(account.currency, isEmpty);
      expect(journal.currency, isEmpty);
      expect(journal.status, isEmpty);
    });

    test('missing financial active flags fail closed', () {
      final account = AccountModel.fromMap(<String, dynamic>{
        'id': 'acc-missing-active',
        'createdAt': '2026-08-10T00:00:00Z',
      });
      final cashbox = CashAccountModel.fromMap(<String, dynamic>{
        'id': 'cash-missing-active',
        'createdAt': '2026-08-10T00:00:00Z',
      });

      expect(account.isActive, isFalse);
      expect(cashbox.isActive, isFalse);
    });

    test('missing master-data active flags fail closed', () {
      final supplier = SupplierModel.fromMap(<String, dynamic>{
        'id': 'supplier-missing-active',
        'createdAt': '2026-08-10T00:00:00Z',
      });
      final item = InventoryModel.fromMap(<String, dynamic>{
        'id': 'item-missing-active',
        'date': '2026-08-10T00:00:00Z',
      });
      final warehouse = WarehouseModel.fromMap(<String, dynamic>{
        'id': 'warehouse-missing-active',
      });
      final branch = BranchModel.fromMap(<String, dynamic>{
        'id': 'branch-missing-active',
        'createdAt': '2026-08-10T00:00:00Z',
      });

      expect(supplier.isActive, isFalse);
      expect(item.isActive, isFalse);
      expect(warehouse.isActive, isFalse);
      expect(branch.isActive, isFalse);
    });

    test('required operational timestamps are never synthesized from now', () {
      expect(
        () => OpportunityModel.fromMap(<String, dynamic>{'id': 'opp-no-date'}),
        throwsFormatException,
      );
      expect(
        () => JournalEntryModel.fromMap(<String, dynamic>{'id': 'je-no-date'}),
        throwsFormatException,
      );
      expect(
        () => AccountStatementLineModel.fromMap(<String, dynamic>{
          'entryId': 'line-no-date',
        }),
        throwsFormatException,
      );
      expect(
        () => CashTransactionModel.fromMap(<String, dynamic>{
          'id': 'cash-no-date',
        }),
        throwsFormatException,
      );
    });

    test(
      'missing audit/period state stays unknown instead of false success',
      () {
        final audit = AuditLogModel.fromMap(<String, dynamic>{
          'id': 'audit-1',
          'createdAt': '2026-08-10T00:00:00Z',
        });
        final period = OperationalPeriod.fromMap(<String, dynamic>{
          'id': 'period-1',
          'starts_at': '2026-08-01T00:00:00Z',
          'ends_at': '2026-08-31T23:59:59Z',
        });
        final customer = CustomerModel.fromMap(<String, dynamic>{
          'id': 'customer-no-date',
        });

        expect(audit.outcome, 'unknown');
        expect(period.status, 'unknown');
        expect(period.isOpen, isFalse);
        expect(customer.createdAt, isEmpty);
      },
    );

    test(
      'missing maintenance status is conservative and bool payloads work',
      () {
        final order = MaintenanceOrderModel.fromMap(<String, dynamic>{
          'id': 'm-1',
          'isSoldCar': true,
        });

        expect(order.status, 'draft');
        expect(order.workflowStage, 'order_draft');
        expect(order.isSoldCar, isTrue);
        expect(order.currencyCode, isEmpty);
      },
    );
  });
}
