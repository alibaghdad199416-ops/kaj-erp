import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Preserves the PostgreSQL/PostgREST diagnostics that are otherwise lost
/// behind a generic workflow failure message.
class WorkflowOperationException implements Exception {
  const WorkflowOperationException({
    required this.operation,
    required this.message,
    this.code,
    this.details,
    this.hint,
  });

  final String operation;
  final String message;
  final String? code;
  final String? details;
  final String? hint;

  factory WorkflowOperationException.fromPostgrest(
    String operation,
    PostgrestException error,
  ) {
    return WorkflowOperationException(
      operation: operation,
      message: error.message,
      code: error.code,
      details: error.details?.toString(),
      hint: error.hint?.toString(),
    );
  }

  String localizedMessage({required bool isArabic}) {
    final diagnostic = <String>[
      if (code != null && code!.trim().isNotEmpty) '[$code]',
      message,
      if (details != null && details!.trim().isNotEmpty) details!,
      if (hint != null && hint!.trim().isNotEmpty) hint!,
    ].join(' — ');
    return isArabic
        ? 'تعذر تنفيذ العملية ($operation): $diagnostic'
        : 'Unable to complete $operation: $diagnostic';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'operation': operation,
    'message': message,
    'code': code,
    'details': details,
    'hint': hint,
  };

  @override
  String toString() => jsonEncode(toJson());
}
