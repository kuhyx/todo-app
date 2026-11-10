/// Assigning plain notes to a repo: sections in its one open note.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/repo_assign.dart';
import 'package:todo/data/repo_note_split.dart';

import 'note_repository_helpers.dart';

Future<NoteRepository> _repo(List<Note> seed) async {
  final repo = await NoteRepository.openInMemory();
  addTearDown(repo.close);
  for (final n in seed) {
    await repo.upsert(n);
  }
  return repo;
}

Note _task(String id, String text, String repo, {Status? status}) =>
    noteFixture(
      id,
      text,
      status: status ?? Status.todo,
      createdAt: DateTime(2026),
    ).copyWith(repo: repo, doneCheck: 'true');

void main() {
  test('appends each plain note as one section and removes it', () async {
    final repo = await _repo([
      _task('r', 'app todos\n\n## Old\nbody', 'kuhyx/app'),
      _task('closed', 'app todos\n\n## x', 'kuhyx/app', status: Status.done),
      noteFixture('p1', 'Fix login\n\n## what\n_why_\nit 500s'),
      noteFixture('p2', 'Tidy', priority: Priority.high),
    ]);
    final plain = (await repo.listNotes()).where((n) => n.repo == null).toList()
      ..sort((a, b) => a.id.compareTo(b.id));

    // Sections land in the order given (the UI passes selection order).
    final refused = await assignToRepo(repo, plain, 'kuhyx/app');

    expect(refused, isEmpty);
    final notes = {for (final n in await repo.listNotes()) n.id: n};
    expect(notes.keys, unorderedEquals(['r', 'closed']));
    final text = notes['r']!.text;
    expect(openSections(text), ['Old', 'Fix login', 'Tidy']);
    expect(text, contains('### what\n_why_\nit 500s'));
    expect(notes['r']!.priority, Priority.high);
    expect(notes['r']!.doneCheck, 'true');
  });

  test('creates the repo note when the repo has none open', () async {
    final repo = await _repo([noteFixture('p', 'Ship it\nnow')]);

    await assignToRepo(repo, await repo.listNotes(), 'kuhyx/new-app');

    final made = (await repo.listNotes()).single;
    expect(made.id, isNot('p'));
    expect(made.repo, 'kuhyx/new-app');
    expect(made.status, Status.todo);
    expect(made.createdBy, 'kuhy');
    expect(made.text, 'new-app todos\n\n## Ship it\nnow');
  });

  test('refuses notes that already have a repo, moves the rest', () async {
    final repo = await _repo([
      _task('t', 'other todos\n\n## A', 'kuhyx/other'),
      noteFixture('p', 'Plain'),
    ]);

    final refused = await assignToRepo(
      repo,
      await repo.listNotes(),
      'kuhyx/app',
    );

    expect(refused.map((n) => n.id), ['t']);
    final notes = {for (final n in await repo.listNotes()) n.id: n};
    expect(notes['t']!.text, 'other todos\n\n## A');
    expect(notes.containsKey('p'), isFalse);
  });

  test('only repo notes: a no-op that returns them all', () async {
    final repo = await _repo([_task('t', 'other todos', 'kuhyx/other')]);
    final before = repo.exportLog();
    final refused = await assignToRepo(
      repo,
      await repo.listNotes(),
      'kuhyx/app',
    );
    expect(refused, hasLength(1));
    expect(repo.exportLog(), before);
  });

  test('demoteHeadings keeps a body inside its section', () {
    expect(
      demoteHeadings('# a\n## b\n### c\n```\n## code\n```\ntext #x'),
      '### a\n### b\n#### c\n```\n## code\n```\ntext #x',
    );
  });

  test('isRepoName accepts owner/name only', () {
    expect(isRepoName('kuhyx/todo-app'), isTrue);
    expect(isRepoName('kuhyx/'), isFalse);
    expect(isRepoName('todo'), isFalse);
    expect(isRepoName('a/b/c'), isFalse);
  });
}
