import 'dart:async';

/// Result of one production-readiness quality gate.
class QualityGateResult {
  const QualityGateResult({
    required this.name,
    required this.passed,
    required this.duration,
    this.details,
  });

  final String name;
  final bool passed;
  final Duration duration;
  final String? details;
}

/// Executes independent checks without allowing one failure to hide the rest.
class QualityGateRunner {
  const QualityGateRunner();

  Future<List<QualityGateResult>> run(
    Map<String, FutureOr<void> Function()> gates,
  ) async {
    final results = <QualityGateResult>[];
    for (final entry in gates.entries) {
      final stopwatch = Stopwatch()..start();
      try {
        await entry.value();
        stopwatch.stop();
        results.add(
          QualityGateResult(
            name: entry.key,
            passed: true,
            duration: stopwatch.elapsed,
          ),
        );
      } catch (error) {
        stopwatch.stop();
        results.add(
          QualityGateResult(
            name: entry.key,
            passed: false,
            duration: stopwatch.elapsed,
            details: error.toString(),
          ),
        );
      }
    }
    return List<QualityGateResult>.unmodifiable(results);
  }
}
