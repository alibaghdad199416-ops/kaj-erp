import 'dart:async';

import 'package:quality_line_erp/core/logging/app_logger.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'persisted_session_failure.dart';
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

  /// Browser authentication is namespaced by the actual Supabase project for
  /// both hosted and local runtimes. The earlier runtime only isolated local
  /// CLI projects, which allowed a persisted hosted session to survive backend
  /// configuration changes and restore the wrong company context.
  static FlutterAuthClientOptions _authOptionsForCurrentBackend() {
    final uri = Uri.tryParse(SupabaseConfig.url);
    final host = uri?.host.toLowerCase() ?? '';
    final isLoopback =
        host == '127.0.0.1' ||
        host == 'localhost' ||
        host.endsWith('.localhost');
    final localStorage = SharedPreferencesLocalStorage(
      persistSessionKey: SupabaseConfig.authPersistSessionKey,
    );

    if (isLoopback) {
      return FlutterAuthClientOptions(
        localStorage: localStorage,
        detectSessionInUri: false,
      );
    }
    return FlutterAuthClientOptions(localStorage: localStorage);
  }

  /// Validate any restored browser credential against the backend that was
  /// actually initialized. A project-scoped storage key prevents most leakage,
  /// but an already-populated invalid token must still fail closed before any
  /// tenant or preferences request is allowed to reuse it.
  static Future<void> _verifyPersistedSessionForCurrentBackend() async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session == null) return;

    try {
      final response = await client.auth.getUser().timeout(
        const Duration(seconds: 12),
      );
      final verified = response.user;
      if (verified == null || verified.id != session.user.id) {
        throw const AuthInvalidJwtException('Persisted user identity mismatch');
      }
      AppLogger.debug(
        'R74 persisted Supabase session verified: '
        'project=${SupabaseConfig.projectRef}; user=${verified.id}',
      );
    } on TimeoutException catch (error, stackTrace) {
      // A timeout proves neither validity nor invalidity. Preserve the token and
      // let the normal authenticated bootstrap make the final decision.
      AppLogger.debug(
        'Persisted Supabase session verification timed out; preserving session: '
        '$error',
      );
      AppLogger.stack(stackTrace);
    } catch (error, stackTrace) {
      if (!isInvalidPersistedAuthFailure(error)) {
        AppLogger.debug(
          'Persisted Supabase session could not be verified yet; preserving it: '
          '$error',
        );
        AppLogger.stack(stackTrace);
        return;
      }
      AppLogger.debug(
        'R74 discarding invalid persisted Supabase session for '
        '${SupabaseConfig.projectRef}: $error',
      );
      AppLogger.stack(stackTrace);
      try {
        await client.auth.signOut(scope: SignOutScope.local).timeout(
          const Duration(seconds: 8),
        );
      } catch (cleanupError, cleanupStack) {
        AppLogger.debug(
          'R74 invalid persisted-session cleanup skipped: $cleanupError',
        );
        AppLogger.stack(cleanupStack);
      }
    }
  }

  static Future<CloudBootstrapResult> _initializeOnce() async {
    var supabaseReady = false;
    final messages = <String>[];
    final configurationError = SupabaseConfig.validateRuntime();

    if (configurationError == null) {
      try {
        AppLogger.debug(
          'Supabase bootstrap target: ${SupabaseConfig.projectRef}; '
          'authStorage=${SupabaseConfig.authPersistSessionKey}',
        );
        await Supabase.initialize(
          url: SupabaseConfig.url,
          publishableKey: SupabaseConfig.anonKey,
          authOptions: _authOptionsForCurrentBackend(),
        );
        await _verifyPersistedSessionForCurrentBackend();
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
      messages.add(configurationError);
      AppLogger.debug(
        'Supabase runtime configuration rejected: $configurationError; '
        'project=${SupabaseConfig.projectRef}',
      );
    }

    final result = CloudBootstrapResult(
      supabaseReady: supabaseReady,
      firebaseReady: true,
      messages: List.unmodifiable(messages),
    );
    _lastResult = result;
    AppLogger.debug(
      'Cloud bootstrap: Supabase=${result.supabaseReady}; '
      'project=${SupabaseConfig.projectRef}; hosting=Firebase',
    );
    return result;
  }
}
