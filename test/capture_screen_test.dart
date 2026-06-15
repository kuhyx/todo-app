import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/data/note.dart';
import 'package:todo/ui/capture_screen.dart';

import 'fake_note_repository.dart';

void main() {
  // A real CRDT DB schedules sqflite timers that never drain under the
  // widget tester's fake clock, so these tests inject a timer-free fake.
  // (NOTE: avoid pumpAndSettle — the autofocused field's cursor blink never
  // settles; pump explicit frames instead.)
  Future<FakeNoteRepository> pumpCapture(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = FakeNoteRepository();
    addTearDown(repo.close);
    await tester.pumpWidget(MaterialApp(home: CaptureScreen(repository: repo)));
    await tester.pump(); // flush initial stream + settings load
    return repo;
  }

  testWidgets('pre-fills the structured template', (tester) async {
    await pumpCapture(tester);

    expect(find.textContaining('<imperative title>'), findsOneWidget);
    expect(find.textContaining('what —'), findsOneWidget);
    expect(find.textContaining('done —'), findsOneWidget);
    expect(find.text('0 saved'), findsOneWidget);
  });

  testWidgets('saving the untouched template creates no note', (tester) async {
    final repo = await pumpCapture(tester);

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(await repo.listNotes(), isEmpty);
  });

  testWidgets('typing into the template persists a note with defaults', (
    tester,
  ) async {
    final repo = await pumpCapture(tester);

    await tester.enterText(
      find.byType(TextField),
      'My idea\n\nwhat — build the thing',
    );
    await tester.pump();

    final notes = await repo.listNotes();
    expect(notes, hasLength(1));
    expect(notes.single.text, contains('My idea'));
    expect(notes.single.priority, Priority.medium);
    expect(notes.single.status, Status.todo);
    expect(find.text('1 saved'), findsOneWidget);
  });

  testWidgets('save after editing shows a snackbar and resets the template', (
    tester,
  ) async {
    final repo = await pumpCapture(tester);

    await tester.enterText(find.byType(TextField), 'A real idea');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump(); // build the snackbar

    expect(find.text('Idea saved locally'), findsOneWidget);
    await tester.pump();

    expect(await repo.listNotes(), hasLength(1));
    expect(find.textContaining('<imperative title>'), findsOneWidget);
  });

  testWidgets('tapping Sync while unconfigured prompts for a token', (
    tester,
  ) async {
    await pumpCapture(tester); // empty prefs → no token → not configured

    await tester.tap(find.byTooltip('Sync'));
    await tester.pump(); // settings load + snackbar
    await tester.pump();

    expect(find.textContaining('Add a GitHub token'), findsOneWidget);
  });

  testWidgets('the notes-list button navigates to the list screen', (
    tester,
  ) async {
    await pumpCapture(tester);

    await tester.tap(find.byTooltip('Notes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // route transition

    expect(find.text('Notes'), findsOneWidget); // list screen app bar title
  });

  testWidgets('changing the priority dropdown updates the saved note', (
    tester,
  ) async {
    final repo = await pumpCapture(tester);

    await tester.enterText(find.byType(TextField), 'Prioritised idea');
    await tester.pump();

    await tester.tap(
      find.byWidgetPredicate((w) => w is DropdownButton<Priority>),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // menu open
    await tester.tap(find.text('High').last);
    await tester.pump();

    expect((await repo.listNotes()).single.priority, Priority.high);
  });

  testWidgets('changing the status dropdown updates the saved note', (
    tester,
  ) async {
    final repo = await pumpCapture(tester);

    await tester.enterText(find.byType(TextField), 'Status idea');
    await tester.pump();

    await tester.tap(
      find.byWidgetPredicate((w) => w is DropdownButton<Status>),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // menu open
    await tester.tap(find.text('In progress').last);
    await tester.pump();

    expect((await repo.listNotes()).single.status, Status.inProgress);
  });
}
