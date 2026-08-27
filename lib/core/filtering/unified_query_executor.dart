export 'unified_filter_engine.dart';

import 'unified_filter_engine.dart';
import 'unified_query.dart';

/// Executes a complete module query in one deterministic pipeline.
///
/// The adapter remains module-specific while query state, filtering lifecycle,
/// and multi-sort ordering stay shared across ERP list screens.
class UnifiedQueryExecutor<T> {
  const UnifiedQueryExecutor({
    required this.criteriaBuilder,
    required this.filterAdapter,
    required this.sort,
  });

  final UnifiedFilterCriteria Function(UnifiedQueryState state) criteriaBuilder;
  final UnifiedFilterAdapter<T> filterAdapter;
  final int Function(T left, T right, String field) sort;

  List<T> execute(Iterable<T> values, UnifiedQueryState state) {
    final result = UnifiedFilterEngine.apply<T>(
      values,
      criteria: criteriaBuilder(state),
      adapter: filterAdapter,
    ).toList();

    result.sort((left, right) {
      for (final rule in state.sorts) {
        final comparison = sort(left, right, rule.field);
        if (comparison != 0) {
          return rule.descending ? -comparison : comparison;
        }
      }
      return 0;
    });
    return result;
  }
}
