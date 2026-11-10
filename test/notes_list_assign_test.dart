/// Assign-to-repo from the selection bar: picker, move, refusal.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';

import 'fake_note_repository.dart';
import 'notes_list_harness.dart';

void _phone(WidgetTester t) {
  t.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 2.625;
  addTearDown(t.view.reset);
}

Note _repoNote(String id, String text, String repo) {
  final n = note(id, text);
  return n.copyWith(repo: repo);
}

Future<FakeNoteRepository> _select(
  WidgetTester t,
  List<Note> seed,
  List<String> titles,
) async {
  final repo = await pumpList(t, seed: seed, applyFilter: true);
  await t.tap(find.byKey(const ValueKey('select-mode')));
  await t.pump();
  for (final title in titles) {
    await t.tap(find.text(title));
    await t.pump();
  }
  await t.tap(find.byKey(const ValueKey('bulk-assign')));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  return repo;
}

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('picker lists known repos; picking one moves the notes', (
    t,
  ) async {
    _phone(t);
    final repo = await _select(
      t,
      [
        _repoNote('r', 'app todos\n\n## Old', 'kuhyx/app'),
        _repoNote('o', 'web todos', 'kuhyx/web'),
        note('p1', 'Fix login'),
        note('p2', 'Tidy up'),
      ],
      ['Fix login', 'Tidy up'],
    );
    expect(find.byKey(const ValueKey('repo-kuhyx/app')), findsOneWidget);
    expect(find.byKey(const ValueKey('repo-kuhyx/web')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('repo-kuhyx/app')));
    await _settle(t);

    final notes = {for (final n in await repo.listNotes()) n.id: n};
    expect(notes.keys, unorderedEquals(['r', 'o']));
    expect(
      notes['r']!.text,
      'app todos\n\n## Old\n\n## Fix login\n\n## Tidy up',
    );
    expect(repo.upsertCalls, 0);
    expect(find.byKey(const ValueKey('selection-bar')), findsNothing);
  });

  testWidgets('a new kuhyx/<name> typed in the field creates its note', (
    t,
  ) async {
    _phone(t);
    final repo = await _select(t, [note('p', 'Ship it')], ['Ship it']);
    final field = find.byKey(const ValueKey('repo-new'));
    expect(t.widget<TextField>(field).controller!.text, 'kuhyx/');

    await t.enterText(field, 'kuhyx/');
    await t.tap(find.byKey(const ValueKey('repo-new-submit')));
    await _settle(t);
    expect(find.byKey(const ValueKey('repo-picker')), findsOneWidget);

    await t.enterText(field, 'kuhyx/fresh');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await _settle(t);

    final made = (await repo.listNotes()).single;
    expect(made.repo, 'kuhyx/fresh');
    expect(made.text, 'fresh todos\n\n## Ship it');
  });

  testWidgets('dismissing the picker changes nothing', (t) async {
    _phone(t);
    final repo = await _select(t, [note('p', 'Ship it')], ['Ship it']);
    await t.tapAt(const Offset(10, 40));
    await _settle(t);
    expect((await repo.listNotes()).single.id, 'p');
    expect(find.byKey(const ValueKey('selection-bar')), findsOneWidget);
  });

  testWidgets('a note already in a repo is refused with a block icon', (
    t,
  ) async {
    _phone(t);
    final repo = await _select(
      t,
      [_repoNote('r', 'app todos\n\n## Old', 'kuhyx/app')],
      ['app todos'],
    );
    await t.tap(find.byKey(const ValueKey('repo-kuhyx/app')));
    await _settle(t);

    expect((await repo.listNotes()).single.text, 'app todos\n\n## Old');
    expect(find.byIcon(Icons.block), findsOneWidget);
    expect(find.byKey(const ValueKey('selection-bar')), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    expect(find.byIcon(Icons.block), findsNothing);
  });
}
