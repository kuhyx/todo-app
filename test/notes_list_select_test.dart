/// Multi-select on the notes list: mode, toggling, bulk status/priority.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/ui/note_actions_sheet.dart';
import 'package:todo/ui/note_detail_screen.dart';

import 'fake_note_repository.dart';
import 'notes_list_harness.dart';

const _dpr = 2.625;

/// Pixel 6a: 1080x2400 px at 2.625 with the real system-bar insets.
void _pixel6a(WidgetTester t) {
  const bars = FakeViewPadding(top: 132, bottom: 63);
  t.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = _dpr
    ..padding = bars
    ..viewPadding = bars;
  addTearDown(t.view.reset);
}

void _desktop(WidgetTester t) {
  t.view
    ..physicalSize = const Size(1600, 1000)
    ..devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

final _seed = [note('a', 'Alpha'), note('b', 'Beta'), note('c', 'Gamma')];

Finder _checkIn(String id) => find.descendant(
  of: find.byKey(ValueKey(id)),
  matching: find.byIcon(Icons.check_circle),
);

Future<void> _pick(WidgetTester t, String button, String item) async {
  await t.tap(find.byKey(ValueKey(button)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.tap(find.byKey(ValueKey(item)));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<FakeNoteRepository> _selectAll(WidgetTester t) async {
  final repo = await pumpList(t, seed: _seed);
  await t.tap(find.byKey(const ValueKey('select-mode')));
  await t.pump();
  for (final title in ['Alpha', 'Beta', 'Gamma']) {
    await t.tap(find.text(title));
    await t.pump();
  }
  return repo;
}

void main() {
  testWidgets('no bar and no checks until something is selected', (t) async {
    _pixel6a(t);
    await pumpList(t, seed: _seed);
    expect(find.byKey(const ValueKey('selection-bar')), findsNothing);
    await t.tap(find.byKey(const ValueKey('select-mode')));
    await t.pump();
    expect(find.byKey(const ValueKey('selection-bar')), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });

  testWidgets('in selection mode a tap toggles instead of opening', (t) async {
    _pixel6a(t);
    await pumpList(t, seed: _seed);
    await t.tap(find.byKey(const ValueKey('select-mode')));
    await t.pump();
    await t.tap(find.text('Alpha'));
    await t.pump();
    expect(find.byType(NoteDetailScreen), findsNothing);
    expect(_checkIn('a'), findsOneWidget);
    expect(_checkIn('b'), findsNothing);
    expect(find.byKey(const ValueKey('selection-bar')), findsOneWidget);

    await t.longPress(find.text('Beta'));
    await t.pump();
    expect(_checkIn('b'), findsOneWidget);
    expect(find.byType(NoteActionsSheet), findsNothing);

    await t.tap(find.text('Alpha'));
    await t.pump();
    expect(_checkIn('a'), findsNothing);
  });

  testWidgets('long-press outside selection mode still opens the sheet', (
    t,
  ) async {
    _pixel6a(t);
    await pumpList(t, seed: _seed);
    await t.longPress(find.text('Alpha'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byType(NoteActionsSheet), findsOneWidget);
  });

  testWidgets('bulk status then priority: one call each, no upserts', (
    t,
  ) async {
    _pixel6a(t);
    final repo = await _selectAll(t);
    await _pick(t, 'bulk-status', 'status-inProgress');
    await _pick(t, 'bulk-priority', 'priority-high');

    expect(repo.bulkCalls, 2);
    expect(repo.upsertCalls, 0);
    final notes = await repo.listNotes();
    expect(notes.map((n) => n.status).toSet(), {Status.inProgress});
    expect(notes.map((n) => n.priority).toSet(), {Priority.high});
    // Selection survives an action, so status + priority is one selection.
    expect(find.byIcon(Icons.check_circle), findsNWidgets(3));
  });

  testWidgets('clear empties the selection and leaves the mode', (t) async {
    _pixel6a(t);
    await _selectAll(t);
    await t.tap(find.byKey(const ValueKey('bulk-clear')));
    await t.pump();
    expect(find.byKey(const ValueKey('selection-bar')), findsNothing);
    await t.tap(find.text('Alpha'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byType(NoteDetailScreen), findsOneWidget);
  });

  testWidgets('desktop list: ctrl-click toggles, shift-click extends', (
    t,
  ) async {
    _desktop(t);
    await pumpList(t, seed: _seed);
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.tap(find.text('Alpha'));
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump();
    expect(find.byType(NoteDetailScreen), findsNothing);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.tap(find.text('Gamma'));
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    for (final id in ['a', 'b', 'c']) {
      final tile = t.widget<ListTile>(
        find.descendant(
          of: find.byKey(ValueKey(id)),
          matching: find.byType(ListTile),
        ),
      );
      expect(tile.selected, isTrue, reason: id);
    }
    expect(_checkIn('b'), findsOneWidget);
  });

  testWidgets('R7: bar icons are hit-testable above the bottom inset', (
    t,
  ) async {
    _pixel6a(t);
    await _selectAll(t);
    const bottomEdge = 2400 / _dpr - 63 / _dpr;
    for (final key in [
      'bulk-status',
      'bulk-priority',
      'bulk-assign',
      'bulk-clear',
    ]) {
      final f = find.byKey(ValueKey(key));
      expect(f.hitTestable(), findsOneWidget, reason: key);
      expect(t.getRect(f).bottom, lessThanOrEqualTo(bottomEdge), reason: key);
    }
  });
}
