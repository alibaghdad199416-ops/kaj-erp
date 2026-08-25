import 'package:flutter/foundation.dart';

import 'package:quality_line_erp/core/logging/app_logger.dart';

import 'erp_operational_readiness_service.dart';

/// Non-blocking runtime view of the Supabase capabilities required by each UI
/// module.
///
/// A missing migration should never look like a frozen page. The controller
/// performs one readiness RPC after authentication and lets the shell explain
/// which backend capabilities are unavailable while keeping navigation usable.
class ErpRuntimeCapabilitiesController extends ChangeNotifier {
  ErpRuntimeCapabilitiesController({ErpOperationalReadinessService? service})
    : _providedService = service;

  final ErpOperationalReadinessService? _providedService;
  ErpOperationalReadinessService? _lazyService;
  ErpOperationalReadiness? _readiness;
  Object? _lastError;
  Future<void>? _inFlight;

  ErpOperationalReadiness? get readiness => _readiness;
  Object? get lastError => _lastError;
  bool get isChecking => _inFlight != null;
  bool get hasSnapshot => _readiness != null;
  bool get checkFailed => _lastError != null && _readiness == null;

  Future<void> check({bool force = false}) {
    if (!force && _readiness != null) return Future<void>.value();
    final running = _inFlight;
    if (running != null) return running;

    final task = _performCheck();
    _inFlight = task;
    notifyListeners();
    return task.whenComplete(() {
      if (identical(_inFlight, task)) {
        _inFlight = null;
        notifyListeners();
      }
    });
  }

  Future<void> _performCheck() async {
    try {
      final service =
          _providedService ??
          (_lazyService ??= ErpOperationalReadinessService());
      _readiness = await service.check();
      _lastError = null;
    } catch (error, stackTrace) {
      _lastError = error;
      AppLogger.warning('ERP runtime readiness check failed: $error');
      AppLogger.stack(stackTrace);
    }
  }

  List<String> requiredCapabilitiesForRoute(String route) {
    final normalized = route.split('?').first;
    return List<String>.unmodifiable(
      _routeCapabilities[normalized] ?? const <String>[],
    );
  }

  List<String> unavailableCapabilitiesForRoute(String route) {
    final snapshot = _readiness;
    if (snapshot == null) return const <String>[];
    return requiredCapabilitiesForRoute(route)
        .where(
          (capability) =>
              snapshot.modules[capability] != ErpModuleReadiness.ready,
        )
        .toList(growable: false);
  }

  bool routeIsReady(String route) =>
      unavailableCapabilitiesForRoute(route).isEmpty;

  static const Map<String, List<String>> _routeCapabilities =
      <String, List<String>>{
        '/dashboard': <String>['dashboard'],
        '/global-search': <String>['search'],
        '/notifications': <String>['notifications'],
        '/inventory': <String>['cars', 'inventory'],
        '/products': <String>['cars', 'inventory'],
        '/maintenance': <String>['maintenance'],
        '/business-partners': <String>['customers', 'suppliers'],
        '/customer-service': <String>['customer_service'],
        '/sales': <String>['sales', 'installments'],
        '/purchases': <String>['purchases'],
        '/accounting': <String>['accounting', 'cashbox', 'expenses'],
        '/settings': <String>['settings', 'access'],
        '/settings/reports': <String>['reports'],
      };
}
