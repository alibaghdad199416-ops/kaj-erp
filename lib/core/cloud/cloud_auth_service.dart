import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_bootstrap.dart';

class CloudAuthResult {
  const CloudAuthResult({required this.success, required this.message});
  final bool success;
  final String message;
}

/// Supabase Authentication account operations used by the web login flow.
class CloudAuthService {
  CloudAuthService._();
  static final instance = CloudAuthService._();

  Future<CloudAuthResult> sendPasswordReset({required String email}) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalizedEmail)) {
      return const CloudAuthResult(
        success: false,
        message: 'أدخل بريدًا إلكترونيًا صالحًا.',
      );
    }
    try {
      final bootstrap = await CloudBootstrap.initialize();
      if (!bootstrap.supabaseReady) {
        return const CloudAuthResult(
          success: false,
          message: 'Supabase Authentication غير مضبوط في هذه النسخة.',
        );
      }
      await Supabase.instance.client.auth
          .resetPasswordForEmail(normalizedEmail)
          .timeout(const Duration(seconds: 25));
      return const CloudAuthResult(
        success: true,
        message: 'تم إرسال رابط استعادة كلمة المرور عبر Supabase.',
      );
    } on TimeoutException {
      return const CloudAuthResult(
        success: false,
        message: 'انتهت مهلة الاتصال بخدمة Supabase.',
      );
    } on AuthException catch (error) {
      return CloudAuthResult(success: false, message: error.message);
    } catch (error, stackTrace) {
      AppLogger.debug('Supabase password reset failed: $error\n$stackTrace');
      return const CloudAuthResult(
        success: false,
        message: 'تعذر إرسال رابط استعادة كلمة المرور.',
      );
    }
  }
}
