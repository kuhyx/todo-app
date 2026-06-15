import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/ui/notes_list_screen.dart';

import 'fake_note_repository.dart';

void main() {
  Note note(
    String id,
    String text, {
    Priority priority = Priority.medium,
    Status status = Status.todo,
  }) {
    final now = DateTime(2026, 6, 15, 9);
    return Note(
      id: id,
      text: text,
      priority: priority,
      status: status,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<FakeNoteRepository> pumpList(
    WidgetTester tester, {
    List<Note> seed = const [],
  }) async {
    final repo = FakeNoteRepository(seed);
    addTearDown(repo.close);
    await tester.pumpWidget(
      MaterialApp(home: NotesListScreen(repository: repo)),
    );
    await tester.pump(); // flush the initial stream emit
    return repo;
  }

  testWidgets('renders notes with a status · priority · time subtitle', (
    tester,
  ) async {
    await pumpList(
      tester,
      seed: [note('a', 'First note', priority: Priority.high)],
    );

    expect(find.text('First note'), findsOneWidget);
    expect(find.textContaining('To do'), findsOneWidget);
    expect(find.textContaining('High'), findsOneWidget);
  });

  testWidgets('defaults to hiding Done/Abandoned with no filter badge', (
    tester,
  ) async {
    final repo = await pumpList(tester, seed: [note('a', 'x')]);

    // The screen's default query hides completed work…
    expect(repo.lastFilter!.statuses, {Status.todo, Status.inProgress});
    // …but that default is not surfaced as an active-filter badge.
    expect(find.byType(Badge), findsOneWidget);
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
  });

  testWidgets('search box feeds a debounced query into the filter', (
    tester,
  ) async {
    final repo = await pumpList(tester, seed: [note('a', 'x')]);

    await tester.enterText(find.byType(TextField), 'diet');
    await tester.pump(const Duration(milliseconds: 300)); // > debounce

    expect(repo.lastFilter!.query, 'diet');
  });

  testWidgets('sort menu selection updates the query sort', (tester) async {
    final repo = await pumpList(tester, seed: [note('a', 'x')]);

    await tester.tap(find.byIcon(Icons.sort));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // menu open
    await tester.tap(find.text('Alphabetical').last);
    await tester.pump();

    expect(repo.lastSort, NoteSort.alphabetical);
  });

  testWidgets('filter sheet adds a status and shows the badge', (tester) async {
    final repo = await pumpList(tester, seed: [note('a', 'x')]);

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet open
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet close

    expect(repo.lastFilter!.statuses, contains(Status.done));
    // A non-default selection now surfaces the badge.
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
  });

  testWidgets('per-note sheet deletes the note', (tester) async {
    final repo = await pumpList(tester, seed: [note('a', 'Delete me')]);

    await tester.tap(find.text('Delete me'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet open
    await tester.tap(find.text('Delete note'));
    await tester.pump();

    expect(await repo.listNotes(), isEmpty);
  });

  testWidgets('per-note sheet changes status via a chip', (tester) async {
    final repo = await pumpList(tester, seed: [note('a', 'Change me')]);

    await tester.tap(find.text('Change me'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('In progress'));
    await tester.pump();

    expect((await repo.listNotes()).single.status, Status.inProgress);
  });

  testWidgets('shows an empty state when there are no notes', (tester) async {
    await pumpList(tester); // no seed
    // The default filter hides Done/Abandoned, so it's the "no match"
    // variant rather than "No notes yet" — either way, an empty message.
    expect(find.textContaining('No notes'), findsOneWidget);
  });

  testWidgets('a Created date preset sets a created range on the filter', (
    tester,
  ) async {
    final repo = await pumpList(tester, seed: [note('a', 'x')]);

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // "Today" appears under both Created and Last-updated; the first is
    // Created.
    await tester.tap(find.text('Today').first);
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.lastFilter!.createdFrom, isNotNull);
    expect(repo.lastFilter!.createdTo, isNotNull);
  });

  testWidgets('clearing the search box resets the query', (tester) async {
    final repo = await pumpList(tester, seed: [note('a', 'x')]);

    await tester.enterText(find.byType(TextField), 'foo');
    await tester.pump(const Duration(milliseconds: 300));
    expect(repo.lastFilter!.query, 'foo');

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.lastFilter!.query, isEmpty);
  });

  testWidgets('renders relative-time labels for varied ages', (tester) async {
    final now = DateTime.now();
    Note aged(String id, Duration ago) => Note(
      id: id,
      text: 'note $id',
      priority: Priority.medium,
      status: Status.todo,
      createdAt: now.subtract(ago),
      updatedAt: now.subtract(ago),
    );
    await pumpList(
      tester,
      seed: [
        aged('s', const Duration(seconds: 10)),
        aged('m', const Duration(minutes: 5)),
        aged('h', const Duration(hours: 2)),
        aged('d', const Duration(days: 3)),
      ],
    );

    expect(find.textContaining('just now'), findsOneWidget);
    expect(find.textContaining('5m ago'), findsOneWidget);
    expect(find.textContaining('2h ago'), findsOneWidget);
    expect(find.textContaining('3d ago'), findsOneWidget);
  });

  testWidgets('Clear all resets the filter sheet to the default', (
    tester,
  ) async {
    final repo = await pumpList(tester, seed: [note('a', 'x')]);

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Done')); // add a non-default status
    await tester.pump();
    await tester.tap(find.text('Clear all'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.lastFilter!.statuses, {Status.todo, Status.inProgress});
  });

  testWidgets('a date range can be set then cleared with Any', (tester) async {
    final repo = await pumpList(tester, seed: [note('a', 'x')]);

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('7 days').first); // Created: last 7 days
    await tester.pump();
    await tester.tap(find.text('Any').first); // clear that range
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.lastFilter!.createdFrom, isNull);
  });

  testWidgets('Custom… opens the range picker (cancel keeps no range)', (
    tester,
  ) async {
    final repo = await pumpList(tester, seed: [note('a', 'x')]);

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Custom…').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // picker opens
    // The full-screen range picker dismisses via a close icon, not a label.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.lastFilter!.createdFrom, isNull);
  });

  testWidgets('filter sheet toggles a priority and a Last-updated preset', (
    tester,
  ) async {
    final repo = await pumpList(tester, seed: [note('a', 'x')]);

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('High')); // priority chip toggle
    // Second "Today" belongs to the Last-updated section.
    await tester.tap(find.text('Today').last);
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.lastFilter!.priorities, contains(Priority.high));
    expect(repo.lastFilter!.updatedFrom, isNotNull);
    expect(repo.lastFilter!.updatedTo, isNotNull);
  });

  testWidgets('a 30-day preset then Custom… confirms the seeded range', (
    tester,
  ) async {
    final repo = await pumpList(tester, seed: [note('a', 'x')]);

    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('30 days').first); // _applyDays(30)
    await tester.pump();
    // Custom… opens the range picker seeded with the 30-day range
    // (initialDateRange != null); confirming with Save returns that range.
    await tester.tap(find.text('Custom…').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // picker opens
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(repo.lastFilter!.createdFrom, isNotNull);
    expect(repo.lastFilter!.createdTo, isNotNull);
  });

  testWidgets('per-note sheet changes priority via a chip', (tester) async {
    final repo = await pumpList(tester, seed: [note('a', 'Repriortise me')]);

    await tester.tap(find.text('Repriortise me'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Low')); // default is Medium → change to Low
    await tester.pump();

    expect((await repo.listNotes()).single.priority, Priority.low);
  });
}
