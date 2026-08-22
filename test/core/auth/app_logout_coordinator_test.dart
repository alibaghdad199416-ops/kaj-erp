import 'package:flutter_test/flutter_test.dart';
import 'package:quality_line_erp/core/auth/app_logout_coordinator.dart';

void main() {
  test('logout clears the Supabase session before login navigation', () async {
    final operations = <String>[];

    await AppLogoutCoordinator.run(
      clearAuthenticatedSession: () async => operations.add('session'),
      activateGuestPreferences: () async => operations.add('preferences'),
      navigateToLogin: () async => operations.add('navigation'),
      isMounted: () => true,
    );

    expect(operations, ['session', 'preferences', 'navigation']);
  });

  test('logout never navigates after its widget is disposed', () async {
    final operations = <String>[];

    await AppLogoutCoordinator.run(
      clearAuthenticatedSession: () async => operations.add('session'),
      activateGuestPreferences: () async => operations.add('preferences'),
      navigateToLogin: () async => operations.add('navigation'),
      isMounted: () => false,
    );

    expect(operations, ['session']);
  });
}
