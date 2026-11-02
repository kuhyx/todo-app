// One list: ideas and repo notes together, one row each, repo searchable, and a filter
// sheet that fits a Pixel 6a screen without scrolling.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';

import 'notes_list_harness.dart';

Note _repoNote(
  String id,
  String title,
  String repo, {
  Status status = Status.todo,
}) => note(id, title, status: status).copyWith(repo: repo, by: 'claude');

final _seed = [
  note('i', 'An idea about tea'),
  _repoNote('r1', 'Fix the scanner', 'kuhyx/kartka'),
  _repoNote('r2', 'Add barcode cache', 'kuhyx/kartka'),
  _repoNote('r3', 'Closed chore', 'kuhyx/kartka', status: Status.done),
];

void _pixel6a(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 2.625
    ..padding = const FakeViewPadding(top: 132, bottom: 63)
    ..viewPadding = const FakeViewPadding(top: 132, bottom: 63);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('every open note is its own row; no group rows', (tester) async {
    _pixel6a(tester);
    await pumpList(tester, seed: _seed, applyFilter: true);
    expect(find.text('An idea about tea'), findsOneWidget);
    expect(find.text('Fix the scanner'), findsOneWidget);
    expect(find.text('Add barcode cache'), findsOneWidget);
    // The done one is filtered out; nothing says "kartka · 2".
    expect(find.text('Closed chore'), findsNothing);
    expect(find.textContaining(' · 2'), findsNothing);
    // The repo name shows as a small label on each repo note's card.
    expect(find.text('kartka'), findsNWidgets(2));
  });

  testWidgets('searching a repo name finds its notes only', (tester) async {
    _pixel6a(tester);
    await pumpList(tester, seed: _seed, applyFilter: true);
    await tester.enterText(find.byType(TextField), 'kartka');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Fix the scanner'), findsOneWidget);
    expect(find.text('Add barcode cache'), findsOneWidget);
    expect(find.text('An idea about tea'), findsNothing);
  });

  testWidgets('wide windows list one row per note', (tester) async {
    await pumpList(tester, seed: _seed, applyFilter: true);
    expect(find.text('Fix the scanner'), findsOneWidget);
    expect(find.text('Add barcode cache'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(3));
  });

  testWidgets('a filter sheet fits a Pixel 6a screen with no scrolling', (
    tester,
  ) async {
    _pixel6a(tester);
    await pumpList(tester, seed: _seed, applyFilter: true);
    await tester.tap(find.byIcon(Icons.filter_list));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final inSheet = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(Scrollable),
    );
    final states = tester.stateList<ScrollableState>(inSheet).toList();
    for (final s in states) {
      if (axisDirectionToAxis(s.axisDirection) == Axis.vertical)
        expect(s.position.maxScrollExtent, 0);
    }
    expect(find.text('Apply').hitTestable(), findsOneWidget);
    expect(find.text('Repo tasks'), findsNothing);
    expect(find.text('Ideas'), findsNothing);
    expect(find.byType(ActionChip), findsNothing);
  });
}
