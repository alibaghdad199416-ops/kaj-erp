import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:flutter/material.dart';

import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/features/settings/reports/data/reports_repository.dart';
import 'package:quality_line_erp/features/settings/reports/models/report_model.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';

class ReportsController extends ChangeNotifier {
  ReportsController({ReportsRepository? repository})
    : _repository = repository ?? ReportsRepository();

  final ReportsRepository _repository;
  ReportModel _report = ReportModel.empty();
  bool _isLoading = false;
  bool _hasLoaded = false;
  Future<void>? _loadInFlight;
  String? _errorMessage;
  DateTime? _startDate;
  DateTime? _endDate;

  ReportModel get report => _report;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasLoaded => _hasLoaded;
  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;

  Future<void> loadReports({
    DateTime? startDate,
    DateTime? endDate,
    bool force = false,
  }) {
    final sameRange = _startDate == startDate && _endDate == endDate;
    if (!force && _hasLoaded && sameRange) return Future<void>.value();
    final active = _loadInFlight;
    if (active != null) return active;

    final request = _loadReportsNow(startDate: startDate, endDate: endDate);
    _loadInFlight = request;
    return request.whenComplete(() {
      if (identical(_loadInFlight, request)) _loadInFlight = null;
    });
  }

  Future<void> _loadReportsNow({DateTime? startDate, DateTime? endDate}) async {
    _isLoading = true;
    _errorMessage = null;
    _startDate = startDate;
    _endDate = endDate;
    notifyListeners();
    try {
      _report = await _repository.getReportsData(
        startDate: startDate,
        endDate: endDate,
      );
      _hasLoaded = true;
    } catch (error) {
      AppLogger.debug('ReportsController.load failed: $error');
      _errorMessage = userFacingError(
        error,
        isArabic: AppTranslation.isArabic,
        arabicFallback: 'تعذر تحميل التقارير.',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> recordReportEvent({
    required String reportKey,
    required String reportTitle,
    required String outputFormat,
    required String module,
  }) => _repository.recordReportEvent(
    reportKey: reportKey,
    reportTitle: reportTitle,
    outputFormat: outputFormat,
    module: module,
    startDate: _startDate,
    endDate: _endDate,
  );

  Future<void> clearFilter() => loadReports(force: true);
}
