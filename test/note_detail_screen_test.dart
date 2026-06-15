import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/ui/markdown_view.dart';
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

  testWidgets('opens in the rendered Markdown view with the title in the bar', (
    tester,
  ) async {
    await pumpDetail(tester, seedNote('# My note\n\n## what\n_why_\n\nbody'));

    expect(find.byType(MarkdownView), findsOneWidget);
    // Title appears both in the app bar and the rendered body.
    expect(find.text('My note'), findsWidgets);
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

  testWidgets('the delete action removes the note and pops', (tester) async {
    final repo = await pumpDetail(tester, seedNote('# Bye'));

    await tester.tap(find.byTooltip('Delete note'));
    await tester.pumpAndSettle();

    expect(await repo.listNotes(), isEmpty);
    expect(find.byType(NoteDetailScreen), findsNothing);
  });
}
