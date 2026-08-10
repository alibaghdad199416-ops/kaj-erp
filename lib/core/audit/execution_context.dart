/// Keeps the authenticated ERP executor available to UI and audit payloads.
/// PostgreSQL audit functions derive the trusted auth identity from Supabase.
class AppExecutionContext {
  AppExecutionContext._();

  static String? userId;
  static String? userName;

  static Future<void> setUser({
    required String id,
    required String name,
  }) async {
    userId = id;
    userName = name;
  }

  static Future<void> clear() async {
    userId = null;
    userName = null;
  }
}
