import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/app/route_names.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/cloud/cloud_bootstrap.dart';
import 'package:quality_line_erp/core/startup/startup_coordinator.dart';
import 'package:quality_line_erp/core/widgets/app_launch_shell.dart';
import 'package:quality_line_erp/design_system/kaj_entry_components.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_shell_components.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';

import 'package:quality_line_erp/core/errors/user_facing_error.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  String? _error;
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    unawaited(_awaitStartup());
  }

  Future<void> _awaitStartup({bool retry = false}) async {
    if (mounted) {
      setState(() {
        _error = null;
        _retrying = retry;
      });
    }

    try {
      if (retry) {
        final cloud = await CloudBootstrap.initialize(retry: true);
        if (!cloud.supabaseReady) {
          throw StateError(cloud.messages.join(' | '));
        }
      } else {
        await StartupCoordinator.instance.waitUntilReady();
        final cloud = CloudBootstrap.lastResult;
        if (cloud == null || !cloud.supabaseReady) {
          throw StateError(
            cloud?.messages.join(' | ') ??
                'Supabase initialization did not complete.',
          );
        }
      }
      if (!mounted) return;
      final access = context.read<AccessController>();
      final restored = await access.restorePersistedSession();
      if (!mounted) return;
      await Navigator.of(context).pushNamedAndRemoveUntil(
        restored ? AppRouteNames.dashboard : AppRouteNames.login,
        (route) => false,
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _retrying = false;
        _error = context.l10n.isArabic
            ? 'استغرق الاتصال بخدمة النظام وقتًا أطول من المتوقع.'
            : 'System initialization took longer than expected.';
      });
    } catch (error, stackTrace) {
      AppLogger.debug('System initialization failed: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _retrying = false;
        _error = userFacingError(
          error,
          isArabic: context.l10n.isArabic,
          arabicFallback: 'تعذر الاتصال بخدمة النظام. أعد المحاولة.',
          englishFallback: 'Unable to initialize the system. Try again.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AppLaunchShell(
      topTrailing: const AppLaunchPreferencesSwitch(),
      content: AppLaunchContentPanel(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _error == null
              ? KajEntryPanel(
                  key: const ValueKey('startup-loading'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SizedBox.square(
                        dimension: 38,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: KajDesignTokens.electricBlue,
                        ),
                      ),
                      const SizedBox(height: 20),
                      KajEntryHeading(
                        eyebrow: context.l10n.isArabic
                            ? 'تهيئة النظام'
                            : 'SYSTEM INITIALIZATION',
                        title: context.l10n.isArabic
                            ? 'مرحباً بك في مساحة العمل'
                            : 'Welcome to your workspace',
                        subtitle: context.l10n.isArabic
                            ? 'جارٍ تجهيز الاتصال الآمن والصلاحيات وبيانات التشغيل.'
                            : 'Preparing secure connectivity, permissions and operational data.',
                        icon: Icons.auto_awesome_rounded,
                      ),
                    ],
                  ),
                )
              : Column(
                  key: const ValueKey('startup-error'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, color: colors.error, size: 40),
                    const SizedBox(height: 12),
                    AppText(
                      _error ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colors.error),
                    ),
                    const SizedBox(height: 18),
                    KajPrimaryAction(
                      onPressed: _retrying
                          ? null
                          : () => _awaitStartup(retry: true),
                      busy: _retrying,
                      icon: Icons.refresh_rounded,
                      label: context.l10n.isArabic ? 'إعادة المحاولة' : 'Retry',
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
