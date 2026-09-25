import 'package:flutter/widgets.dart';

import 'package:todo/attachments/image_store_api.dart';

/// Makes the app's one [ImageStore] reachable from any widget below it,
/// without threading it through every screen constructor.
///
/// Screens built without a scope (most widget tests) get a shared
/// [NoImageStore], so they render and simply cannot attach.
class ImageStoreScope extends InheritedNotifier<ImageStore> {
  /// Provides [store] to [child].
  const ImageStoreScope({
    required ImageStore store,
    required super.child,
    super.key,
  }) : super(notifier: store);

  static final ImageStore _none = NoImageStore();

  /// The nearest store, subscribing [context] to its changes.
  static ImageStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ImageStoreScope>()?.notifier ??
      _none;

  /// The nearest store, without subscribing (for callbacks).
  static ImageStore read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ImageStoreScope>()?.notifier ??
      _none;
}
