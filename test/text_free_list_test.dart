/// Textgate guard for the notes list and the sheets it opens: nothing
/// app-written is painted, only note content, numbers and glyphs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';

import 'notes_list_harness.dart';
import 'text_free_guard.dart';

const _content = [
  'Buy milk',
  'Fix sync',
  'kuhyx/todo-app',
  'flutter test',
  'claude',
  'green run',
  'todo-app',
];

final _task = Note(
  id: 't',
  text: 'Fix sync',
  priority: Priority.high,
  status: Status.inProgress,
  createdAt: DateTime(2026, 6, 15, 9),
  updatedAt: DateTime(2026, 6, 15, 9),
  repo: 'kuhyx/todo-app',
  doneCheck: 'flutter test',
  by: 'claude',
  evidence: 'green run',
);

void _size(WidgetTester t, Size s, double dpr) {
  t.view
    ..physicalSize = s
    ..devicePixelRatio = dpr;
  addTearDown(t.view.reset);
}

void _desktop(WidgetTester t) => _size(t, const Size(1600, 1000), 1);

void _phone(WidgetTester t) => _size(t, const Size(1080, 2400), 2.625);

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('the empty list paints no words', (t) async {
    _desktop(t);
    await pumpList(t);
    expectNoChromeWords(t);
  });

  testWidgets('the filtered-empty list paints no words', (t) async {
    _desktop(t);
    await pumpList(
      t,
      seed: [note('a', 'Buy milk', status: Status.done)],
      applyFilter: true,
    );
    expectNoChromeWords(t);
  });

  testWidgets('the desktop list paints only note content', (t) async {
    _desktop(t);
    await pumpList(t, seed: [note('a', 'Buy milk'), note('e', ''), _task]);
    expectNoChromeWords(t, content: _content);
  });

  testWidgets('the phone grid paints only note content', (t) async {
    _phone(t);
    await pumpList(t, seed: [note('a', 'Buy milk'), note('e', ''), _task]);
    expectNoChromeWords(t, content: _content);
  });

  testWidgets('the filter sheet paints no words', (t) async {
    _phone(t);
    await pumpList(t, seed: [note('a', 'Buy milk')], applyFilter: true);
    await t.tap(find.byIcon(Icons.filter_list));
    await _settle(t);
    expectNoChromeWords(t, content: _content);
  });

  testWidgets('an opened note paints only its content', (t) async {
    _desktop(t);
    await pumpList(t, seed: [_task]);
    await t.tap(find.text('Fix sync'));
    await _settle(t);
    expectNoChromeWords(t, content: _content);
  });

  for (final (name, title) in [
    ('plain note', 'Buy milk'),
    ('task', 'Fix sync'),
  ]) {
    testWidgets('the $name sheet paints only note content', (t) async {
      _phone(t);
      await pumpList(t, seed: [note('a', 'Buy milk'), _task]);
      await t.longPress(find.text(title));
      await _settle(t);
      expectNoChromeWords(t, content: _content);
    });
  }
}
