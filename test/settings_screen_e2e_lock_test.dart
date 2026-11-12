import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/sync/run_sync.dart';

import 'capture_screen_harness.dart' show recordingMock;
import 'settings_screen_harness.dart';

void main() {
  tearDown(() => e2eLocked.value = false);

  testWidgets('the lock tile follows the last sync', (tester) async {
    e2eLocked.value = true;
    await pumpSettings(tester);
    expect(find.byIcon(Icons.lock), findsOneWidget);
    e2eLocked.value = false;
    await tester.pump();
    expect(find.byIcon(Icons.lock_open), findsOneWidget);
  });

  testWidgets('saving a passphrase retries the sync, which unlocks', (
    tester,
  ) async {
    e2eLocked.value = true;
    await pumpSettings(tester, httpClient: recordingMock(<String>[]));
    await tester.tap(find.byIcon(Icons.lock));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'test-passphrase');
    await tester.tap(find.byIcon(Icons.check));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pump();
    expect(e2eLocked.value, isFalse);
  });
}
