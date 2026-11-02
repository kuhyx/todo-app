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

  group('NoteFilter.sources', () {
    final idea = _note('idea');
    final todo = _note('t', repo: 'kuhyx/todo');
    final utils = _note('u', repo: 'kuhyx/utils');
    List<String> pass(Set<String> sources) => [
      for (final n in [idea, todo, utils])
        if (matchesFilter(n, NoteFilter(sources: sources))) n.id,
    ];

    test('empty means every note', () {
      expect(pass({}), ['idea', 't', 'u']);
      expect(const NoteFilter().isEmpty, isTrue);
    });

    test('ideas only', () => expect(pass({kIdeasSource}), ['idea']));

    test('the Repo tasks source lets every repo task in', () {
      expect(pass({kRepoTasksSource}), ['t', 'u']);
      expect(pass({kIdeasSource, kRepoTasksSource}), ['idea', 't', 'u']);
    });

    test('a repo source lets only that repo in', () {
      expect(pass({'kuhyx/utils'}), ['u']);
      expect(pass({kIdeasSource, 'kuhyx/todo'}), ['idea', 't']);
    });

    test('ANDs with the other facets', () {
      final f = const NoteFilter(
        sources: {kRepoTasksSource},
      ).copyWith(query: 'zzz');
      expect(matchesFilter(todo, f), isFalse);
    });

    test('counts as one facet and survives copyWith', () {
      const f = NoteFilter(sources: {kIdeasSource});
      expect(f.isEmpty, isFalse);
      expect(f.activeCount, 1);
      expect(f.copyWith(query: 'q').sources, {kIdeasSource});
      expect(f.copyWith(sources: {}).sources, isEmpty);
    });

    test('search also matches the repo name', () {
      expect(matchesFilter(utils, const NoteFilter(query: 'UTILS')), isTrue);
      expect(matchesFilter(idea, const NoteFilter(query: 'utils')), isFalse);
    });
  });
}
