import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note.dart';
import 'package:todo/ui/image_input.dart';
import 'package:todo/ui/images/image_strip.dart';

import '../capture_screen_harness.dart';
import '../fake_image_store.dart';

void main() {
  testWidgets('📎 on an empty draft creates the note under the image id', (
    tester,
  ) async {
    final store = FakeImageStore();
    final repo = await pumpCapture(
      tester,
      imageStore: store,
      imagePicking: (_) async => [
        Uint8List.fromList([1]),
      ],
      appSettings: ValueNotifier(const AppSettings(advancedMode: false)),
    );
    await tester.tap(find.byTooltip('Attach image'));
    await tester.pump();
    await tester.pump();
    final ref = store.attached.keys.single;
    final notes = await repo.listNotes();
    expect(notes.single.id, ref.noteId);
    expect(notes.single.text, contains(ref.markdown));
    expect(find.byType(ImageStrip), findsOneWidget);
  });

  testWidgets('📎 on a started draft files under that note', (tester) async {
    final store = FakeImageStore();
    final repo = await pumpCapture(
      tester,
      imageStore: store,
      imagePicking: (_) async => [
        Uint8List.fromList([1]),
      ],
      appSettings: ValueNotifier(const AppSettings(advancedMode: false)),
    );
    await tester.enterText(find.byType(TextField), 'idea');
    await tester.pump();
    final id = (await repo.listNotes()).single.id;
    await tester.tap(find.byTooltip('Attach image'));
    await tester.pump();
    await tester.pump();
    expect(store.attached.keys.single.noteId, id);
    expect((await repo.listNotes()).single.text, startsWith('idea\n![]('));
  });

  testWidgets('launch and resume reconcile with every note', (tester) async {
    final store = FakeImageStore();
    await pumpCapture(
      tester,
      imageStore: store,
      seed: [
        Note(
          id: 'a',
          text: 'one',
          priority: Priority.medium,
          status: Status.done,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ],
    );
    await tester.pump();
    expect(store.reconciles, isNotEmpty);
    expect(store.reconciles.last, ['one']);
    final before = store.reconciles.length;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(store.reconciles.length, before + 1);
  });

  testWidgets('a manual sync reconciles images after it', (tester) async {
    final store = FakeImageStore();
    await pumpCapture(
      tester,
      imageStore: store,
      prefs: configuredPrefs,
      httpClient: recordingMock([]),
    );
    await tester.pump();
    final before = store.reconciles.length;
    await tester.tap(find.byTooltip('Sync'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(store.reconciles.length, greaterThan(before));
  });

  testWidgets('a paste or drop attaches to the draft', (tester) async {
    final store = FakeImageStore();
    final repo = await pumpCapture(
      tester,
      imageStore: store,
      appSettings: ValueNotifier(const AppSettings(advancedMode: false)),
    );
    tester.widget<ImageInputListener>(find.byType(ImageInputListener)).onImages(
      [
        Uint8List.fromList([1]),
      ],
      1,
    );
    await tester.pump();
    await tester.pump();
    expect(store.attached, hasLength(1));
    expect(
      (await repo.listNotes()).single.id,
      store.attached.keys.single.noteId,
    );
    expect(find.text('Not an image'), findsOneWidget);
  });
}
