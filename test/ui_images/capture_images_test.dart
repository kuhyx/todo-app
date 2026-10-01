import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note.dart';
import 'package:todo/ui/attachment_picking.dart';
import 'package:todo/ui/image_input.dart';
import 'package:todo/ui/images/attachment_strip.dart';

import '../capture_screen_harness.dart';
import '../fake_image_store.dart';

void main() {
  testWidgets('📎 on an empty draft creates the note under the file id', (
    tester,
  ) async {
    final store = FakeImageStore();
    final repo = await pumpCapture(
      tester,
      imageStore: store,
      attachmentPicking: (_) async => [
        XFile('/picked/shot.png'),
        XFile('/picked/Raport.pdf'),
      ],
      appSettings: ValueNotifier(const AppSettings(advancedMode: false)),
    );
    await tester.tap(find.byTooltip('Attach'));
    await tester.pump();
    await tester.pump();
    expect(store.attachedFiles, hasLength(2));
    final notes = await repo.listNotes();
    expect(notes.single.text, contains('![]('));
    expect(notes.single.text, contains('[Raport.pdf]('));
    expect(notes.single.text, contains('/${notes.single.id}/'));
    expect(find.byType(AttachmentStrip), findsOneWidget);
  });

  testWidgets('📎 on a started draft files under that note', (tester) async {
    final store = FakeImageStore();
    final repo = await pumpCapture(
      tester,
      imageStore: store,
      attachmentPicking: (_) async => [XFile('/picked/a.pdf')],
      appSettings: ValueNotifier(const AppSettings(advancedMode: false)),
    );
    await tester.enterText(find.byType(TextField), 'idea');
    await tester.pump();
    final id = (await repo.listNotes()).single.id;
    await tester.tap(find.byTooltip('Attach'));
    await tester.pump();
    await tester.pump();
    final text = (await repo.listNotes()).single.text;
    expect(text, startsWith('idea\n[a.pdf]('));
    expect(text, contains('/$id/'));
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

  testWidgets('a drop attaches any file to the draft', (tester) async {
    final store = FakeImageStore();
    final repo = await pumpCapture(
      tester,
      imageStore: store,
      appSettings: ValueNotifier(const AppSettings(advancedMode: false)),
    );
    tester.widget<ImageInputListener>(find.byType(ImageInputListener)).onFiles([
      XFile('/dropped/clip.mp4'),
    ]);
    await tester.pump();
    await tester.pump();
    expect(store.attachedFiles.single.name, 'clip.mp4');
    expect((await repo.listNotes()).single.text, contains('[clip.mp4]('));
  });

  testWidgets('a paste attaches to the draft', (tester) async {
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
