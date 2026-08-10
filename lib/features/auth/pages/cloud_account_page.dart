import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:quality_line_erp/core/localization/app_localizations.dart';
import 'package:quality_line_erp/core/preferences/app_preferences_controller.dart';

import 'package:quality_line_erp/app/route_names.dart';
import 'package:quality_line_erp/core/cloud/cloud_auth_service.dart';
import 'package:quality_line_erp/core/cloud/cloud_provider_status.dart';
import 'package:quality_line_erp/core/startup/startup_coordinator.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';

class CloudAccountPage extends StatefulWidget {
  const CloudAccountPage({super.key});

  @override
  State<CloudAccountPage> createState() => _CloudAccountPageState();
}

class _CloudAccountPageState extends State<CloudAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    await _signInToErp();
  }

  Future<void> _signInToErp() async {
    if (_busy) {
      return;
    }

    setState(() => _busy = true);

    final access = context.read<AccessController>();

    try {
      await StartupCoordinator.instance.waitUntilReady(
        timeout: const Duration(seconds: 150),
      );

      final success = await access.login(
        username: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text,
      );

      if (!mounted) {
        return;
      }

      if (success) {
        await context
            .read<AppPreferencesController>()
            .synchronizeForCurrentUser();
        if (!mounted) return;
        await Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AppRouteNames.dashboard, (route) => false);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            access.errorMessage ?? 'تعذر تسجيل الدخول إلى نظام ERP.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } on TimeoutException {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText(
            'لم تكتمل تهيئة قاعدة البيانات. حدّث الصفحة ثم أعد المحاولة.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } catch (error, stackTrace) {
      AppLogger.debug('Cloud ERP sign-in failed: $error');
      AppLogger.stack(stackTrace);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText(
            'تعذر تجهيز تسجيل الدخول السحابي. أعد المحاولة بعد تحديث الصفحة.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    FocusScope.of(context).unfocus();

    final email = _emailController.text.trim().toLowerCase();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('أدخل البريد الإلكتروني أولًا.')),
      );
      return;
    }

    if (_busy) {
      return;
    }

    setState(() => _busy = true);

    try {
      final result = await CloudAuthService.instance.sendPasswordReset(
        email: email,
      );

      if (!mounted) {
        return;
      }

      await _showResult(result);
    } catch (error, stackTrace) {
      AppLogger.debug('Cloud password reset failed: $error');
      AppLogger.stack(stackTrace);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: AppText('تعذر إرسال رابط استعادة كلمة المرور.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _showResult(CloudAuthResult result) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          icon: Icon(
            result.success
                ? Icons.cloud_done_outlined
                : Icons.cloud_off_outlined,
          ),
          title: AppText(
            result.success ? 'اكتملت العملية' : 'تعذر إكمال العملية',
          ),
          content: AppText(result.message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const AppText('حسنًا'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = CloudProviderStatus.current();
    final configured = status.hybridConfigured;

    return Scaffold(
      appBar: AppBar(
        title: const AppText('الحساب السحابي'),
        leading: IconButton(
          onPressed: _busy
              ? null
              : () async {
                  await Navigator.pushReplacementNamed(
                    context,
                    AppRouteNames.login,
                  );
                },
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.cloud_outlined,
                        size: 54,
                        color: colors.primary,
                      ),
                      const SizedBox(height: 12),
                      AppText(
                        'الدخول إلى الحساب السحابي',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      AppText(
                        'يتم تسجيل الدخول عبر Supabase، ثم تحميل مستخدم ERP من قاعدة البيانات '
                        'ودوره وصلاحياته وفتح لوحة التحكم مباشرة.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      if (!configured) ...[
                        const SizedBox(height: 16),
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: AppText(
                              'يجب تهيئة Supabase في نسخة التطبيق الحالية.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      InputDecorator(
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate('مزود الحساب'),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.cloud_done_outlined),
                        ),
                        child: const AppText(
                          'مصادقة Supabase وقاعدة بيانات PostgreSQL للنظام',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        enabled: !_busy,
                        autofillHints: const [
                          AutofillHints.email,
                          AutofillHints.username,
                        ],
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate(
                            'البريد الإلكتروني',
                          ),
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';

                          if (email.isEmpty) {
                            return AppTranslation.translate(
                              'أدخل البريد الإلكتروني.',
                            );
                          }

                          if (!email.contains('@')) {
                            return AppTranslation.translate(
                              'أدخل بريدًا إلكترونيًا صحيحًا.',
                            );
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        enabled: !_busy,
                        autofillHints: const [AutofillHints.password],
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) async {
                          if (!_busy && configured) {
                            await _submit();
                          }
                        },
                        decoration: InputDecoration(
                          labelText: AppTranslation.translate('كلمة المرور'),
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    setState(() {
                                      _obscure = !_obscure;
                                    });
                                  },
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return AppTranslation.translate(
                              'أدخل كلمة المرور.',
                            );
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _busy || !configured ? null : _submit,
                        icon: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login),
                        label: AppText(
                          _busy ? 'جاري تسجيل الدخول...' : 'تسجيل الدخول',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _busy || !configured ? null : _resetPassword,
                        icon: const Icon(Icons.lock_reset_outlined),
                        label: const AppText('استعادة كلمة المرور'),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                await Navigator.pushReplacementNamed(
                                  context,
                                  AppRouteNames.login,
                                );
                              },
                        child: const AppText('العودة إلى شاشة الدخول'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
