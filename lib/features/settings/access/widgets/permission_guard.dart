import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';

import 'package:quality_line_erp/app/route_names.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';

class PermissionGuard extends StatefulWidget {
  const PermissionGuard({
    super.key,
    required this.permission,
    required this.child,
  });

  final String permission;
  final Widget child;

  @override
  State<PermissionGuard> createState() => _PermissionGuardState();
}

class _PermissionGuardState extends State<PermissionGuard> {
  bool _deniedRecorded = false;
  bool _restoreScheduled = false;
  bool _redirectScheduled = false;

  void _scheduleSessionRestoreOrRedirect(AccessController access) {
    if (_restoreScheduled || _redirectScheduled) return;
    _restoreScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // A browser reload or deep link can build a protected route before the
      // in-memory AccessController has been reconstructed. Do not discard a
      // valid Supabase browser session merely because this widget rendered
      // before SplashPage had a chance to restore it.
      if (access.isAuthenticated) {
        _restoreScheduled = false;
        return;
      }

      final restored = await access.restorePersistedSession();
      if (!mounted) return;
      if (restored || access.isAuthenticated) {
        _restoreScheduled = false;
        setState(() {});
        return;
      }

      _redirectScheduled = true;
      await Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRouteNames.login, (route) => false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessController>();

    if (!access.isAuthenticated) {
      _scheduleSessionRestoreOrRedirect(access);
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.black)),
      );
    }

    if (access.hasPermission(widget.permission)) {
      return widget.child;
    }

    if (!_deniedRecorded) {
      _deniedRecorded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await context.read<AccessController>().recordDeniedAccess(
          widget.permission,
        );
      });
    }

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        appBar: AppBar(title: const AppText('غير مصرح')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: 80,
                    color: Colors.black54,
                  ),
                  const SizedBox(height: 20),
                  const AppText(
                    'ليس لديك صلاحية للوصول إلى هذه الصفحة',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  AppText(
                    'الصلاحية المطلوبة: ${widget.permission}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).pushNamedAndRemoveUntil(
                        AppRouteNames.dashboard,
                        (route) => false,
                      );
                    },
                    icon: const Icon(Icons.dashboard_outlined),
                    label: const AppText('العودة إلى لوحة التحكم'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
