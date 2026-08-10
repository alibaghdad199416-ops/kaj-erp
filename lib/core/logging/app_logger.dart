import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Centralized, release-safe application logging.
///
/// Debug and informational messages are compiled out of production output.
/// Warnings and errors remain available without exposing full object dumps.
class AppLogger {
  const AppLogger._();

  static const int _maxMessageLength = 1200;

  static void debug(Object? message) {
    if (!kDebugMode) return;
    _write('DEBUG', message);
  }

  static void info(Object? message) {
    if (!kDebugMode) return;
    _write('INFO', message);
  }

  static void warning(Object? message) {
    _write('WARN', message);
  }

  static void error(Object? message, {Object? error, StackTrace? stackTrace}) {
    final details = error == null ? message : '$message: $error';
    _write('ERROR', details);
    if (stackTrace != null && kDebugMode) {
      developer.log(
        details.toString(),
        name: 'QualityLineERP',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static void stack(StackTrace? stackTrace) {
    if (!kDebugMode || stackTrace == null) return;
    developer.log(
      'Stack trace',
      name: 'QualityLineERP',
      level: 500,
      stackTrace: stackTrace,
    );
  }

  static void _write(String level, Object? message) {
    final normalized =
        message?.toString().replaceAll(RegExp(r'[\r\n]+'), ' ') ?? '';
    final safeMessage = normalized.length <= _maxMessageLength
        ? normalized
        : '${normalized.substring(0, _maxMessageLength)}…';
    developer.log(
      safeMessage,
      name: 'QualityLineERP',
      level: _developerLevel(level),
    );
  }

  static int _developerLevel(String level) {
    return switch (level) {
      'ERROR' => 1000,
      'WARN' => 900,
      'INFO' => 800,
      _ => 500,
    };
  }
}
