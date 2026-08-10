import 'package:quality_line_erp/core/cloud/cloud_feature_command.dart';
import 'package:quality_line_erp/features/sales/models/sale_model.dart';
import 'package:quality_line_erp/features/customer_service/models/opportunity_model.dart';

class OpportunityRepository {
  final CloudFeatureCommand _cloud = CloudFeatureCommand.instance;

  Future<List<OpportunityModel>> getOpportunities() async => (await _cloud.list(
    'opportunity',
    'list',
  )).map(OpportunityModel.fromMap).toList(growable: false);

  Future<void> add(OpportunityModel opportunity) => _cloud.call(
    'opportunity',
    'save',
    payload: {'record': opportunity.toMap(), 'create_only': true},
  );

  Future<void> update(OpportunityModel opportunity) => _cloud.call(
    'opportunity',
    'save',
    payload: {
      'record': opportunity.toMap(),
      'create_only': false,
      'expected_updated_at': opportunity.updatedAt?.toUtc().toIso8601String(),
    },
  );

  Future<void> delete(OpportunityModel opportunity) => _cloud.call(
    'opportunity',
    'delete',
    payload: {
      'id': opportunity.id,
      'expected_updated_at': opportunity.updatedAt?.toUtc().toIso8601String(),
    },
  );

  Future<SaleModel> markWonAndCreateInvoice({
    required OpportunityModel opportunity,
    required String carId,
    required String carName,
    required double salePrice,
    required double paidAmount,
    required String paymentMethod,
  }) async {
    final row = await _cloud.map(
      'opportunity',
      'mark_won',
      payload: {
        'opportunity_id': opportunity.id,
        'expected_updated_at': opportunity.updatedAt?.toUtc().toIso8601String(),
        'car_id': carId,
        'car_name': carName,
        'sale_price': salePrice,
        'paid_amount': paidAmount,
        'payment_method': paymentMethod,
      },
    );
    return SaleModel.fromMap(row);
  }

  Future<void> markLost(OpportunityModel opportunity) => _cloud.call(
    'opportunity',
    'mark_lost',
    payload: {
      'id': opportunity.id,
      'expected_updated_at': opportunity.updatedAt?.toUtc().toIso8601String(),
    },
  );
}
