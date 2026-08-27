import 'unified_filter_engine.dart';
import 'unified_query.dart';

/// Executes a complete module query in one deterministic pipeline.
///
/// The filter adapter remains module-specific; sorting is described by the
/// caller so the shared query state can support different ERP entities without
/// introducing model-specific dependencies into the core layer.
class UnifiedQueryExecutor<T> {
  const UnifiedQueryExecutor({required this.filterAdapter, required this.sort});

  final UnifiedFilterAdapter<T> filterAdapter;
  final int Function(T left, T right, String field) sort;

  List<T> execute(Iterable<T> values, UnifiedQueryState state) {
    final result = UnifiedFilterEngine.apply<T>(
      values,
      criteria: UnifiedFilterCriteria(searchText: state.search),
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
