/// The one page route every screen is pushed with, on the shared motion tokens.
library;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:todo/ui/motion.dart';

/// A route for [builder]: fade plus a short rise over [AppDuration.slow],
/// instant under the OS "remove animations" setting.
Route<T> appRoute<T>(BuildContext context, WidgetBuilder builder) =>
    _AppPageRoute<T>(
      builder: builder,
      duration: motionDuration(context, AppDuration.slow),
    );

class _AppPageRoute<T> extends MaterialPageRoute<T> {
  _AppPageRoute({required super.builder, required this.duration});

  final Duration duration;

  @override
  Duration get transitionDuration => duration;

  @override
  Duration get reverseTransitionDuration => duration;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enter = CurvedAnimation(
      parent: animation,
      curve: AppCurve.decelerate,
      reverseCurve: AppCurve.accelerate,
    );
    return FadeTransition(
      opacity: enter,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(enter),
        child: child,
      ),
    );
  }
}
