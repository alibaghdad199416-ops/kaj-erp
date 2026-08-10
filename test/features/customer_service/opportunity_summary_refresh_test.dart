import 'package:flutter_test/flutter_test.dart';

import 'package:quality_line_erp/features/customer_service/controllers/opportunities_controller.dart';
import 'package:quality_line_erp/features/customer_service/models/opportunity_model.dart';
import 'package:quality_line_erp/features/customer_service/repositories/opportunity_repository.dart';

OpportunityModel _opportunity({
  String stage = 'proposal',
  String? salesOrderStatus,
  String? deliveryStatus,
  String? invoiceStatus,
  String? paymentStatus,
  double paid = 0,
  double remaining = 300,
}) => OpportunityModel(
  id: 'opportunity-r49',
  opportunityNumber: 'OPP0001',
  customerId: 'customer-r49',
  customerName: 'R49 Customer',
  customerPhone: '07700000000',
  title: 'R49 lifecycle',
  source: 'runtime',
  expectedValue: 300,
  currency: 'USD',
  stage: stage,
  probability: stage == 'closed' ? 100 : 60,
  status: OpportunityStatus.pending,
  saleId: 'sales-order-r49',
  salesOrderStatus: salesOrderStatus,
  deliveryNumber: 'DEL0001',
  deliveryStatus: deliveryStatus,
  invoiceNumber: 'INV0001',
  invoiceStatus: invoiceStatus,
  paymentStatus: paymentStatus,
  paidAmount: paid,
  remainingAmount: remaining,
  assignedUserId: 'user-r49',
  assignedUserName: 'R49 Admin',
  createdByUserId: 'user-r49',
  createdByUserName: 'R49 Admin',
  createdAt: DateTime.utc(2026, 8, 10),
);

class _CanonicalReadBackRepository extends OpportunityRepository {
  _CanonicalReadBackRepository(this.current);

  OpportunityModel current;
  int reads = 0;

  @override
  Future<List<OpportunityModel>> getOpportunities() async {
    reads += 1;
    return [current];
  }

  @override
  Future<void> update(OpportunityModel opportunity) async {
    current = _opportunity(
      stage: 'closed',
      salesOrderStatus: 'approved',
      deliveryStatus: 'approved',
      invoiceStatus: 'approved',
      paymentStatus: 'paid',
      paid: 300,
      remaining: 0,
    );
  }
}

void main() {
  test(
    'successful mutation replaces every stale opportunity summary field',
    () async {
      final stale = _opportunity(
        salesOrderStatus: 'draft',
        deliveryStatus: 'pending',
        invoiceStatus: 'pending',
        paymentStatus: 'unpaid',
      );
      final repository = _CanonicalReadBackRepository(stale);
      final controller = OpportunitiesController(repository: repository);

      await controller.loadOpportunities();
      expect(controller.opportunities.single.paymentStatus, 'unpaid');

      await controller.update(stale);

      final refreshed = controller.opportunities.single;
      expect(repository.reads, 2);
      expect(refreshed.id, stale.id);
      expect(refreshed.saleId, 'sales-order-r49');
      expect(refreshed.customerId, 'customer-r49');
      expect(refreshed.stage, 'closed');
      expect(refreshed.salesOrderStatus, 'approved');
      expect(refreshed.deliveryStatus, 'approved');
      expect(refreshed.invoiceStatus, 'approved');
      expect(refreshed.paymentStatus, 'paid');
      expect(refreshed.paidAmount, 300);
      expect(refreshed.remainingAmount, 0);
      expect(refreshed.expectedValue, 300);
      expect(refreshed.currency, 'USD');
    },
  );
}
