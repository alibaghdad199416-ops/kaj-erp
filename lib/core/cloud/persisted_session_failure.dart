import 'package:supabase_flutter/supabase_flutter.dart';

/// Classifies only failures that prove persisted browser credentials are no
/// longer usable. Connectivity and server availability errors deliberately
/// remain unclassified so a potentially valid session is preserved.
bool isInvalidPersistedAuthFailure(Object error) {
  if (error is AuthSessionMissingException ||
      error is AuthRetryableFetchException) {
    return false;
  }
  if (error is AuthInvalidJwtException) return true;
  if (error is AuthException) {
    return _hasInvalidAuthEvidence(
      code: error.code,
      statusCode: error.statusCode,
      text: error.message,
    );
  }
  if (error is PostgrestException) {
    return _hasInvalidAuthEvidence(
      code: error.code,
      text: '${error.message} ${error.details ?? ''} ${error.hint ?? ''}',
    );
  }
  return false;
}

bool _hasInvalidAuthEvidence({
  String? code,
  String? statusCode,
  required String text,
}) {
  final normalizedCode = (code ?? '').trim().toLowerCase();
  final normalizedStatus = (statusCode ?? '').trim();
  final normalizedText = text.toLowerCase();
  const invalidCodes = <String>{
    'invalid_jwt',
    'bad_jwt',
    'refresh_token_not_found',
    'refresh_token_already_used',
    'pgrst301',
    'pgrst302',
    '401',
  };
  if (invalidCodes.contains(normalizedCode) || normalizedStatus == '401') {
    return true;
  }
  return const <String>[
    'invalid jwt',
    'bad_jwt',
    'jwt expired',
    'expired jwt',
    'invalid refresh token',
    'refresh token not found',
    'refresh token has already been used',
  ].any(normalizedText.contains);
}
