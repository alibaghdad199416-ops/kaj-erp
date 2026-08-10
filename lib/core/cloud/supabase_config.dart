class SupabaseConfig {
  SupabaseConfig._();

  /// Supply these values at run/build time. The publishable key is safe for a
  /// browser client; service-role and secret keys are rejected explicitly.
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: ''),
  );

  /// Compatibility alias used by older scripts in existing deployments.
  static String get anonKey => publishableKey;

  static String? validate({String? projectUrl, String? publishableKey}) {
    final resolvedUrl = (projectUrl ?? url).trim();
    final resolvedKey = (publishableKey ?? SupabaseConfig.publishableKey)
        .trim();

    final uri = Uri.tryParse(resolvedUrl);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'رابط Supabase غير صالح. استخدم رابط المشروع الأساسي عبر HTTPS.';
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      return 'استخدم رابط مشروع Supabase الأساسي فقط، من دون /rest/v1 أو أي مسار إضافي.';
    }
    if (!uri.host.endsWith('.supabase.co')) {
      return 'رابط Supabase يجب أن ينتهي بـ .supabase.co.';
    }
    if (resolvedKey.isEmpty || resolvedKey.contains('YOUR_')) {
      return 'مفتاح Supabase العام غير مضبوط.';
    }
    if (resolvedKey.startsWith('service_role') ||
        resolvedKey.startsWith('sb_secret_')) {
      return 'لا تستخدم مفتاحاً سرياً داخل تطبيق الويب. استخدم Publishable/anon key.';
    }
    return null;
  }

  static bool get isConfigured => validate() == null;
}
