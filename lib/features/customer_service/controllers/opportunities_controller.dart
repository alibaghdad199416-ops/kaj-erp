import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/filtering/unified_filter_engine.dart';
import 'package:quality_line_erp/core/filtering/unified_query.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/features/sales/models/sale_model.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import 'package:quality_line_erp/features/customer_service/models/opportunity_model.dart';
import 'package:quality_line_erp/features/customer_service/repositories/opportunity_repository.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';

class OpportunitiesController extends ChangeNotifier {
  final OpportunityRepository _repository = OpportunityRepository();
  final UnifiedQueryController query = UnifiedQueryController();
  List<OpportunityModel> _items = [];
  bool _isLoading = false;
  String? _errorMessage;

  OpportunitiesController() {
    query.addListener(_onQueryChanged);
  }

  List<OpportunityModel> get opportunities => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  List<OpportunityModel> get visibleOpportunities => UnifiedFilterEngine.apply(
    _items,
    criteria: UnifiedFilterCriteria(
      searchText: query.state.search,
      statuses: {
        for (final token in query.state.filters)
          if (token.key == 'status') token.value.toString(),
      },
    ),
    adapter: UnifiedFilterAdapter<OpportunityModel>(
      searchableText: (item) => <Object?>[
        item.opportunityNumber,
        item.title,
        item.customerName,
        item.customerPhone,
        item.assignedUserName,
        item.source,
        item.invoiceNumber,
        item.carName,
        item.salesOrderStatus,
        item.deliveryNumber,
        item.invoiceStatus,
        item.paymentStatus,
      ],
      status: (item) => item.status.name,
      partnerId: (item) => item.customerId,
      userId: (item) => item.assignedUserId,
      currency: (item) => item.currency,
      date: (item) => item.createdAt,
    ),
    sorts: query.state.sorts
        .map((rule) {
          final key = rule.field;
          Comparable<dynamic> value(OpportunityModel item) {
            switch (key) {
              case 'opportunityNumber':
                return item.opportunityNumber;
              case 'customerName':
                return item.customerName;
              case 'expectedValue':
                return item.expectedValue;
              case 'status':
                return item.status.name;
              case 'followUpDate':
                return item.followUpDate ??
                    DateTime.fromMillisecondsSinceEpoch(0);
              case 'createdAt':
              default:
                return item.createdAt;
            }
          }

          return UnifiedSortCriterion<OpportunityModel>(
            key: key,
            value: value,
            direction: rule.descending
                ? UnifiedSortDirection.descending
                : UnifiedSortDirection.ascending,
          );
        })
        .toList(growable: false),
  );

  void _onQueryChanged() => notifyListeners();

  Future<void> loadOpportunities() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _items = await _repository.getOpportunities();
    } catch (e) {
      AppLogger.debug('OpportunitiesController.load failed: $e');
      _errorMessage = userFacingError(
        e,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر تحميل فرص العملاء.',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> add(OpportunityModel item) async {
    await _repository.add(item);
    await loadOpportunities();
    AppDataChangeBus.instance.publish(
      'opportunities',
      operation: 'insert',
      entityId: item.id,
    );
  }

  Future<void> update(OpportunityModel item) async {
    await _repository.update(item);
    await loadOpportunities();
    AppDataChangeBus.instance.publish(
      'opportunities',
      operation: 'update',
      entityId: item.id,
    );
  }

  Future<void> delete(OpportunityModel item) async {
    await _repository.delete(item);
    _items = _items
        .where((value) => value.id != item.id)
        .toList(growable: false);
    notifyListeners();
    AppDataChangeBus.instance.publish(
      'opportunities',
      operation: 'delete',
      entityId: item.id,
    );
  }

  Future<void> markLost(OpportunityModel item) async {
    await _repository.markLost(item);
    await loadOpportunities();
  }

  Future<SaleModel> markWonAndCreateInvoice({
    required OpportunityModel opportunity,
    required String carId,
    required String carName,
    required double salePrice,
    required double paidAmount,
    required String paymentMethod,
  }) async {
    final sale = await _repository.markWonAndCreateInvoice(
      opportunity: opportunity,
      carId: carId,
      carName: carName,
      salePrice: salePrice,
      paidAmount: paidAmount,
      paymentMethod: paymentMethod,
    );
    await loadOpportunities();
    return sale;
  }

  @override
  void dispose() {
    query.removeListener(_onQueryChanged);
    query.dispose();
    super.dispose();
  }
}
