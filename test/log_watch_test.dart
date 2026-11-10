import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/log_watch.dart';

void main() {
  late StreamController<void> changes;
  late int computes;

  setUp(() {
    changes = StreamController<void>.broadcast(sync: true);
    computes = 0;
  });
  tearDown(() => changes.close());

  Stream<int> watch() => watchLog(changes.stream, () => ++computes);

  test('the seed is emitted at once on listen', () async {
    final seen = <int>[];
    final sub = watch().listen(seen.add);
    expect(computes, 1, reason: 'seeded inside listen, not on a timer');
    await pumpEventQueue();
    expect(seen, [1]);
    await sub.cancel();
  });

  test(
    'a burst of 5 changes yields one recompute carrying the latest',
    () async {
      final seen = <int>[];
      final sub = watch().listen(seen.add);
      for (var i = 0; i < 5; i++) {
        changes.add(null);
      }
      expect(computes, 1, reason: 'nothing recomputed inside the burst');
      await pumpEventQueue();
      await sub.cancel();

      expect(computes, 2);
      expect(seen, [1, 2]);
    },
  );

  test('changes after a flush start a new coalescing window', () async {
    final seen = <int>[];
    final sub = watch().listen(seen.add);
    changes.add(null);
    await pumpEventQueue();
    changes.add(null);
    changes.add(null);
    await pumpEventQueue();
    await sub.cancel();

    expect(seen, [1, 2, 3]);
  });

  test(
    'cancel drops a pending recompute and the change subscription',
    () async {
      final sub = watch().listen((_) {});
      changes.add(null);
      await sub.cancel();
      await pumpEventQueue();

      expect(computes, 1);
      expect(changes.hasListener, isFalse);
    },
  );

  test('each listener gets its own stream state', () async {
    final a = <int>[];
    final b = <int>[];
    final subA = watch().listen(a.add);
    final subB = watch().listen(b.add);
    changes.add(null);
    await pumpEventQueue();
    await subA.cancel();
    await subB.cancel();

    expect(a.length, 2);
    expect(b.length, 2);
  });
}
