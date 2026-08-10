import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:quality_line_erp/features/dashboard/data/dashboard_repository.dart';
import 'package:quality_line_erp/features/dashboard/models/dashboard_model.dart';

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
  String? _errorMessage;

  DashboardModel get dashboard => _dashboard;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  DateTime get lastGeneratedAt => _dashboard.generatedAt;
  int get appliedRevision => _appliedRevision;
  bool get hasLoaded => _loadedAt != null;

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
    final active = _loadInFlight;
    if (active != null) return active;

    final future = _loadNow();
    _loadInFlight = future;
    return future.whenComplete(() {
      if (identical(_loadInFlight, future)) _loadInFlight = null;
    });
  }

  Future<void> _loadNow() async {
    if (_disposed) return;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _dashboard = await _repository.getDashboardData();
      _loadedAt = DateTime.now();
      _appliedRevision++;
    } catch (error) {
      AppLogger.debug('DashboardController.load failed: $error');
      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر تحميل لوحة التحكم.',
      );
    } finally {
      _isLoading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
