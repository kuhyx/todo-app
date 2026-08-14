import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/ui/notes_list_screen.dart';

import 'fake_note_repository.dart';

import 'notes_list_harness.dart';

void main() {
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

    await tester.tap(find.byTooltip('Quick actions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Low')); // default is Medium → change to Low
    await tester.pump();

    expect((await repo.listNotes()).single.priority, Priority.low);
  });

  testWidgets('tapping a note opens the detail screen', (tester) async {
    await pumpList(tester, seed: [note('a', '# Open me\n\nbody')]);

    await tester.tap(find.text('Open me'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // route transition

    // The detail screen shows the note title in its app bar plus the
    // Priority/Status meta dropdowns and the editor mode toggle.
    expect(find.text('Priority'), findsOneWidget);
    expect(find.text('View'), findsOneWidget);
  });
}
