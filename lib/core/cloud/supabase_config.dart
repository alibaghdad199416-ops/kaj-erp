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

  static String get anonKey => publishableKey;

  static bool _isLocalUrl(Uri uri) =>
      (uri.host == '127.0.0.1' || uri.host == 'localhost') &&
      (uri.scheme == 'http' || uri.scheme == 'https');

  static String? validate({String? projectUrl, String? publishableKey}) {
    final resolvedUrl = (projectUrl ?? url).trim();
    final resolvedKey = (publishableKey ?? SupabaseConfig.publishableKey)
        .trim();

    final uri = Uri.tryParse(resolvedUrl);
    if (uri == null || uri.host.isEmpty) {
      return 'رابط Supabase غير صالح.';
    }

    // Local Docker/Supabase development is intentionally allowed only on the
    // loopback interface. Production URLs still require HTTPS and .supabase.co.
    final isLocal = _isLocalUrl(uri);
    if (!isLocal) {
      if (uri.scheme != 'https') {
        return 'رابط Supabase غير صالح. استخدم رابط المشروع الأساسي عبر HTTPS.';
      }
      if (!uri.host.endsWith('.supabase.co')) {
        return 'رابط Supabase يجب أن ينتهي بـ .supabase.co.';
      }
    }

    if (uri.path.isNotEmpty && uri.path != '/') {
      return 'استخدم رابط مشروع Supabase الأساسي فقط، من دون /rest/v1 أو أي مسار إضافي.';
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
