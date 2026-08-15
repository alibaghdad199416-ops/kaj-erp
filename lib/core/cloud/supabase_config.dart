class SupabaseConfig {
  SupabaseConfig._();

  /// The only hosted Supabase project used by the current KAJ ERP production
  /// runtime. Local Supabase CLI development remains available through the
  /// explicit loopback opt-in below.
  static const String expectedProductionProjectRef =
      'havlqebmnjdcwmpaaqew';

  // Browser-facing project defaults keep local inspection reliable even
  // when Flutter is launched without --dart-define-from-file. Explicit
  // dart-defines still override these values. Never place secret/service
  // role keys here; only the public Supabase project URL/publishable key.
  static const String _defaultProjectUrl =
      'https://havlqebmnjdcwmpaaqew.supabase.co';
  static const String _defaultPublishableKey =
      'sb_publishable_JfrD4JkzaOkkZDbANocq_g_-MRdyWix';

  /// Supply these values at run/build time. The publishable key is safe for a
  /// browser client; service-role and secret keys are rejected explicitly.
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _defaultProjectUrl,
  );

  static const String publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment(
      'SUPABASE_ANON_KEY',
      defaultValue: _defaultPublishableKey,
    ),
  );

  /// Identifies the local Supabase CLI project and isolates its browser state.
  /// Supplying this value is also an explicit, narrowly scoped opt-in to a
  /// loopback backend. Production define files omit it.
  static const String localProjectId = String.fromEnvironment(
    'SUPABASE_LOCAL_PROJECT_ID',
    defaultValue: '',
  );

  /// Compatibility opt-in retained for older local launch scripts.
  static const bool _explicitAllowLocalDev = bool.fromEnvironment(
    'SUPABASE_ALLOW_LOCAL_DEV',
    defaultValue: false,
  );

  static bool get allowLocalDev => resolveLocalDevelopmentOptIn(
    explicitAllowLocalDev: _explicitAllowLocalDev,
    localProjectId: localProjectId,
  );

  static bool resolveLocalDevelopmentOptIn({
    required bool explicitAllowLocalDev,
    required String localProjectId,
  }) => explicitAllowLocalDev || localProjectId.trim().isNotEmpty;

  /// Project-ref/runtime namespace used to isolate browser auth and tenant
  /// selections. This prevents an old Supabase project or tenant selection
  /// from being reused after the runtime backend changes.
  static String get projectRef => projectRefFor(
    projectUrl: url,
    localProjectId: localProjectId,
  );

  static String get browserStorageNamespace => storageNamespaceFor(
    projectUrl: url,
    localProjectId: localProjectId,
  );

  static String get authPersistSessionKey =>
      'kaj-erp-$browserStorageNamespace-auth-token';

  static String projectRefFor({
    required String projectUrl,
    String localProjectId = '',
  }) {
    final uri = Uri.tryParse(projectUrl.trim());
    final host = uri?.host.toLowerCase() ?? '';
    if (_isLoopback(host)) {
      final local = localProjectId.trim();
      return local.isEmpty ? 'quality_line_erp_local_dev' : local;
    }
    const suffix = '.supabase.co';
    if (host.endsWith(suffix)) {
      final ref = host.substring(0, host.length - suffix.length).trim();
      if (ref.isNotEmpty && !ref.contains('.')) return ref;
    }
    return host.isEmpty ? 'unknown_supabase_backend' : host;
  }

  static String storageNamespaceFor({
    required String projectUrl,
    String localProjectId = '',
  }) => projectRefFor(
    projectUrl: projectUrl,
    localProjectId: localProjectId,
  ).replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');

  /// Compatibility alias used by older scripts in existing deployments.
  static String get anonKey => publishableKey;

  static String? validate({
    String? projectUrl,
    String? publishableKey,
    bool? allowLocalDevelopment,
  }) => validateConfiguration(
    projectUrl: (projectUrl ?? url).trim(),
    publishableKey: (publishableKey ?? SupabaseConfig.publishableKey).trim(),
    allowLocalDev: allowLocalDevelopment ?? SupabaseConfig.allowLocalDev,
  );

  static String? validateConfiguration({
    required String projectUrl,
    required String publishableKey,
    required bool allowLocalDev,
  }) {
    final resolvedUrl = projectUrl.trim();
    final resolvedKey = publishableKey.trim();

    // R57_LOCAL_LOOPBACK_CONFIG_FIX
    // Local Supabase development is intentionally allowed only on loopback.
    // Hosted Supabase validation below remains unchanged and still requires
    // the normal hosted URL/security rules.
    final localUri = Uri.tryParse(resolvedUrl);
    final localHost = localUri?.host.toLowerCase() ?? '';
    final isLocalLoopback =
        localHost == '127.0.0.1' ||
        localHost == 'localhost' ||
        localHost.endsWith('.localhost');

    if (isLocalLoopback && allowLocalDev) {
      final validLocalScheme =
          localUri != null &&
          (localUri.scheme == 'http' || localUri.scheme == 'https');

      if (!validLocalScheme || localUri.host.isEmpty) {
        return 'رابط Supabase المحلي غير صالح.';
      }
      if (localUri.path.isNotEmpty && localUri.path != '/') {
        return 'استخدم رابط Supabase المحلي الأساسي فقط، من دون /rest/v1 أو أي مسار إضافي.';
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

    final uri = Uri.tryParse(resolvedUrl);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return 'رابط Supabase غير صالح. استخدم رابط المشروع الأساسي عبر HTTPS.';
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      return 'استخدم رابط مشروع Supabase الأساسي فقط، من دون /rest/v1 أو أي مسار إضافي.';
    }
    final localTarget = _isLoopback(uri.host);
    final validLocal =
        allowLocalDev &&
        uri.scheme == 'http' &&
        localTarget &&
        uri.hasPort &&
        uri.port > 0;
    final validHosted =
        uri.scheme == 'https' &&
        uri.host.endsWith('.supabase.co') &&
        !localTarget &&
        !uri.hasPort;
    if (!validLocal && !validHosted) {
      return 'رابط Supabase يجب أن ينتهي بـ .supabase.co.';
    }
    if (resolvedKey.isEmpty || resolvedKey.contains('YOUR_')) {
      return 'مفتاح Supabase العام غير مضبوط.';
    }
    final normalizedKey = resolvedKey.toLowerCase();
    if (normalizedKey.contains('service_role') ||
        normalizedKey.startsWith('sb_secret_')) {
      return 'لا تستخدم مفتاحاً سرياً داخل تطبيق الويب. استخدم Publishable/anon key.';
    }
    return null;
  }

  static bool isLocalTarget({
    String? projectUrl,
    String? publishableKey,
    bool? allowLocalDevelopment,
  }) {
    final resolvedUrl = (projectUrl ?? url).trim();
    final resolvedKey = (publishableKey ?? SupabaseConfig.publishableKey)
        .trim();
    final allowed = allowLocalDevelopment ?? allowLocalDev;
    if (validateConfiguration(
          projectUrl: resolvedUrl,
          publishableKey: resolvedKey,
          allowLocalDev: allowed,
        ) !=
        null) {
      return false;
    }
    final uri = Uri.parse(resolvedUrl);
    return allowed && uri.scheme == 'http' && _isLoopback(uri.host);
  }

  static String environmentLabel({
    required bool isArabic,
    String? projectUrl,
    String? publishableKey,
    bool? allowLocalDevelopment,
  }) =>
      isLocalTarget(
        projectUrl: projectUrl,
        publishableKey: publishableKey,
        allowLocalDevelopment: allowLocalDevelopment,
      )
      ? (isArabic
            ? 'بيئة تطوير Supabase المحلية'
            : 'Local Supabase Development Environment')
      : (isArabic
            ? 'اتصال آمن عبر Supabase • استضافة Firebase'
            : 'Secure Supabase connection • Firebase Hosting');

  static bool _isLoopback(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1' ||
        normalized.endsWith('.localhost');
  }

  static bool get isConfigured => validate() == null;
}
