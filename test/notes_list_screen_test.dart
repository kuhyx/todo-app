import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/ui/notes_list_screen.dart';

import 'fake_note_repository.dart';

import 'notes_list_harness.dart';

void main() {
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

    await tester.tap(find.byTooltip('Quick actions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // sheet open
    await tester.tap(find.text('Delete note'));
    await tester.pumpAndSettle();

    // Delete is now confirmed on this path too: it is irreversible, has no
    // undo, and is one Tab from a Return in the sheet's chip rows.
    expect(find.text('Delete note?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(await repo.listNotes(), isEmpty);
  });

  testWidgets('cancelling the sheet delete keeps the note', (tester) async {
    final repo = await pumpList(tester, seed: [note('a', 'Keep me')]);

    await tester.tap(find.byTooltip('Quick actions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Delete note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await repo.listNotes(), hasLength(1));
  });

  testWidgets('per-note sheet changes status via a chip', (tester) async {
    final repo = await pumpList(tester, seed: [note('a', 'Change me')]);

    await tester.tap(find.byTooltip('Quick actions'));
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
}
