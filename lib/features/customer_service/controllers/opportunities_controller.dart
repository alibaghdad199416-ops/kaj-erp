import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/events/app_data_change_bus.dart';
import 'package:quality_line_erp/features/customer_service/models/opportunity_model.dart';
import 'package:quality_line_erp/features/customer_service/repositories/opportunity_repository.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';

class OpportunitiesController extends ChangeNotifier {
  OpportunitiesController({OpportunityRepository? repository})
    : _repository = repository ?? OpportunityRepository();

  final OpportunityRepository _repository;
  List<OpportunityModel> _items = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<OpportunityModel> get opportunities => List.unmodifiable(_items);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get pendingCount =>
      _items.where((e) => e.status == OpportunityStatus.pending).length;
  int get wonCount =>
      _items.where((e) => e.status == OpportunityStatus.won).length;
  int get lostCount =>
      _items.where((e) => e.status == OpportunityStatus.lost).length;
  Map<String, double> get pipelineValueByCurrency {
    final totals = <String, double>{};
    for (final opportunity in _items.where(
      (item) => item.status == OpportunityStatus.pending,
    )) {
      final currency = opportunity.currency.trim().toUpperCase();
      if (currency.isEmpty) continue;
      totals.update(
        currency,
        (value) => value + opportunity.expectedValue,
        ifAbsent: () => opportunity.expectedValue,
      );
    }
    return Map<String, double>.unmodifiable(totals);
  }

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
    // Read back the canonical server projection after every edit. PostgreSQL
    // owns the business reference and sales-workflow reconciliation, while
    // field permissions can also preserve server-owned values.
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

  Future<void> saveAsLost(OpportunityModel item, {required bool isNew}) async {
    if (isNew) {
      await _repository.add(item);
    } else {
      await _repository.update(item);
    }
    final saved = (await _repository.getOpportunities())
        .where((value) => value.id == item.id)
        .firstOrNull;
    if (saved == null) {
      throw StateError('Opportunity read-back missing before mark_lost.');
    }
    await _repository.markLost(saved);
    await loadOpportunities();
  }
}
