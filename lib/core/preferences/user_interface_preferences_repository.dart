import 'package:supabase_flutter/supabase_flutter.dart';

import 'user_interface_preferences.dart';

class UserInterfacePreferencesRepository {
  UserInterfacePreferencesRepository(this._client);

  final SupabaseClient _client;

  Future<bool> _hasUsableSession(String userId) async {
    var session = _client.auth.currentSession;
    if (session == null || session.user.id != userId) return false;

    final expiresAt = session.expiresAt;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiresAt != null && expiresAt <= now + 30) {
      try {
        final response = await _client.auth.refreshSession();
        session = response.session;
      } on AuthException {
        return false;
      }
    }
    return session != null && session.user.id == userId;
  }

  Future<UserInterfacePreferences?> fetch(String userId) async {
    if (!await _hasUsableSession(userId)) return null;
    try {
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
    } on PostgrestException catch (error) {
      if (error.code == '401' || error.code == 'PGRST301') return null;
      rethrow;
    }
  }

  Future<void> save(String userId, UserInterfacePreferences preferences) async {
    if (!await _hasUsableSession(userId)) return;
    try {
      await _client
          .from('erp_user_ui_preferences')
          .upsert(preferences.toRemoteMap(userId), onConflict: 'user_id');
    } on PostgrestException catch (error) {
      if (error.code == '401' || error.code == 'PGRST301') return;
      rethrow;
    }
  }
}
