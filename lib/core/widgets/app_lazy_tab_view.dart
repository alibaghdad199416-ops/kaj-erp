import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Lazily builds module tabs and keeps already visited tabs alive.
///
/// Flutter's regular [TabBarView] may build neighbouring heavy ERP pages. That
/// caused cars, products, warehouses, partners, sales and purchases to issue
/// database queries before the user opened them. This view builds only the
/// selected tab, then preserves it in an [IndexedStack].
class AppLazyTabView extends StatefulWidget {
  const AppLazyTabView({super.key, required this.children});

  final List<Widget> children;

  @override
  State<AppLazyTabView> createState() => _AppLazyTabViewState();
}

class _AppLazyTabViewState extends State<AppLazyTabView> {
  TabController? _controller;
  final Set<int> _visited = <int>{};
  int _selectedIndex = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = DefaultTabController.maybeOf(context);
    if (identical(next, _controller)) return;
    _controller?.removeListener(_handleTabChanged);
    _controller = next;
    _controller?.addListener(_handleTabChanged);
    final index = _safeIndex(_controller?.index ?? 0);
    _selectedIndex = index;
    _visited.add(index);
  }

  @override
  void didUpdateWidget(covariant AppLazyTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _visited.removeWhere((index) => index >= widget.children.length);
    _visited.add(_safeIndex(_controller?.index ?? 0));
  }

  int _safeIndex(int index) {
    if (widget.children.isEmpty) return 0;
    return index.clamp(0, widget.children.length - 1).toInt();
  }

  void _handleTabChanged() {
    if (!mounted || widget.children.isEmpty) return;
    final index = _safeIndex(_controller?.index ?? 0);

    void applySelection() {
      if (!mounted) return;
      final selectionChanged = index != _selectedIndex;
      final newlyVisited = !_visited.contains(index);
      if (!selectionChanged && !newlyVisited) return;
      setState(() {
        _selectedIndex = index;
        _visited.add(index);
      });
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => applySelection());
    } else {
      applySelection();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_handleTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();
    final selected = _safeIndex(_controller?.index ?? _selectedIndex);
    return IndexedStack(
      index: selected,
      children: List<Widget>.generate(widget.children.length, (index) {
        if (index != selected && !_visited.contains(index)) {
          return const SizedBox.shrink();
        }
        return KeyedSubtree(
          key: ValueKey<String>('lazy-module-tab-$index'),
          child: widget.children[index],
        );
      }, growable: false),
    );
  }
}
