// Repo tasks in the notes list: no source filter at all, and their fields
// read-only in the note sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/ui/notes_list_defaults.dart';
import 'package:todo/ui/note_actions_sheet.dart';

import 'notes_list_harness.dart';

Note task(String id, String repo, {String? evidence}) =>
    note(id, 'Task $id').copyWith(
      repo: repo,
      doneCheck: 'make check',
      by: 'claude',
      evidence: evidence,
    );

bool badgeShown(WidgetTester tester) =>
    tester.widget<Badge>(find.byType(Badge)).isLabelVisible;

void main() {
  testWidgets('the default view filters by status only, with no badge', (
    tester,
  ) async {
    final repo = await pumpList(
      tester,
      seed: [note('i', 'An idea'), task('t', 'kuhyx/utils')],
    );
    expect(repo.lastFilter!.statuses, kDefaultStatuses);
    expect(repo.lastFilter!.repo, isNull);
    expect(repo.lastFilter!.repoTasksOnly, isFalse);
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

  testWidgets('a plain idea shows no task fields', (tester) async {
    await pumpActions(tester, note('i', 'An idea'));
    expect(find.text('Repo'), findsNothing);
    expect(find.text('Done check'), findsNothing);
    expect(find.text('Evidence'), findsNothing);
  });
}
