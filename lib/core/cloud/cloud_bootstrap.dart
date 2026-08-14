import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

class CloudBootstrapResult {
  const CloudBootstrapResult({
    required this.supabaseReady,
    required this.firebaseReady,
    required this.messages,
  });

  final bool supabaseReady;

  /// Firebase Hosting is a deployment target and does not require a runtime SDK.
  final bool firebaseReady;
  final List<String> messages;

  bool get anyReady => supabaseReady;
  bool get hybridReady => supabaseReady;
}

/// Initializes the production backend. Supabase owns authentication, database,
/// storage and realtime. Firebase is used only to host the compiled web build.
class CloudBootstrap {
  CloudBootstrap._();

  static Future<CloudBootstrapResult>? _initialization;
  static CloudBootstrapResult? _lastResult;

  static CloudBootstrapResult? get lastResult => _lastResult;
  static bool get isInitializing =>
      _initialization != null && _lastResult == null;

  static Future<CloudBootstrapResult> initialize({bool retry = false}) {
    if (_lastResult?.supabaseReady == true) {
      return Future<CloudBootstrapResult>.value(_lastResult!);
    }
    if (retry) {
      _initialization = null;
      _lastResult = null;
    }
    return _initialization ??= _initializeOnce();
  }

  /// R57 local-development auth isolation.
  ///
  /// supabase_flutter's default persisted-session key is derived from the URL
  /// host. Multiple Supabase CLI projects on 127.0.0.1 would therefore share
  /// the same browser session key. Give each local project its own namespace.
  /// Hosted Supabase behavior is intentionally unchanged.
  static FlutterAuthClientOptions _r57AuthOptionsForCurrentBackend() {
    final uri = Uri.tryParse(SupabaseConfig.url);
    final host = uri?.host.toLowerCase() ?? '';
    final isLoopback =
        host == '127.0.0.1' ||
        host == 'localhost' ||
        host.endsWith('.localhost');

    if (!isLoopback) {
      return const FlutterAuthClientOptions();
    }

    final configuredProject = SupabaseConfig.localProjectId;
    final project = configuredProject.trim().isEmpty
        ? 'quality_line_erp_local_dev'
        : configuredProject.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');

    return FlutterAuthClientOptions(
      localStorage: SharedPreferencesLocalStorage(
        persistSessionKey: 'kaj-erp-$project-auth-token',
      ),
      detectSessionInUri: false,
    );
  }

  static Future<CloudBootstrapResult> _initializeOnce() async {
    var supabaseReady = false;
    final messages = <String>[];

    if (SupabaseConfig.validate() == null) {
      try {
        await Supabase.initialize(
          url: SupabaseConfig.url,
          publishableKey: SupabaseConfig.anonKey,

          authOptions: _r57AuthOptionsForCurrentBackend(),
        );
        supabaseReady = true;
      } catch (error, stackTrace) {
        messages.add('Supabase: تعذرت التهيئة.');
        AppLogger.error(
          'Supabase initialization failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    } else {
      messages.add('Supabase غير مضبوط في هذه النسخة.');
    }

    final result = CloudBootstrapResult(
      supabaseReady: supabaseReady,
      firebaseReady: true,
      messages: List.unmodifiable(messages),
    );
    _lastResult = result;
    AppLogger.debug(
      'Cloud bootstrap: Supabase=${result.supabaseReady}; hosting=Firebase',
    );
    return result;
  }
}
