import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/app/app.dart';
import 'package:quality_line_erp/app/bootstrap/app_dependencies.dart';
import 'package:quality_line_erp/core/cloud/cloud_bootstrap.dart';
import 'package:quality_line_erp/core/cloud/cloud_tenant_context.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:quality_line_erp/core/performance/app_performance.dart';
import 'package:quality_line_erp/core/release/app_release_info.dart';
import 'package:quality_line_erp/core/startup/startup_coordinator.dart';

Future<void> main() async {
  await runZonedGuarded(_bootstrap, (error, stackTrace) {
    AppLogger.error(
      'Uncaught application error',
      error: error,
      stackTrace: stackTrace,
    );
  });
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.debug('KAJ ERP ${AppReleaseInfo.runtimeSignature} starting');

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.debug('Flutter framework error: ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLogger.error(
      'Platform dispatcher error',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };
  ErrorWidget.builder = (details) =>
      _AppFailureView(message: details.exceptionAsString());
  AppPerformance.configure();

  // Supabase Cloud is the only production persistence/authentication boundary.
  // Fail closed before starting providers, refresh loops, or cached tenant
  // state so local preferences can never masquerade as an ERP session.
  final cloud = await CloudBootstrap.initialize();
  if (!cloud.supabaseReady) {
    runApp(
      _CloudUnavailableApp(
        message: cloud.messages.isEmpty
            ? 'تعذر تهيئة Supabase Cloud.'
            : cloud.messages.join(' | '),
      ),
    );
    return;
  }

  try {
    await CloudTenantContext.instance.load();
  } catch (error, stackTrace) {
    AppLogger.debug('Tenant cache restore failed: $error');
    AppLogger.stack(stackTrace);
    try {
      await CloudTenantContext.instance.clearCloudSelection();
    } catch (clearError, clearStackTrace) {
      AppLogger.debug('Tenant cache reset failed: $clearError');
      AppLogger.stack(clearStackTrace);
    }
  }

  await StartupCoordinator.instance.run(
    prerequisites: const [],
    primaryData: const [],
    aggregates: const [],
  );

  final dependencies = AppDependencies.create();
  try {
    await dependencies.preferences.load();
  } catch (error, stackTrace) {
    AppLogger.debug('Application preferences restore failed: $error');
    AppLogger.stack(stackTrace);
  }
  await dependencies.refreshCoordinator.start();

  runApp(
    MultiProvider(providers: dependencies.providers, child: const MyApp()),
  );
}

class _CloudUnavailableApp extends StatelessWidget {
  const _CloudUnavailableApp({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _AppFailureView(message: message),
    );
  }
}

class _AppFailureView extends StatelessWidget {
  const _AppFailureView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF050A11),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 46),
                    const SizedBox(height: 14),
                    const AppText(
                      'تعذر تشغيل النظام السحابي',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const AppText(
                      'لم يتم تشغيل بيانات ERP أو جلسة محلية بديلة. تحقق من إعدادات Supabase Cloud ثم أعد تحميل الصفحة.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    AppSelectableText(
                      message,
                      maxLines: 5,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
