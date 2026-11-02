// Repo tasks in the notes list: hidden by default, one chip per repo plus a
// "Repo tasks" chip in the filter sheet, fields read-only in the note sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/ui/note_actions_sheet.dart';

import 'notes_list_harness.dart';

Note task(String id, String repo, {String? evidence}) =>
    note(id, 'Task $id').copyWith(
      repo: repo,
      doneCheck: 'make check',
      by: 'claude',
      evidence: evidence,
    );

final _seed = [
  note('i', 'An idea'),
  task('t', 'kuhyx/utils'),
  task('u', 'kuhyx/todo'),
  task('v', 'kuhyx/todo'),
];

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.filter_list));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> apply(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Apply'));
  await tester.pump();
  await tester.tap(find.text('Apply'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

bool chipSelected(WidgetTester tester, String label) =>
    tester.widget<FilterChip>(find.widgetWithText(FilterChip, label)).selected;

bool badgeShown(WidgetTester tester) =>
    tester.widget<Badge>(find.byType(Badge)).isLabelVisible;

void main() {
  testWidgets('the default view shows only ideas, with no badge', (
    tester,
  ) async {
    final repo = await pumpList(tester, seed: _seed);
    expect(repo.lastFilter!.sources, {kIdeasSource});
    expect(badgeShown(tester), isFalse);
  });

  testWidgets('the sheet offers Ideas, Repo tasks and one chip per repo', (
    tester,
  ) async {
    await pumpList(tester, seed: _seed);
    await openSheet(tester);
    expect(chipSelected(tester, 'Ideas'), isTrue);
    expect(chipSelected(tester, 'Repo tasks'), isFalse);
    expect(find.widgetWithText(FilterChip, 'kuhyx/todo'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'kuhyx/utils'), findsOneWidget);
    expect(chipSelected(tester, 'kuhyx/todo'), isFalse);
  });

  testWidgets('Repo tasks lets every repo task in and shows the badge', (
    tester,
  ) async {
    final repo = await pumpList(tester, seed: _seed);
    await openSheet(tester);
    await tester.tap(find.text('Repo tasks'));
    await tester.pump();
    await apply(tester);
    expect(repo.lastFilter!.sources, {kIdeasSource, kRepoTasksSource});
    expect(badgeShown(tester), isTrue);
  });

  testWidgets('a repo chip, without Ideas, shows only that repo', (
    tester,
  ) async {
    final repo = await pumpList(tester, seed: _seed);
    await openSheet(tester);
    await tester.tap(find.text('Ideas'));
    await tester.tap(find.text('kuhyx/utils'));
    await tester.pump();
    await apply(tester);
    expect(repo.lastFilter!.sources, {'kuhyx/utils'});
  });

  testWidgets('Clear all resets the source chips to ideas only', (
    tester,
  ) async {
    final repo = await pumpList(tester, seed: _seed);
    await openSheet(tester);
    await tester.tap(find.text('kuhyx/todo'));
    await tester.pump();
    await tester.tap(find.text('Clear all'));
    await tester.pump();
    await apply(tester);
    expect(repo.lastFilter!.sources, {kIdeasSource});
    expect(badgeShown(tester), isFalse);
  });

  Future<void> pumpActions(WidgetTester tester, Note n) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: NoteActionsSheet(
          note: n,
          onChanged: (_) async {},
          onDelete: () async {},
        ),
      ),
    ),
  );

  testWidgets('the note sheet shows task fields read-only when present', (
    tester,
  ) async {
    await pumpActions(tester, task('t', 'kuhyx/todo', evidence: 'abc 0'));
    expect(find.text('kuhyx/todo'), findsOneWidget);
    expect(find.text('make check'), findsOneWidget);
    expect(find.text('claude'), findsOneWidget);
    expect(find.text('abc 0'), findsOneWidget);
    expect(find.text('Done check'), findsOneWidget);
    expect(find.text('Evidence'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('no repo tasks stored: the sheet has no source chips', (
    tester,
  ) async {
    await pumpList(tester, seed: [note('i', 'An idea')]);
    await openSheet(tester);
    expect(find.text('Repo tasks'), findsNothing);
  });

  testWidgets('a plain idea shows no task fields', (tester) async {
    await pumpActions(tester, note('i', 'An idea'));
    expect(find.text('Repo'), findsNothing);
    expect(find.text('Done check'), findsNothing);
    expect(find.text('Evidence'), findsNothing);
  });
}
