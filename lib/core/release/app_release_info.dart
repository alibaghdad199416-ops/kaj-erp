class AppReleaseInfo {
  AppReleaseInfo._();

  static const String version = '22.9.8';
  static const int buildNumber = 229008;
  static const String channel = 'release-candidate';

  // R49 release identity is retained for historical validation and package
  // compatibility. It is not the current runtime cache/deployment identity.
  static const String syncEngine = '22.9.8-r49-focused-final-completion';
  static const String operationalRevision =
      '22.9.8-r49-focused-final-completion';
  static const String releaseToken = 'r49-focused-final-completion-20260810';

  // Current source/runtime identity. R74 adds authenticated user+tenant
  // attestation and invalidates the earlier project-only tenant cache.
  static const String currentRuntimeRevision =
      'r74-authenticated-tenant-runtime';
  static const String currentRuntimeToken =
      'r74-authenticated-tenant-runtime-20260815';

  // Historical audit markers retained for backward-compatible release checks:
  // 18.9.8 / 189800 / v738-full-verified-runtime-accounting-ui-20260806
  static const String legacyV738 =
      '18.9.8+189800-v738-full-verified-runtime-accounting-ui-20260806';

  static String get displayVersion => '$version+$buildNumber';
  static String get runtimeSignature => '$displayVersion/$currentRuntimeToken';
}
