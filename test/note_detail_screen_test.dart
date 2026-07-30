import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/ui/note_detail_screen.dart';

import 'fake_note_repository.dart';

void main() {
  Note seedNote(String text) => Note(
    id: 'n1',
    text: text,
    priority: Priority.medium,
    status: Status.todo,
    createdAt: DateTime(2026, 6, 15, 9),
    updatedAt: DateTime(2026, 6, 15, 9),
  );

  Future<FakeNoteRepository> pumpDetail(WidgetTester tester, Note note) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = FakeNoteRepository([note]);
    addTearDown(repo.close);
    await tester.pumpWidget(
      MaterialApp(
        home: NoteDetailScreen(note: note, repository: repo),
      ),
    );
    await tester.pump();
    return repo;
  }

  testWidgets('opens in Raw with the title in the app bar', (tester) async {
    await pumpDetail(tester, seedNote('# My note\n\n## what\n_why_\n\nbody'));

    final raw = tester.widget<TextField>(find.byType(TextField));
    expect(raw.controller!.text, contains('My note'));
    expect(find.text('My note'), findsOneWidget); // app bar title
  });

  testWidgets('changing the priority dropdown persists the note', (
    tester,
  ) async {
    final repo = await pumpDetail(tester, seedNote('# T'));

    await tester.tap(
      find.byWidgetPredicate((w) => w is DropdownButtonFormField<Priority>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('High').last);
    await tester.pumpAndSettle();

    expect((await repo.listNotes()).single.priority, Priority.high);
  });

  testWidgets('changing the status dropdown persists the note', (tester) async {
    final repo = await pumpDetail(tester, seedNote('# T'));

    await tester.tap(
      find.byWidgetPredicate((w) => w is DropdownButtonFormField<Status>),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();

    expect((await repo.listNotes()).single.status, Status.done);
  });

  testWidgets('editing the body in Raw mode persists the new text', (
    tester,
  ) async {
    final repo = await pumpDetail(tester, seedNote('# T\n\n## what\nold'));

    await tester.tap(find.text('Raw'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '# T\n\n## what\nnew body');
    await tester.pump();

    expect((await repo.listNotes()).single.text, contains('new body'));
  });

  testWidgets(
    'clearing the body then tapping Guided runs the wizard and persists the chosen priority',
    (tester) async {
      final repo = await pumpDetail(tester, seedNote('# T\n\n## what\nold'));

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      await tester.tap(find.text('Guided'));
      await tester.pump();
      expect(find.text('Step 1 of 2'), findsOneWidget);
      // Wizard hides the Status dropdown (onChromeVisibleChanged(false)).
      expect(find.text('Status'), findsNothing);

      await tester.tap(find.byType(DropdownButtonFormField<Priority>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('High').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.tap(find.text('Start'));
      await tester.pump();

      expect((await repo.listNotes()).single.priority, Priority.high);
    },
  );

  testWidgets('the delete action removes the note and pops', (tester) async {
    final repo = await pumpDetail(tester, seedNote('# Bye'));

    await tester.tap(find.byTooltip('Delete note'));
    await tester.pumpAndSettle();

    // Delete is now confirmed. Deleting a note is irreversible and there is no
    // undo, so a single Return on a focused control must not destroy it.
    expect(find.text('Delete note?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(await repo.listNotes(), isEmpty);
    expect(find.byType(NoteDetailScreen), findsNothing);
  });

  testWidgets('cancelling the delete keeps the note', (tester) async {
    final repo = await pumpDetail(tester, seedNote('# Keep me'));

    await tester.tap(find.byTooltip('Delete note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await repo.listNotes(), hasLength(1));
    expect(find.byType(NoteDetailScreen), findsOneWidget);
  });
}
