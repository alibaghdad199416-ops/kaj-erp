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

  // Current source/runtime identity. Phase 11 R94 closes inherited PUBLIC
  // execution on low-level legacy RPCs; R93 and R74 remain historical markers.
  static const String currentRuntimeRevision = 'r94-legacy-acl-runtime-closure';
  static const String currentRuntimeToken =
      'r94-legacy-acl-runtime-closure-20260820';
  static const String databaseContract = 'R94';

  // Historical audit markers retained for backward-compatible release checks:
  // 18.9.8 / 189800 / v738-full-verified-runtime-accounting-ui-20260806
  static const String legacyV738 =
      '18.9.8+189800-v738-full-verified-runtime-accounting-ui-20260806';

  static String get displayVersion => '$version+$buildNumber';
  static String get runtimeSignature => '$displayVersion/$currentRuntimeToken';
}
