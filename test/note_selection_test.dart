/// The notes list's selection state, apart from any widget.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/ui/note_selection.dart';

import 'notes_list_harness.dart';

void main() {
  final order = [
    note('a', 'A'),
    note('b', 'B'),
    note('c', 'C'),
    note('d', 'D'),
  ];

  test('mode toggles; leaving it clears the selection', () {
    final s = NoteSelection();
    addTearDown(s.dispose);
    expect(s.active, isFalse);
    s.toggleMode();
    expect(s.active, isTrue);
    s.toggle('a');
    expect(s.ids, {'a'});
    s.toggleMode();
    expect(s.active, isFalse);
    expect(s.ids, isEmpty);
  });

  test('toggle adds then removes, and enters the mode', () {
    final s = NoteSelection();
    addTearDown(s.dispose);
    var notified = 0;
    s.addListener(() => notified++);
    s.toggle('b');
    expect(s.active, isTrue);
    expect(s.contains('b'), isTrue);
    s.toggle('b');
    expect(s.contains('b'), isFalse);
    expect(s.active, isTrue);
    expect(notified, 2);
  });

  test('extendTo selects the run from the anchor, either direction', () {
    final s = NoteSelection();
    addTearDown(s.dispose);
    s
      ..toggle('d')
      ..extendTo('b', order);
    expect(s.ids, {'b', 'c', 'd'});
    s
      ..clear()
      ..toggle('a')
      ..extendTo('c', order);
    expect(s.ids, {'a', 'b', 'c'});
  });

  test('extendTo without a usable anchor just toggles', () {
    final s = NoteSelection();
    addTearDown(s.dispose);
    s.extendTo('c', order);
    expect(s.ids, {'c'});
    s
      ..clear()
      ..toggle('zz')
      ..extendTo('a', order);
    expect(s.ids, {'zz', 'a'});
  });

  test('clear empties and leaves the mode', () {
    final s = NoteSelection();
    addTearDown(s.dispose);
    s
      ..toggle('a')
      ..clear();
    expect(s.ids, isEmpty);
    expect(s.active, isFalse);
  });

  testWidgets('handleTap: plain tap outside the mode is not consumed', (
    t,
  ) async {
    final s = NoteSelection();
    addTearDown(s.dispose);
    expect(s.handleTap(order[0], order), isFalse);
    expect(s.ids, isEmpty);

    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    expect(s.handleTap(order[0], order), isTrue);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(s.ids, {'a'});

    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    expect(s.handleTap(order[2], order), isTrue);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(s.ids, {'a', 'b', 'c'});

    expect(s.handleTap(order[1], order), isTrue);
    expect(s.ids, {'a', 'c'});
  });
}
