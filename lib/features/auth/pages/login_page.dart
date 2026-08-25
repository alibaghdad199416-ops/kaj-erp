import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:quality_line_erp/app/route_names.dart';
import 'package:quality_line_erp/core/cloud/cloud_auth_service.dart';
import 'package:quality_line_erp/core/errors/user_facing_error.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:quality_line_erp/core/preferences/app_preferences_controller.dart';
import 'package:quality_line_erp/core/startup/authenticated_data_loader.dart';
import 'package:quality_line_erp/core/startup/startup_coordinator.dart';
import 'package:quality_line_erp/core/widgets/app_launch_shell.dart';
import 'package:quality_line_erp/design_system/kaj_design_tokens.dart';
import 'package:quality_line_erp/design_system/kaj_shell_components.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isRecoveringPassword = false;
  bool _submitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_submitting) return;
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    final access = context.read<AccessController>();
    try {
      try {
        await StartupCoordinator.instance.waitUntilReady(
          timeout: const Duration(seconds: 150),
        );
      } on TimeoutException {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: AppText(
              'لم تكتمل تهيئة قاعدة البيانات. حدّث الصفحة أو أعد المحاولة.',
            ),
            backgroundColor: KajDesignTokens.danger,
          ),
        );
        return;
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
              userFacingError(
                error,
                isArabic: context.l10n.isArabic,
                arabicFallback: 'تعذر تجهيز بيانات النظام.',
                englishFallback: 'Unable to prepare system data.',
              ),
            ),
            backgroundColor: KajDesignTokens.danger,
          ),
        );
        return;
      }

      final success = await access.login(
        username: _usernameController.text,
        password: _passwordController.text,
      );
      if (!mounted) return;

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText(
              access.errorMessage ?? context.l10n.text('loginFailed'),
            ),
            backgroundColor: KajDesignTokens.danger,
          ),
        );
        return;
      }

      // Authentication is the navigation boundary. Preferences, dashboard and
      // runtime readiness are useful warm-up tasks, but none of them should
      // leave an already authenticated user on the login screen or require a
      // second click. They continue in the background after routing.
      final preferences = context.read<AppPreferencesController>();
      unawaited(() async {
        try {
          await Future.wait<void>(<Future<void>>[
            preferences.synchronizeForCurrentUser(),
            AuthenticatedDataLoader.load(context),
          ]);
        } catch (error, stackTrace) {
          AppLogger.debug('Post-login warm-up skipped: $error');
          AppLogger.stack(stackTrace);
        }
      }());

      await Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRouteNames.dashboard, (route) => false);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _recoverPassword() async {
    FocusScope.of(context).unfocus();
    final ar = context.l10n.isArabic;
    final email = _usernameController.text.trim().toLowerCase();

    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            ar
                ? 'أدخل بريدًا إلكترونيًا سحابيًا صالحًا أولًا.'
                : 'Enter a valid cloud email address first.',
          ),
          backgroundColor: KajDesignTokens.danger,
        ),
      );
      return;
    }

    if (_isRecoveringPassword) return;
    setState(() => _isRecoveringPassword = true);

    try {
      final result = await CloudAuthService.instance.sendPasswordReset(
        email: email,
      );
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            result.success
                ? (ar
                      ? 'تم إرسال رابط استعادة كلمة المرور إلى بريدك السحابي.'
                      : 'A password recovery link was sent to your cloud email.')
                : (ar
                      ? 'تعذر إرسال رابط استعادة كلمة المرور. تحقق من البريد والاتصال.'
                      : 'Unable to send the recovery link. Check the email and connection.'),
          ),
          backgroundColor: result.success
              ? KajDesignTokens.success
              : KajDesignTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isRecoveringPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = context.watch<AccessController>();
    final ar = context.l10n.isArabic;
    final scheme = Theme.of(context).colorScheme;

    return AppLaunchShell(
      topTrailing: const AppLaunchPreferencesSwitch(),
      content: AutofillGroup(
        child: Form(
          key: _formKey,
          child: AppLaunchContentPanel(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: KajDesignTokens.electricBlue.withValues(
                          alpha: .10,
                        ),
                        borderRadius: BorderRadius.circular(
                          KajDesignTokens.radiusSm,
                        ),
                        border: Border.all(
                          color: KajDesignTokens.electricBlue.withValues(
                            alpha: .24,
                          ),
                        ),
                      ),
                      child: const Icon(
                        Icons.lock_person_outlined,
                        size: 20,
                        color: KajDesignTokens.electricBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          AppText(
                            context.l10n.text('login'),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          AppText(
                            ar
                                ? 'استخدم حساب Supabase المعتمد.'
                                : 'Use your authorized Supabase account.',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                KajField(
                  key: const ValueKey('login-username'),
                  controller: _usernameController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  label: ar
                      ? 'البريد الإلكتروني السحابي'
                      : 'Cloud email address',
                  hint: 'name@company.com',
                  leading: Icons.alternate_email_rounded,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? (ar
                            ? 'أدخل البريد الإلكتروني السحابي.'
                            : 'Enter the cloud email address.')
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  key: const ValueKey('login-password'),
                  controller: _passwordController,
                  autofillHints: const <String>[AutofillHints.password],
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: context.l10n.text('password'),
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? context.l10n.text('showPassword')
                          : context.l10n.text('hidePassword'),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return context.l10n.text('enterPassword');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton.icon(
                    onPressed:
                        access.isAuthenticating ||
                            _isRecoveringPassword ||
                            _submitting
                        ? null
                        : _recoverPassword,
                    icon: _isRecoveringPassword
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_reset_outlined, size: 17),
                    label: AppText(
                      ar ? 'استعادة كلمة المرور' : 'Recover password',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: KajPrimaryAction(
                    onPressed:
                        access.isAuthenticating ||
                            _isRecoveringPassword ||
                            _submitting
                        ? null
                        : _login,
                    busy: access.isAuthenticating || _submitting,
                    icon: Icons.login_rounded,
                    label: access.isAuthenticating || _submitting
                        ? context.l10n.text('loggingIn')
                        : context.l10n.text('login'),
                  ),
                ),
                const SizedBox(height: 17),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(
                      Icons.verified_user_outlined,
                      size: 14,
                      color: KajDesignTokens.electricBlue,
                    ),
                    const SizedBox(width: 6),
                    AppText(
                      ar
                          ? 'جلسة مشفرة وصلاحيات حسب المستخدم'
                          : 'Encrypted session and user-based permissions',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
