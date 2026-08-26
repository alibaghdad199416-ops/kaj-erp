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
    if (uri == null || uri.host.isEmpty) {
      return 'رابط Supabase غير صالح.';
    }

    final isLocal =
        (uri.host == 'localhost' || uri.host == '127.0.0.1') &&
        (uri.scheme == 'http' || uri.scheme == 'https');
    final isHosted = uri.scheme == 'https' && uri.host.endsWith('.supabase.co');
    if (!isLocal && !isHosted) {
      return 'رابط Supabase يجب أن يكون رابط مشروع HTTPS على .supabase.co أو رابط Supabase محلياً عبر localhost/127.0.0.1.';
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      return 'استخدم رابط Supabase الأساسي فقط، من دون /rest/v1 أو أي مسار إضافي.';
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
