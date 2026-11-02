// One open note per repo: the shared add path, the done_check composition
// and the one-time merge plan.
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/repo_note.dart';
import 'package:todo/data/repo_note_merge.dart';

const _repo = 'kuhyx/wake-alarm';

Note _n(
  String id,
  String text, {
  int day = 1,
  String repo = _repo,
  Status status = Status.todo,
  Priority priority = Priority.medium,
  String? doneCheck,
}) => Note(
  id: id,
  text: text,
  priority: priority,
  status: status,
  createdAt: DateTime.utc(2026, 10, day),
  updatedAt: DateTime.utc(2026, 10, day),
  repo: repo,
  doneCheck: doneCheck,
  by: 'claude',
);

void main() {
  group('composeDoneCheck', () {
    test('both present are wrapped and joined with &&', () {
      expect(composeDoneCheck('a', 'b'), '( a ) && ( b )');
    });
    test('only one present is kept as is', () {
      expect(composeDoneCheck('a', null), 'a');
      expect(composeDoneCheck(null, 'b'), 'b');
      expect(composeDoneCheck('', 'b'), 'b');
      expect(composeDoneCheck(null, null), isNull);
    });
  });

  group('addRepoTask', () {
    late NoteRepository repo;
    setUp(() async => repo = await NoteRepository.openInMemory());
    tearDown(() => repo.close());

    test('creates "<name> todos" with the task as the first section', () async {
      final r = await addRepoTask(
        repo,
        repo: _repo,
        title: 'Fix A',
        body: 'what: a',
        doneCheck: 'true',
        priority: Priority.high,
        by: 'claude',
      );
      expect(r.appended, isFalse);
      expect(r.note.text, 'wake-alarm todos\n\n## Fix A\nwhat: a');
      expect(r.note.doneCheck, 'true');
      expect(r.note.priority, Priority.high);
      expect(r.note.by, 'claude');
      expect(r.note.status, Status.todo);
    });

    test('appends to the open note: body, check, max priority', () async {
      final first = await addRepoTask(
        repo,
        repo: _repo,
        title: 'Fix A',
        body: 'what: a',
        doneCheck: 'test a',
        priority: Priority.high,
      );
      await repo.upsert(first.note);
      final second = await addRepoTask(
        repo,
        repo: _repo,
        title: 'Fix B',
        body: 'what: b',
        doneCheck: 'test b',
        priority: Priority.low,
      );
      expect(second.appended, isTrue);
      expect(second.note.id, first.note.id);
      expect(
        second.note.text,
        'wake-alarm todos\n\n## Fix A\nwhat: a\n\n## Fix B\nwhat: b',
      );
      expect(second.note.doneCheck, '( test a ) && ( test b )');
      expect(second.note.priority, Priority.high);
    });

    test('a missing check on either side keeps the other', () async {
      final first = await addRepoTask(repo, repo: _repo, title: 'A');
      await repo.upsert(first.note);
      final second = await addRepoTask(
        repo,
        repo: _repo,
        title: 'B\nCheck: manual',
        doneCheck: 'test b',
      );
      expect(second.note.doneCheck, 'test b');
      expect(second.note.text, contains('Check: manual'));
    });

    test('closed notes and other repos do not absorb the task', () async {
      await repo.upsert(_n('d', 'old\n\n## x', status: Status.done));
      await repo.upsert(_n('o', 'other\n\n## x', repo: 'kuhyx/other'));
      final r = await addRepoTask(repo, repo: _repo, title: 'Fix A');
      expect(r.appended, isFalse);
      expect(r.note.id, isNot(anyOf('d', 'o')));
    });

    test('an in-progress note counts as open; the oldest wins', () async {
      await repo.upsert(_n('new', 'T\n\n## n', day: 5));
      await repo.upsert(
        _n('old', 'T\n\n## o', day: 2, status: Status.inProgress),
      );
      final r = await addRepoTask(repo, repo: _repo, title: 'Z');
      expect(r.note.id, 'old');
    });
  });

  group('planRepoMerges', () {
    test('merges three notes into the oldest, sections oldest first', () {
      final plan = planRepoMerges([
        _n('b', 'Second\n\nbody b', day: 2, doneCheck: 'cb'),
        _n('a', 'First', day: 1, doneCheck: 'ca', priority: Priority.low),
        _n('c', 'Third\n\nbody c', day: 3, priority: Priority.high),
        _n('x', 'Elsewhere', repo: 'kuhyx/other', day: 1),
      ]);
      final m = plan.singleWhere((p) => p.kept.repo == _repo);
      expect(m.kept.id, 'a');
      expect(m.removed.map((n) => n.id), ['b', 'c']);
      expect(
        m.kept.text,
        'wake-alarm todos\n\n## First\n\n## Second\nbody b\n\n## Third\nbody c',
      );
      expect(m.kept.doneCheck, '( ca ) && ( cb )');
      expect(m.kept.priority, Priority.high);
    });

    test('single-note repos are retitled with the body as one section', () {
      final plan = planRepoMerges([_n('x', 'Only\n\nbody')]);
      expect(plan.single.removed, isEmpty);
      expect(plan.single.kept.text, 'wake-alarm todos\n\n## Only\nbody');
    });

    test('already merged repos are left alone (idempotent)', () {
      final merged = planRepoMerges([
        _n('a', 'One', day: 1),
        _n('b', 'Two', day: 2),
      ]).single.kept;
      expect(planRepoMerges([merged]), isEmpty);
    });

    test('a merged note plus a new one folds in without re-wrapping', () {
      final merged = _n('a', 'wake-alarm todos\n\n## One\nx', day: 1);
      final plan = planRepoMerges([merged, _n('b', 'Two\n\ny', day: 2)]);
      expect(
        plan.single.kept.text,
        'wake-alarm todos\n\n## One\nx\n\n## Two\ny',
      );
    });

    test('closed notes and plain ideas are ignored', () {
      final idea = Note(
        id: 'i',
        text: 'idea',
        priority: Priority.medium,
        status: Status.todo,
        createdAt: DateTime.utc(2026, 10),
        updatedAt: DateTime.utc(2026, 10),
      );
      expect(
        planRepoMerges([idea, _n('d', 'Done', status: Status.done)]),
        isEmpty,
      );
    });
  });
}
