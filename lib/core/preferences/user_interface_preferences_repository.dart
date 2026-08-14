import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_interface_preferences.dart';

abstract interface class UserInterfacePreferencesRemoteStore {
  Future<UserInterfacePreferences?> fetch(String userId);
  Future<void> save(String userId, UserInterfacePreferences preferences);
}

class UserPreferencesSessionUnavailable implements Exception {
  const UserPreferencesSessionUnavailable();

  @override
  String toString() => 'User preferences session is not ready.';
}

class UserInterfacePreferencesRepository
    implements UserInterfacePreferencesRemoteStore {
  UserInterfacePreferencesRepository(this._client);

  final SupabaseClient _client;

  Future<void> _requireUsableSession(String userId) async {
    var session = _client.auth.currentSession;
    if (session == null || session.user.id != userId) {
      throw const UserPreferencesSessionUnavailable();
    }

    final expiresAt = session.expiresAt;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiresAt != null && expiresAt <= now + 30) {
      final response = await _client.auth.refreshSession();
      session = response.session;
    }
    if (session == null || session.user.id != userId) {
      throw const UserPreferencesSessionUnavailable();
    }
  }

  @override
  Future<UserInterfacePreferences?> fetch(String userId) async {
    await _requireUsableSession(userId);
    final row = await _client
        .from('erp_user_ui_preferences')
        .select(
          'locale_code,theme_mode,navigation_position,'
          'side_navigation_collapsed,favorite_routes,'
          'collapsed_navigation_groups,side_navigation_scroll_offset',
        )
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return UserInterfacePreferences.fromMap(row);
  }

  @override
  Future<void> save(String userId, UserInterfacePreferences preferences) async {
    await _requireUsableSession(userId);
    await _client
        .from('erp_user_ui_preferences')
        .upsert(preferences.toRemoteMap(userId), onConflict: 'user_id');
  }
}
