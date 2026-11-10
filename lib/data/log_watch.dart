/// A seeded, coalesced stream over the note log's change events.
library;

import 'dart:async';

/// A stream that emits `compute()` when first listened to (the seed), then
/// again after [changes] fires. Seeding in `onListen` -- rather than lazily in
/// an `async*` body -- avoids a race where a write between `listen` and the
/// first generator tick would swallow the initial snapshot.
///
/// Re-emits are coalesced: the first change of a burst arms one
/// zero-duration timer and every further change before it fires is absorbed,
/// so N back-to-back changes cost ONE `compute()` carrying the latest state
/// instead of N full re-queries (each of which repaints the whole list).
/// The timer fires on the next event-loop turn, so tests stay deterministic
/// under `pumpEventQueue` and the widget tester's `pump`.
Stream<T> watchLog<T>(Stream<void> changes, T Function() compute) {
  StreamSubscription<void>? sub;
  Timer? pending;
  late final StreamController<T> controller;
  controller = StreamController<T>(
    onListen: () {
      controller.add(compute());
      sub = changes.listen((_) {
        pending ??= Timer(Duration.zero, () {
          pending = null;
          controller.add(compute());
        });
      });
    },
    onCancel: () {
      pending?.cancel();
      pending = null;
      return sub?.cancel();
    },
  );
  return controller.stream;
}
