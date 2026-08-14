import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:quality_line_erp/core/preferences/app_preferences_controller.dart';
import 'package:quality_line_erp/core/preferences/user_interface_preferences.dart';
import 'package:quality_line_erp/core/preferences/user_interface_preferences_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('equal preference writes do not repeat the remote upsert', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'kaj_v4_visual_layout_applied.user-a': true,
    });
    const value = UserInterfacePreferences(
      localeCode: 'en',
      themeMode: ThemeMode.dark,
      navigationPosition: AppNavigationPosition.side,
      sideNavigationCollapsed: false,
      favoriteRoutes: <String>{},
      collapsedNavigationGroups: <String>{},
      sideNavigationScrollOffset: 24,
    );
    final remote = _FakeRemoteStore()..fetchResults.add(value);
    final controller = _controller(remote, userId: 'user-a');

    await controller.synchronizeForCurrentUser();
    await controller.setSideNavigationScrollOffset(24);
    await controller.setThemeMode(ThemeMode.dark);

    expect(remote.saved, isEmpty);
  });

  test('a changed preference is persisted once for its owning user', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'kaj_v4_visual_layout_applied.user-a': true,
    });
    final remote = _FakeRemoteStore()
      ..fetchResults.add(UserInterfacePreferences.defaults());
    final controller = _controller(remote, userId: 'user-a');

    await controller.synchronizeForCurrentUser();
    await controller.setThemeMode(ThemeMode.light);
    await controller.setThemeMode(ThemeMode.light);

    expect(remote.saved, hasLength(1));
    expect(remote.saved.single.$1, 'user-a');
    expect(remote.saved.single.$2.themeMode, ThemeMode.light);
  });

  test(
    'final scroll state stays with the active user after account switch',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'kaj_v4_visual_layout_applied.user-a': true,
        'kaj_v4_visual_layout_applied.user-b': true,
      });
      var userId = 'user-a';
      final remote = _FakeRemoteStore()
        ..fetchResults.add(UserInterfacePreferences.defaults())
        ..fetchResults.add(UserInterfacePreferences.defaults());
      final controller = AppPreferencesController(
        repositoryForTesting: remote,
        currentUserIdForTesting: () => userId,
      );

      await controller.synchronizeForCurrentUser();
      await controller.setSideNavigationScrollOffset(18);
      userId = 'user-b';
      await controller.synchronizeForCurrentUser();
      await controller.setSideNavigationScrollOffset(37);

      expect(remote.saved, hasLength(2));
      expect(remote.saved[0].$1, 'user-a');
      expect(remote.saved[0].$2.sideNavigationScrollOffset, 18);
      expect(remote.saved[1].$1, 'user-b');
      expect(remote.saved[1].$2.sideNavigationScrollOffset, 37);
    },
  );

  test('successful no-row fetch may create the remote snapshot', () async {
    final remote = _FakeRemoteStore()..fetchResults.add(null);
    final controller = _controller(remote, userId: 'user-a');

    await controller.synchronizeForCurrentUser();

    expect(remote.fetchCalls, 1);
    expect(remote.saved, hasLength(1));
    expect(remote.saved.single.$1, 'user-a');
  });

  test('authorization failure never becomes a missing-row save', () async {
    final remote = _FakeRemoteStore()
      ..fetchResults.add(
        const PostgrestException(message: 'Invalid JWT', code: 'PGRST301'),
      );
    final controller = _controller(remote, userId: 'user-a');

    await controller.synchronizeForCurrentUser();

    expect(remote.saved, isEmpty);
  });

  test('transient fetch failure never triggers fallback remote save', () async {
    final remote = _FakeRemoteStore()
      ..fetchResults.add(TimeoutException('temporary server delay'));
    final controller = _controller(remote, userId: 'user-a');

    await controller.synchronizeForCurrentUser();

    expect(remote.saved, isEmpty);
  });

  test('explicit sync follows an early failed same-user activation', () async {
    final firstFetch = Completer<UserInterfacePreferences?>();
    final remote = _FakeRemoteStore()
      ..fetchResults.add(firstFetch.future)
      ..fetchResults.add(
        const UserInterfacePreferences(
          localeCode: 'ar',
          themeMode: ThemeMode.light,
          navigationPosition: AppNavigationPosition.top,
          sideNavigationCollapsed: false,
          favoriteRoutes: <String>{'/sales'},
          collapsedNavigationGroups: <String>{},
          sideNavigationScrollOffset: 0,
        ),
      );
    final controller = _controller(remote, userId: 'user-a');
    final early = controller.load();
    final explicit = controller.synchronizeForCurrentUser();
    while (remote.fetchCalls == 0) {
      await Future<void>.delayed(Duration.zero);
    }
    firstFetch.completeError(TimeoutException('early auth race'));

    await early;
    await explicit;

    expect(remote.fetchCalls, 2);
    expect(controller.locale.languageCode, 'ar');
    expect(controller.favoriteRoutes, contains('/sales'));
  });

  test('successful remote values continue to replace local values', () async {
    final remote = _FakeRemoteStore()
      ..fetchResults.add(
        const UserInterfacePreferences(
          localeCode: 'ar',
          themeMode: ThemeMode.light,
          navigationPosition: AppNavigationPosition.top,
          sideNavigationCollapsed: true,
          favoriteRoutes: <String>{'/inventory'},
          collapsedNavigationGroups: <String>{'accounting'},
          sideNavigationScrollOffset: 42,
        ),
      );
    final controller = _controller(remote, userId: 'user-a');

    await controller.synchronizeForCurrentUser();

    expect(controller.locale.languageCode, 'ar');
    expect(controller.favoriteRoutes, contains('/inventory'));
    expect(controller.sideNavigationScrollOffset, 42);
  });

  test(
    'guest preferences remain local and never touch remote storage',
    () async {
      final remote = _FakeRemoteStore();
      final controller = _controller(remote, userId: null);

      await controller.useGuestPreferences();

      expect(controller.activeUserId, isNull);
      expect(remote.fetchCalls, 0);
      expect(remote.saved, isEmpty);
    },
  );
}

AppPreferencesController _controller(
  _FakeRemoteStore remote, {
  required String? userId,
}) => AppPreferencesController(
  repositoryForTesting: remote,
  currentUserIdForTesting: () => userId,
);

class _FakeRemoteStore implements UserInterfacePreferencesRemoteStore {
  final List<Object?> fetchResults = <Object?>[];
  final List<(String, UserInterfacePreferences)> saved = [];
  int fetchCalls = 0;

  @override
  Future<UserInterfacePreferences?> fetch(String userId) async {
    final result = fetchResults[fetchCalls++];
    if (result is Future<UserInterfacePreferences?>) return result;
    if (result is Object && result is! UserInterfacePreferences) throw result;
    return result as UserInterfacePreferences?;
  }

  @override
  Future<void> save(String userId, UserInterfacePreferences preferences) async {
    saved.add((userId, preferences));
  }
}
