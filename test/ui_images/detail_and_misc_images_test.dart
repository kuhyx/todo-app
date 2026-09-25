import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/attachments/image_store_scope.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_template_parser.dart';
import 'package:todo/images/image_ref.dart';
import 'package:todo/sync/desktop_wrapper.dart';
import 'package:todo/sync/notes_markdown.dart';
import 'package:todo/ui/capture_draft.dart';
import 'package:todo/ui/image_input.dart';
import 'package:todo/ui/image_input_files.dart';
import 'package:todo/ui/images/image_embed.dart';
import 'package:todo/ui/images/image_strip.dart';
import 'package:todo/ui/markdown_view.dart';
import 'package:todo/ui/note_detail_screen.dart';

import '../fake_image_store.dart';
import '../fake_note_repository.dart';

Note note(String text) => Note(
  id: 'n1',
  text: text,
  priority: Priority.medium,
  status: Status.todo,
  createdAt: DateTime(2026, 9, 25),
  updatedAt: DateTime(2026, 9, 25),
);

void main() {
  final ref = ImageRef.create('n1');

  testWidgets('detail: 📎 inserts at the cursor and persists', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = FakeImageStore();
    final repo = FakeNoteRepository([note('first\nsecond')]);
    addTearDown(repo.close);
    await tester.pumpWidget(
      ImageStoreScope(
        store: store,
        child: MaterialApp(
          home: NoteDetailScreen(
            note: note('first\nsecond'),
            repository: repo,
            appSettings: ValueNotifier(const AppSettings(advancedMode: true)),
            imagePicking: (_) async => [
              Uint8List.fromList([1]),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    tester.widget<TextField>(find.byType(TextField)).controller!.selection =
        const TextSelection.collapsed(offset: 5);
    await tester.tap(find.byTooltip('Attach image'));
    await tester.pump();
    await tester.pump();
    final added = store.attached.keys.single;
    expect(added.noteId, 'n1');
    expect(
      (await repo.listNotes()).single.text,
      'first\n${added.markdown}\nsecond',
    );
    expect(find.byType(ImageStrip), findsOneWidget);
    // A paste or drop lands in the same note.
    tester.widget<ImageInputListener>(find.byType(ImageInputListener)).onImages(
      [
        Uint8List.fromList([2]),
      ],
      0,
    );
    await tester.pump();
    await tester.pump();
    expect(store.attached, hasLength(2));
    expect(store.attached.keys.last.noteId, 'n1');
    // View mode renders inline and hides the strip.
    await tester.tap(find.text('View'));
    await tester.pump();
    expect(find.byType(ImageStrip), findsNothing);
    expect(find.byType(ImageEmbed), findsNWidgets(2));
  });

  testWidgets('markdown view draws an image line as an embed', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MarkdownView(text: 'text\n${ref.markdown}\n')),
      ),
    );
    expect(find.byType(ImageEmbed), findsOneWidget);
    expect(find.text('text'), findsOneWidget);
  });

  testWidgets('the io input listener is a pass-through', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ImageInputListener(onImages: (_, _) {}, child: const Text('x')),
      ),
    );
    expect(find.text('x'), findsOneWidget);
  });

  test('partitionImageFiles keeps order and counts the rest', () {
    final split = partitionImageFiles([
      'image/png',
      'application/pdf',
      'IMAGE/JPEG',
      '',
    ]);
    expect(split.images, [0, 2]);
    expect(split.rejected, 2);
  });

  test('noteTitle skips image lines', () {
    expect(noteTitle('${ref.markdown}\n# Real title'), 'Real title');
    expect(noteTitle(ref.markdown), 'Image');
    expect(noteTitle('${ref.markdown}\n\n${ref.markdown}'), '2 images');
    expect(noteTitle(''), '');
  });

  test('the backlog export uses disk paths and parses back', () {
    final exported = NotesMarkdown.export([note('t\n${ref.markdown}')]);
    expect(exported, contains('![]($kBacklogImagesRoot/${ref.relativePath})'));
    expect(NotesMarkdown.parse(exported).single.text, 't\n${ref.markdown}');
  });

  test('the page talks to the wrapper that served it', () {
    expect(
      servingWrapperOrigin(Uri.parse('http://localhost:8731/#/x')),
      'http://localhost:8731',
    );
    expect(servingWrapperOrigin(Uri.parse('file:///x')), desktopWrapperOrigin);
    expect(servingWrapperOrigin(), desktopWrapperOrigin);
  });

  group('capture draft id reservation', () {
    late FakeNoteRepository repo;
    late CaptureDraft draft;
    setUp(() {
      repo = FakeNoteRepository([]);
      draft = CaptureDraft(repo);
    });
    tearDown(() async {
      draft.dispose();
      await repo.close();
    });

    test('a reserved id saves nothing until text arrives', () async {
      final id = draft.reserveId();
      expect(draft.reserveId(), id);
      await draft.persistMetadata(live: () => true);
      expect(await repo.listNotes(), isEmpty);
      expect(await draft.write('   ', live: () => true), isFalse);
      expect(await draft.write('x', live: () => true), isTrue);
      expect((await repo.listNotes()).single.id, id);
      expect(await draft.write('xy', live: () => true), isFalse);
    });

    test('reset drops the reservation', () async {
      final id = draft.reserveId();
      draft.reset();
      expect(draft.reserveId(), isNot(id));
    });
  });
}
