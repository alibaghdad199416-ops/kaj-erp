class AppLogoutCoordinator {
  const AppLogoutCoordinator._();

  static Future<void> run({
    required Future<void> Function() clearAuthenticatedSession,
    required Future<void> Function() activateGuestPreferences,
    required Future<void> Function() navigateToLogin,
    required bool Function() isMounted,
  }) async {
    await clearAuthenticatedSession();
    if (!isMounted()) return;

    await activateGuestPreferences();
    if (!isMounted()) return;

    await navigateToLogin();
  }
}
