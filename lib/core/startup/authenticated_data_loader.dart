import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/core/cloud/erp_runtime_capabilities_controller.dart';
import 'package:quality_line_erp/core/performance/async_task_pool.dart';
import 'package:quality_line_erp/features/dashboard/controllers/dashboard_controller.dart';

/// Loads only the data required for the first authenticated screen.
///
/// Previous releases fetched every ERP module during sign-in. That made login
/// and browser refresh wait for many unrelated network requests. Each module
/// already owns its own lazy loader, so startup now warms only runtime readiness and the dashboard summary.
class AuthenticatedDataLoader {
  const AuthenticatedDataLoader._();

  static Future<void> load(BuildContext context) async {
    final runtimeCapabilities = context
        .read<ErpRuntimeCapabilitiesController>();
    final dashboard = context.read<DashboardController>();

    // The authenticated bootstrap already carries the active user and
    // permissions. Keep the background warm-up intentionally small so slow
    // reports, notifications or another permission snapshot cannot delay the
    // first dashboard frame.
    const pool = AsyncTaskPool(maxConcurrent: 2);
    await pool.runAll(<NamedAsyncTask>[
      NamedAsyncTask(name: 'runtime-readiness', run: runtimeCapabilities.check),
      NamedAsyncTask(name: 'dashboard', run: dashboard.loadDashboard),
    ]);
  }
}
