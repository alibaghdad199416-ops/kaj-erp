import 'package:flutter/material.dart';

/// Builds large lists in small increments to keep first paint fast on web.
/// More rows are exposed automatically as the user approaches the end.
class IncrementalListView extends StatefulWidget {
  const IncrementalListView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.separatorBuilder,
    this.padding,
    this.initialItemCount = 36,
    this.loadMoreCount = 36,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final IndexedWidgetBuilder? separatorBuilder;
  final EdgeInsetsGeometry? padding;
  final int initialItemCount;
  final int loadMoreCount;

  @override
  State<IncrementalListView> createState() => _IncrementalListViewState();
}

class _IncrementalListViewState extends State<IncrementalListView> {
  late final ScrollController _controller;
  late int _visibleCount;

  @override
  void initState() {
    super.initState();
    _visibleCount = _boundedInitialCount();
    _controller = ScrollController()..addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant IncrementalListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.itemCount < _visibleCount) {
      _visibleCount = widget.itemCount;
    } else if (oldWidget.itemCount == 0 && widget.itemCount > 0) {
      _visibleCount = _boundedInitialCount();
    }
  }

  int _boundedInitialCount() => widget.itemCount < widget.initialItemCount
      ? widget.itemCount
      : widget.initialItemCount;

  Widget _buildItem(BuildContext context, int index) =>
      RepaintBoundary(child: widget.itemBuilder(context, index));

  void _onScroll() {
    if (!_controller.hasClients || _visibleCount >= widget.itemCount) return;
    if (_controller.position.extentAfter > 900) return;
    final next = (_visibleCount + widget.loadMoreCount)
        .clamp(0, widget.itemCount)
        .toInt();
    if (next != _visibleCount) setState(() => _visibleCount = next);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.separatorBuilder == null) {
      return ListView.builder(
        controller: _controller,
        padding: widget.padding,
        itemCount: _visibleCount,
        semanticChildCount: _visibleCount,
        itemBuilder: _buildItem,
      );
    }
    return ListView.separated(
      controller: _controller,
      padding: widget.padding,
      itemCount: _visibleCount,
      itemBuilder: _buildItem,
      separatorBuilder: widget.separatorBuilder!,
    );
  }
}
