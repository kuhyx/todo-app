/// Pixel 6a geometry of the notes grid: whole tiles only, nothing under the
/// status bar or the navigation bar, no overflow, scrolls only past a screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/ui/note_grid_tile.dart';

import 'notes_list_harness.dart';

const _dpr = 2.625;
const _navBar = 63 / _dpr;
const _statusBar = 132 / _dpr;
const _screenHeight = 2400 / _dpr;

/// 1080x2400 px at 2.625, with the real system-bar insets.
void _pixel6a(WidgetTester t, {double keyboardDp = 0}) {
  const bars = FakeViewPadding(top: 132, bottom: 63);
  t.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = _dpr
    ..padding = bars
    ..viewPadding = bars
    ..viewInsets = FakeViewPadding(bottom: keyboardDp * _dpr);
  addTearDown(t.view.reset);
}

List<Note> _notes(int n) => [
  for (var i = 0; i < n; i++)
    note(
      'n$i',
      'Note $i with a rather long title that wraps onto several lines',
      priority: Priority.values[i % 3],
    ),
];

Rect _viewport(WidgetTester t) => t.getRect(find.byType(GridView));

/// Tiles whose rect touches the viewport.
List<Rect> _shown(WidgetTester t) {
  final view = _viewport(t);
  return [
    for (final e in find.byType(NoteGridTile).evaluate())
      t.getRect(find.byWidget(e.widget)),
  ].where((r) => r.overlaps(view)).toList();
}

double _maxScroll(WidgetTester t) => t
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(GridView),
        matching: find.byType(Scrollable),
      ),
    )
    .position
    .maxScrollExtent;

void _expectWholeTilesOnly(WidgetTester t) {
  final view = _viewport(t);
  final shown = _shown(t);
  expect(shown, isNotEmpty);
  for (final r in shown) {
    expect(r.top, greaterThanOrEqualTo(view.top - 0.01), reason: '$r');
    expect(r.bottom, lessThanOrEqualTo(view.bottom + 0.01), reason: '$r');
  }
  // The rows use up the whole viewport: no strip of dead space under them.
  final lastBottom = shown.map((r) => r.bottom).reduce((a, b) => a > b ? a : b);
  expect(lastBottom, closeTo(view.bottom, 0.01));
}

void main() {
  testWidgets('Pixel 6a: whole tiles between the system bars', (t) async {
    _pixel6a(t);
    await pumpList(t, seed: _notes(300));

    expect(t.takeException(), isNull);
    final view = _viewport(t);
    expect(view.top, greaterThanOrEqualTo(_statusBar + kToolbarHeight));
    expect(view.bottom, closeTo(_screenHeight - _navBar, 0.01));
    _expectWholeTilesOnly(t);
    // Two columns, a real screenful, and tiles big enough to read.
    final shown = _shown(t);
    expect(shown.length.isEven, isTrue);
    expect(shown.length, greaterThanOrEqualTo(10));
    expect(shown.first.height, greaterThanOrEqualTo(88));
    expect(shown.first.width, closeTo(shown[1].width, 0.01));
    expect(shown[1].left, greaterThan(shown.first.right));
  });

  testWidgets('Pixel 6a: 300 notes scroll vertically to the last one', (
    t,
  ) async {
    _pixel6a(t);
    await pumpList(t, seed: _notes(300));

    expect(_maxScroll(t), greaterThan(0));
    await t.drag(find.byType(GridView), const Offset(0, -500000));
    await t.pump();
    await t.pump(const Duration(seconds: 1));

    expect(find.textContaining('Note 299 '), findsOneWidget);
    expect(find.textContaining('Note 299 ').hitTestable(), findsOneWidget);
    expect(_viewport(t).bottom, closeTo(_screenHeight - _navBar, 0.01));
  });

  testWidgets('Pixel 6a: exactly one screenful does not scroll', (t) async {
    _pixel6a(t);
    await pumpList(t, seed: _notes(300));
    final perScreen = _shown(t).length;

    await t.pumpWidget(const SizedBox());
    await pumpList(t, seed: _notes(perScreen));
    expect(_maxScroll(t), 0);
    _expectWholeTilesOnly(t);
    expect(_shown(t), hasLength(perScreen));
  });

  testWidgets('Pixel 6a: a few notes keep full-size tiles at the top', (
    t,
  ) async {
    _pixel6a(t);
    await pumpList(t, seed: _notes(300));
    final full = _shown(t).first;

    await t.pumpWidget(const SizedBox());
    await pumpList(t, seed: _notes(3));
    expect(_maxScroll(t), 0);
    expect(t.takeException(), isNull);
    final first = t.getRect(find.byType(NoteGridTile).first);
    expect(first.size, full.size);
    expect(first.top, closeTo(_viewport(t).top, 0.01));
  });

  testWidgets('Pixel 6a: toolbar, search and a tile are all tappable', (
    t,
  ) async {
    _pixel6a(t);
    await pumpList(t, seed: _notes(20));

    expect(find.byIcon(Icons.sort).hitTestable(), findsOneWidget);
    expect(find.byIcon(Icons.filter_list).hitTestable(), findsOneWidget);
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    expect(find.byType(NoteGridTile).hitTestable(), findsWidgets);
  });

  testWidgets('Pixel 6a with the keyboard open: still whole tiles', (t) async {
    _pixel6a(t, keyboardDp: 300);
    await pumpList(t, seed: _notes(300));

    expect(t.takeException(), isNull);
    _expectWholeTilesOnly(t);
  });

  testWidgets('Pixel 6a at 2x text scale: no overflow, tiles stay whole', (
    t,
  ) async {
    _pixel6a(t);
    t.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpList(t, seed: _notes(300));

    expect(t.takeException(), isNull);
    _expectWholeTilesOnly(t);
  });
}
