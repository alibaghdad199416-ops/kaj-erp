import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:quality_line_erp/features/dashboard/data/dashboard_repository.dart';
import 'package:quality_line_erp/features/dashboard/models/dashboard_model.dart';

enum DashboardPeriod { allTime, today, currentMonth, custom }

class DashboardController extends ChangeNotifier {
  DashboardController({DashboardRepository? repository})
    : _repository = repository ?? DashboardRepository();

  final DashboardRepository _repository;
  DashboardModel _dashboard = DashboardModel.empty();
  Future<void>? _loadInFlight;
  DateTime? _loadedAt;
  bool _isLoading = false;
  bool _disposed = false;
  int _appliedRevision = 0;
  int _requestRevision = 0;
  String? _errorMessage;
  DashboardPeriod _period = DashboardPeriod.allTime;
  DateTime? _fromDate;
  DateTime _toDate = DateTime.now();

  DashboardModel get dashboard => _dashboard;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime get lastGeneratedAt => _dashboard.generatedAt;
  int get appliedRevision => _appliedRevision;
  bool get hasLoaded => _loadedAt != null;
  DashboardPeriod get period => _period;
  DateTime? get fromDate => _fromDate;
  DateTime get toDate => _toDate;

  Future<void> refresh() => loadDashboard(force: true);

  Future<void> waitForIdle() => _loadInFlight ?? Future<void>.value();

  Future<void> loadDashboard({bool force = false}) {
    if (_disposed) return Future<void>.value();
    final loadedAt = _loadedAt;
    if (!force &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < const Duration(seconds: 30)) {
      return Future<void>.value();
    }
    final revision = ++_requestRevision;
    final fromDate = _fromDate;
    final toDate = _toDate;
    final future = _loadNow(revision, fromDate, toDate);
    _loadInFlight = future;
    return future.whenComplete(() {
      if (identical(_loadInFlight, future)) _loadInFlight = null;
    });
  }

  Future<void> setPeriod(DashboardPeriod value) async {
    if (_disposed) return;
    final today = DateTime.now();
    _period = value;
    _toDate = DateTime(today.year, today.month, today.day);
    _fromDate = switch (value) {
      DashboardPeriod.allTime => null,
      DashboardPeriod.today => _toDate,
      DashboardPeriod.currentMonth => DateTime(today.year, today.month),
      DashboardPeriod.custom => _fromDate,
    };
    notifyListeners();
    await loadDashboard(force: true);
  }

  Future<void> setCustomRange(DateTime fromDate, DateTime toDate) async {
    final from = DateTime(fromDate.year, fromDate.month, fromDate.day);
    final to = DateTime(toDate.year, toDate.month, toDate.day);
    if (from.isAfter(to)) throw ArgumentError('invalid_dashboard_date_range');
    _period = DashboardPeriod.custom;
    _fromDate = from;
    _toDate = to;
    notifyListeners();
    await loadDashboard(force: true);
  }

  Future<void> _loadNow(
    int revision,
    DateTime? fromDate,
    DateTime toDate,
  ) async {
    if (_disposed) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final next = await _repository.getDashboardData(
        fromDate: fromDate,
        toDate: toDate,
      );
      if (_disposed || revision != _requestRevision) return;
      _dashboard = next;
      _loadedAt = DateTime.now();
      _appliedRevision++;
    } catch (error) {
      AppLogger.debug('DashboardController.load failed: $error');
      if (revision != _requestRevision) return;
      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر تحميل لوحة التحكم.',
      );
    } finally {
      if (revision == _requestRevision) {
        _isLoading = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
