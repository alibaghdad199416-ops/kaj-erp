import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/cloud/persisted_session_failure.dart';
import 'package:quality_line_erp/features/settings/access/controllers/access_controller.dart';

void main() {
  test('bad_jwt and invalid JWT failures prove persisted auth is invalid', () {
    expect(
      isInvalidPersistedAuthFailure(
        const PostgrestException(message: 'Invalid JWT', code: 'bad_jwt'),
      ),
      isTrue,
    );
    expect(
      isInvalidPersistedAuthFailure(AuthInvalidJwtException('JWT expired')),
      isTrue,
    );
  });

  test('invalid persisted auth is cleaned and returns false', () async {
    var cleanupCalls = 0;
    final controller = AccessController(
      persistedSessionRestoreForTesting: () async =>
          throw const PostgrestException(
            message: 'Invalid JWT',
            code: 'PGRST301',
          ),
      invalidSessionCleanupForTesting: () async => cleanupCalls += 1,
    );

    expect(await controller.restorePersistedSession(), isFalse);
    expect(cleanupCalls, 1);
  });

  test('transient failures preserve the potentially valid session', () async {
    for (final error in <Object>[
      TimeoutException('temporary timeout'),
      AuthRetryableFetchException(message: 'network unavailable'),
      const PostgrestException(message: 'Service unavailable', code: '503'),
    ]) {
      var cleanupCalls = 0;
      final controller = AccessController(
        persistedSessionRestoreForTesting: () async => throw error,
        invalidSessionCleanupForTesting: () async => cleanupCalls += 1,
      );
      expect(await controller.restorePersistedSession(), isFalse);
      expect(cleanupCalls, 0);
    }
  });

  test('normal no-session result stays false without cleanup', () async {
    var cleanupCalls = 0;
    final controller = AccessController(
      persistedSessionRestoreForTesting: () async => false,
      invalidSessionCleanupForTesting: () async => cleanupCalls += 1,
    );
    expect(await controller.restorePersistedSession(), isFalse);
    expect(cleanupCalls, 0);
  });

  test('valid persisted-session fast path remains true', () async {
    var cleanupCalls = 0;
    final controller = AccessController(
      persistedSessionRestoreForTesting: () async => true,
      invalidSessionCleanupForTesting: () async => cleanupCalls += 1,
    );
    expect(await controller.restorePersistedSession(), isTrue);
    expect(cleanupCalls, 0);
  });
}
