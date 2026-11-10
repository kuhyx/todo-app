/// A seeded stream over the note log's change events.
library;

import 'dart:async';

/// A stream that emits `compute()` synchronously when first listened to (the
/// seed), then again on every event of [changes]. Seeding in `onListen` --
/// rather than lazily in an `async*` body -- avoids a race where a write
/// between `listen` and the first generator tick would swallow the initial
/// snapshot.
Stream<T> watchLog<T>(Stream<void> changes, T Function() compute) {
  StreamSubscription<void>? sub;
  late final StreamController<T> controller;
  controller = StreamController<T>(
    onListen: () {
      controller.add(compute());
      sub = changes.listen((_) => controller.add(compute()));
    },
    onCancel: () => sub?.cancel(),
  );
  return controller.stream;
}
