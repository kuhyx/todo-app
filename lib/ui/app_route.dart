/// The one page route every screen is pushed with.
library;

import 'package:material_ui/material_ui.dart';

/// A route for [builder] that switches screens instantly: no fade, no slide.
///
/// Without a GPU the desktop web build repaints the whole 4K canvas in
/// software on every frame, so a 320 ms transition cost ~600 ms of main
/// thread and a 260-300 ms frame stall on every tab switch and note open.
/// The same instant switch applies on the phone. The context is unused but
/// kept so every call site stays as it was.
///
/// [name] is a route pattern (`/notes/detail`), never an id or a title: the
/// app-errors reporter stamps it on every report made on that screen.
Route<T> appRoute<T>(BuildContext _, WidgetBuilder builder, {String? name}) =>
    _AppPageRoute<T>(
      builder: builder,
      settings: RouteSettings(name: name),
    );

class _AppPageRoute<T> extends MaterialPageRoute<T> {
  _AppPageRoute({required super.builder, super.settings});

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
