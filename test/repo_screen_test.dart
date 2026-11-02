// The repo screen: all of a repo's tasks, each opening its note, plus the
// copy-all action.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/ui/note_grid_tile.dart';
import 'package:todo/ui/note_tile.dart';

import 'notes_list_harness.dart';

Note _task(String id, String text, {String repo = 'kuhyx/kartka'}) =>
    note(id, text).copyWith(repo: repo, by: 'claude');

final _seed = [
  _task('aaaaaaaa-1111', '# Fix scanner\n\nIt crashes on EAN-8.'),
  _task('bbbbbbbb-2222', 'Add cache'),
  _task('cccccccc-3333', 'Other repo task', repo: 'kuhyx/utils'),
];

Future<void> _openRepo(WidgetTester tester) async {
  await tester.tap(find.text('kartka · 2'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('tapping the repo row lists all its tasks', (tester) async {
    await pumpList(tester, seed: _seed, applyFilter: true);
    await _openRepo(tester);
    expect(find.text('Fix scanner'), findsOneWidget);
    expect(find.text('Add cache'), findsOneWidget);
    expect(find.text('Other repo task'), findsNothing);
  });

  testWidgets('phone grid: the repo tile opens the screen; long-press acts', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await pumpList(tester, seed: _seed, applyFilter: true);
    await _openRepo(tester);
    await tester.longPress(find.text('Add cache'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Delete note'), findsOneWidget);
  });

  testWidgets('a task on the repo screen opens its note detail', (
    tester,
  ) async {
    await pumpList(tester, seed: _seed, applyFilter: true);
    await _openRepo(tester);
    await tester.tap(find.text('Add cache'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('View'), findsOneWidget);
  });

  testWidgets('copy puts every task title, body and id8 on the clipboard', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await pumpList(tester, seed: _seed, applyFilter: true);
    await _openRepo(tester);
    await tester.tap(find.byTooltip('Copy all'));
    await tester.pump();
    expect(copied, isNotNull);
    expect(copied, contains('Fix scanner'));
    expect(copied, contains('It crashes on EAN-8.'));
    expect(copied, contains('id: aaaaaaaa'));
    expect(copied, contains('Add cache'));
    expect(copied, contains('id: bbbbbbbb'));
    expect(copied, isNot(contains('Other repo task')));
    expect(copied, contains('\n\n'));
  });

  testWidgets('cards show the bare repo name; an idea shows none', (
    tester,
  ) async {
    Future<void> pumpCards() => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              NoteTile(note: _seed[0], onTap: () {}, onActions: () {}),
              SizedBox(
                height: 120,
                child: NoteGridTile(
                  note: _seed[1],
                  onTap: () {},
                  onActions: () {},
                ),
              ),
              SizedBox(
                height: 120,
                child: NoteGridTile(
                  note: note('i', 'Just an idea'),
                  onTap: () {},
                  onActions: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await pumpCards();
    expect(find.textContaining('kartka'), findsNWidgets(2));
    expect(find.textContaining('kuhyx/'), findsNothing);
  });
}
