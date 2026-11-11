/// What the narrow notes grid shows and does, apart from its geometry.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/ui/note_grid_tile.dart';

import 'notes_list_harness.dart';

void _phone(WidgetTester t) {
  t.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
}

Future<void> _openSheet(WidgetTester t, String title) async {
  await t.longPress(find.text(title));
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('phone width shows tiles, desktop width keeps the list', (
    t,
  ) async {
    _phone(t);
    await pumpList(t, seed: [note('a', 'Buy milk')]);
    expect(find.byType(NoteGridTile), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);

    t.view
      ..physicalSize = const Size(3840, 2160)
      ..devicePixelRatio = 1;
    await t.pump();
    expect(find.byType(NoteGridTile), findsNothing);
    expect(find.byType(ListTile), findsOneWidget);
  });

  testWidgets('a tile is title plus priority and status cues only', (t) async {
    _phone(t);
    await pumpList(
      t,
      seed: [
        note(
          'a',
          'Buy milk\n\n## what\nTwo litres',
          priority: Priority.high,
          status: Status.inProgress,
        ),
      ],
    );

    expect(find.text('Buy milk'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.textContaining('Two litres'), findsNothing);
    expect(find.textContaining('edited'), findsNothing);
    expect(find.byTooltip('Quick actions'), findsNothing);
  });

  testWidgets('priority and status each get their own cue', (t) async {
    _phone(t);
    await pumpList(
      t,
      seed: [
        note('h', 'H', priority: Priority.high),
        note('m', 'M'),
        note('l', 'L', priority: Priority.low, status: Status.inProgress),
      ],
    );
    final scheme = Theme.of(t.element(find.byType(Scaffold))).colorScheme;
    final accents = {
      for (final id in ['h', 'm', 'l'])
        t.widget<NoteGridTile>(find.byKey(ValueKey(id))).accentFor(scheme),
    };
    expect(accents, hasLength(3));
    expect(find.byIcon(Icons.radio_button_unchecked), findsNWidgets(2));
    expect(find.byIcon(Icons.timelapse), findsOneWidget);
  });

  testWidgets('every status has an icon', (t) async {
    _phone(t);
    await pumpList(
      t,
      seed: [for (final s in Status.values) note(s.name, s.name, status: s)],
    );
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
  });

  testWidgets('an empty note reads (empty)', (t) async {
    _phone(t);
    await pumpList(t, seed: [note('a', '')]);
    expect(find.text('(empty)'), findsOneWidget);
  });

  testWidgets('tap opens the note', (t) async {
    _phone(t);
    await pumpList(t, seed: [note('a', 'Open me')]);

    await t.tap(find.text('Open me'));
    await t.pumpAndSettle();

    expect(find.bySemanticsLabel('Priority'), findsOneWidget);
    expect(find.bySemanticsLabel('View'), findsOneWidget);
  });

  testWidgets('long-press opens the sheet with body, dates and actions', (
    t,
  ) async {
    _phone(t);
    final repo = await pumpList(
      t,
      seed: [note('a', 'Buy milk\n\n## what\nTwo litres of oat')],
    );

    await _openSheet(t, 'Buy milk');

    expect(find.textContaining('Two litres of oat'), findsOneWidget);
    expect(find.textContaining('Edited'), findsOneWidget);
    expect(find.textContaining('Created'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('In progress'));
    await t.pump();
    expect((await repo.listNotes()).single.status, Status.inProgress);
    expect(find.bySemanticsLabel('Delete note'), findsOneWidget);
  });

  testWidgets('a title-only note adds no body to the sheet', (t) async {
    _phone(t);
    await pumpList(t, seed: [note('a', 'Just a title')]);

    await _openSheet(t, 'Just a title');

    expect(find.text('Just a title'), findsNWidgets(2));
    expect(find.textContaining('Edited'), findsOneWidget);
  });

  testWidgets('the sheet can delete a grid note', (t) async {
    _phone(t);
    final repo = await pumpList(t, seed: [note('a', 'Delete me')]);

    await _openSheet(t, 'Delete me');
    await t.tap(find.bySemanticsLabel('Delete note'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('confirm-delete')));
    await t.pumpAndSettle();

    expect(await repo.listNotes(), isEmpty);
  });

  testWidgets('empty state and the default filter survive the grid', (t) async {
    _phone(t);
    final repo = await pumpList(t);

    expect(find.textContaining('No notes'), findsOneWidget);
    expect(repo.lastFilter!.statuses, {Status.todo, Status.inProgress});
    expect(t.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);
  });
}
