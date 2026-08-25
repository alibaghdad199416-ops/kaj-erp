import 'package:flutter/material.dart';

/// A polished, web-friendly transition used consistently between ERP modules.
class LuxuryPageTransitionsBuilder extends PageTransitionsBuilder {
  const LuxuryPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: Tween<double>(begin: .15, end: 1).animate(curved),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(.035, .018),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: .985, end: 1).animate(curved),
          child: child,
        ),
      ),
    );
  }
}
