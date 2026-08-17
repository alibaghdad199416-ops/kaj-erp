class SupabaseConfig {
  SupabaseConfig._();

  static const String _defaultProjectUrl = 'http://127.0.0.1:54321';
  static const String _defaultPublishableKey = '';
  static const String _defaultLocalProjectId = 'quality_line_erp_local_dev';

  /// Quality Line ERP is intentionally local-Supabase-only in this branch.
  /// The public key is environment-specific and must come from `supabase status`
  /// (or an equivalent local launch configuration); it is never committed.
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

  static const String localProjectId = String.fromEnvironment(
    'SUPABASE_LOCAL_PROJECT_ID',
    defaultValue: _defaultLocalProjectId,
  );

  static const bool _explicitAllowLocalDev = bool.fromEnvironment(
    'SUPABASE_ALLOW_LOCAL_DEV',
    defaultValue: true,
  );

  static bool get allowLocalDev => resolveLocalDevelopmentOptIn(
    explicitAllowLocalDev: _explicitAllowLocalDev,
    localProjectId: localProjectId,
  );

  static bool resolveLocalDevelopmentOptIn({
    required bool explicitAllowLocalDev,
    required String localProjectId,
  }) => explicitAllowLocalDev || localProjectId.trim().isNotEmpty;

  static String get projectRef =>
      projectRefFor(projectUrl: url, localProjectId: localProjectId);

  static String get browserStorageNamespace =>
      storageNamespaceFor(projectUrl: url, localProjectId: localProjectId);

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
      return local.isEmpty ? _defaultLocalProjectId : local;
    }
    return host.isEmpty ? 'blocked_non_local_backend' : host;
  }

  static String storageNamespaceFor({
    required String projectUrl,
    String localProjectId = '',
  }) => projectRefFor(
    projectUrl: projectUrl,
    localProjectId: localProjectId,
  ).replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');

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

  static String? validateRuntime() => validate();

  static String? validateConfiguration({
    required String projectUrl,
    required String publishableKey,
    required bool allowLocalDev,
  }) {
    final resolvedUrl = projectUrl.trim();
    final resolvedKey = publishableKey.trim();
    final uri = Uri.tryParse(resolvedUrl);

    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return 'رابط Supabase المحلي غير صالح.';
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      return 'استخدم رابط Supabase المحلي الأساسي فقط، من دون /rest/v1 أو أي مسار إضافي.';
    }
    if (!allowLocalDev ||
        uri.scheme != 'http' ||
        !_isLoopback(uri.host) ||
        !uri.hasPort ||
        uri.port <= 0) {
      return 'هذا الإصدار يعمل مع Local Supabase فقط على localhost/127.0.0.1.';
    }
    if (resolvedKey.isEmpty || resolvedKey.contains('YOUR_')) {
      return 'مفتاح Supabase المحلي العام غير مضبوط. استخدم المفتاح العام من supabase status.';
    }
    final normalizedKey = resolvedKey.toLowerCase();
    if (normalizedKey.contains('service_role') ||
        normalizedKey.startsWith('sb_secret_')) {
      return 'لا تستخدم مفتاحاً سرياً داخل تطبيق الويب. استخدم Publishable/anon key المحلي.';
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
    return uri.scheme == 'http' && _isLoopback(uri.host);
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
      : (isArabic ? 'Local Supabase مطلوب' : 'Local Supabase Required');

  static bool _isLoopback(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1' ||
        normalized.endsWith('.localhost');
  }

  static bool get isConfigured => validateRuntime() == null;
}
