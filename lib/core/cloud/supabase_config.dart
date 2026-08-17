class SupabaseConfig {
  SupabaseConfig._();

  static const String expectedProductionProjectRef =
      'havlqebmnjdcwmpaaqew';
  static const String expectedProductionUrl =
      'https://$expectedProductionProjectRef.supabase.co';
  static const String _defaultProjectUrl = expectedProductionUrl;
  static const String _defaultPublishableKey = '';
  static const String _defaultLocalProjectId = '';

  /// The checked-in runtime targets the intended hosted Supabase project.
  /// Local Supabase remains available only through the generated local runtime
  /// file, which opts in explicitly with SUPABASE_ALLOW_LOCAL_DEV=true.
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
      return local.isEmpty ? 'quality_line_erp_local_dev' : local;
    }
    if (host.endsWith('.supabase.co')) {
      return host.substring(0, host.length - '.supabase.co'.length);
    }
    return host.isEmpty ? 'unconfigured_backend' : host;
  }

  static String storageNamespaceFor({
    required String projectUrl,
    String localProjectId = '',
  }) => projectRefFor(
    projectUrl: projectUrl,
    localProjectId: localProjectId,
  ).replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');

  /// Compatibility alias used by older scripts and call sites.
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
      return 'رابط Supabase غير صالح.';
    }
    if (uri.path.isNotEmpty && uri.path != '/') {
      return 'استخدم رابط مشروع Supabase الأساسي فقط، من دون /rest/v1 أو أي مسار إضافي.';
    }

    final host = uri.host.toLowerCase();
    if (_isLoopback(host)) {
      if (!allowLocalDev ||
          uri.scheme != 'http' ||
          !uri.hasPort ||
          uri.port <= 0) {
        return 'Local Supabase غير مفعّل لهذا التشغيل.';
      }
    } else {
      if (uri.scheme != 'https') {
        return 'اتصال Hosted Supabase يجب أن يستخدم HTTPS.';
      }
      if (host != '$expectedProductionProjectRef.supabase.co') {
        return 'رابط Hosted Supabase لا يطابق مشروع KAJ ERP المعتمد.';
      }
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
    return uri.scheme == 'http' && _isLoopback(uri.host);
  }

  static bool isHostedProductionTarget({
    String? projectUrl,
    String? publishableKey,
  }) {
    final resolvedUrl = (projectUrl ?? url).trim();
    final resolvedKey = (publishableKey ?? SupabaseConfig.publishableKey)
        .trim();
    if (validateConfiguration(
          projectUrl: resolvedUrl,
          publishableKey: resolvedKey,
          allowLocalDev: false,
        ) !=
        null) {
      return false;
    }
    final uri = Uri.parse(resolvedUrl);
    return uri.scheme == 'https' &&
        uri.host.toLowerCase() ==
            '$expectedProductionProjectRef.supabase.co';
  }

  static String environmentLabel({
    required bool isArabic,
    String? projectUrl,
    String? publishableKey,
    bool? allowLocalDevelopment,
  }) {
    if (isHostedProductionTarget(
      projectUrl: projectUrl,
      publishableKey: publishableKey,
    )) {
      return isArabic ? 'Supabase الإنتاجي' : 'Production Supabase';
    }
    if (isLocalTarget(
      projectUrl: projectUrl,
      publishableKey: publishableKey,
      allowLocalDevelopment: allowLocalDevelopment,
    )) {
      return isArabic
          ? 'بيئة تطوير Supabase المحلية'
          : 'Local Supabase Development Environment';
    }
    return isArabic ? 'إعداد Supabase مطلوب' : 'Supabase Configuration Required';
  }

  static bool _isLoopback(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1' ||
        normalized.endsWith('.localhost');
  }

  static bool get isConfigured => validateRuntime() == null;
}
