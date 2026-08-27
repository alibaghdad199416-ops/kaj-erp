class AppReleaseInfo {
  AppReleaseInfo._();

  static const String version = '22.9.8';
  static const int buildNumber = 229008;
  static const String channel = 'final';
  static const String syncEngine =
      '22.9.8-final-cross-stage-integrity-r57-r58-r59-r60';

  static const String operationalRevision =
      '22.9.8-final-cross-stage-integrity-r57-r58-r59-r60';

  static const String releaseToken = 'final-cross-stage-integrity-20260826';

  // Historical audit markers retained for backward-compatible release checks:
  // 18.9.8 / 189800 / v738-full-verified-runtime-accounting-ui-20260806
  static const String legacyV738 =
      '18.9.8+189800-v738-full-verified-runtime-accounting-ui-20260806';

  static String get displayVersion => '$version+$buildNumber';
  static String get runtimeSignature => '$displayVersion/$syncEngine';
}
