// The repo-task fields on Note and the source facet of NoteFilter.
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';

Note _note(String id, {String? repo, String text = 'x'}) {
  final at = DateTime.utc(2026);
  return Note(
    id: id,
    text: text,
    priority: Priority.medium,
    status: Status.todo,
    createdAt: at,
    updatedAt: at,
    repo: repo,
  );
}

void main() {
  group('Note task fields', () {
    test('default to null, which makes a plain idea', () {
      final idea = _note('a');
      expect(idea.repo, isNull);
      expect(idea.doneCheck, isNull);
      expect(idea.by, isNull);
      expect(idea.evidence, isNull);
      expect(idea.isRepoTask, isFalse);
      expect(_note('b', repo: 'kuhyx/todo').isRepoTask, isTrue);
    });

    test('copyWith keeps them unless replaced', () {
      final task = _note(
        'a',
        repo: 'kuhyx/todo',
      ).copyWith(doneCheck: 'true', by: 'kuhy', evidence: 'e');
      final edited = task.copyWith(text: 'y');
      expect(edited.repo, 'kuhyx/todo');
      expect(edited.doneCheck, 'true');
      expect(edited.by, 'kuhy');
      expect(edited.evidence, 'e');
      expect(task.copyWith(repo: 'kuhyx/utils').repo, 'kuhyx/utils');
    });

    test('kNoteAuthors is exactly claude and kuhy', () {
      expect(kNoteAuthors, {'claude', 'kuhy'});
    });
  });

  group('NoteFilter repo facets', () {
    final idea = _note('idea');
    final todo = _note('t', repo: 'kuhyx/todo');
    final utils = _note('u', repo: 'kuhyx/utils');
    List<String> pass(NoteFilter f) => [
      for (final n in [idea, todo, utils])
        if (matchesFilter(n, f)) n.id,
    ];

    test('empty means every note, ideas included', () {
      expect(pass(const NoteFilter()), ['idea', 't', 'u']);
      expect(const NoteFilter().isEmpty, isTrue);
    });

    test('repoTasksOnly drops ideas', () {
      expect(pass(const NoteFilter(repoTasksOnly: true)), ['t', 'u']);
    });

    test('repo is plain equality', () {
      expect(pass(const NoteFilter(repo: 'kuhyx/utils')), ['u']);
      expect(pass(const NoteFilter(repo: 'utils')), isEmpty);
    });

    test('ANDs with the other facets', () {
      const f = NoteFilter(repoTasksOnly: true, query: 'zzz');
      expect(matchesFilter(todo, f), isFalse);
    });

    test('each counts as one facet and survives copyWith', () {
      const f = NoteFilter(repo: 'a/b', repoTasksOnly: true);
      expect(f.isEmpty, isFalse);
      expect(f.activeCount, 2);
      final g = f.copyWith(query: 'q');
      expect(g.repo, 'a/b');
      expect(g.repoTasksOnly, isTrue);
      expect(f.copyWith(repo: 'c/d', repoTasksOnly: false).repo, 'c/d');
      expect(f.copyWith(repoTasksOnly: false).repoTasksOnly, isFalse);
    });

    test('search also matches the repo name', () {
      expect(matchesFilter(utils, const NoteFilter(query: 'UTILS')), isTrue);
      expect(matchesFilter(idea, const NoteFilter(query: 'utils')), isFalse);
    });
  });
}
