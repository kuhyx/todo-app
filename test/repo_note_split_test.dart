// new_note: a second open note per repo, the duplicate guard that merges
// into it, and the shared add path that never joins such a note.
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/repo_note.dart';
import 'package:todo/data/repo_note_merge.dart';
import 'package:todo/data/repo_note_split.dart';

const _repo = 'kuhyx/herosi';

Note _n(String id, String text, {int day = 1, String repo = _repo}) => Note(
  id: id,
  text: text,
  priority: Priority.medium,
  status: Status.todo,
  createdAt: DateTime.utc(2026, 10, day),
  updatedAt: DateTime.utc(2026, 10, day),
  repo: repo,
  doneCheck: 'old',
);

Future<Note> _get(NoteRepository r, String id) async =>
    (await r.listNotes()).singleWhere((n) => n.id == id);

void main() {
  late NoteRepository repo;
  setUp(() async => repo = await NoteRepository.openInMemory());
  tearDown(() => repo.close());

  Future<SplitAdd> add(String title, {Future<bool> Function(Note)? busy}) =>
      addSeparateTask(
        repo,
        repo: _repo,
        title: title,
        body: 'what',
        doneCheck: 'new',
        priority: Priority.high,
        by: 'claude',
        busy: busy,
      );

  final shared = _n('aaaaaaaa-shared', 'herosi todos\n\n## Mędrzec\nlisted');

  test('C1: builds a second open note, the shared one untouched', () async {
    await repo.upsert(shared);
    final r = await add('Mędrzec');
    expect(r.kind, SplitKind.added);
    expect(r.note.id, isNot(shared.id));
    expect(r.note.text, 'herosi todos: Mędrzec\n\n## Mędrzec\nwhat');
    expect(r.note.doneCheck, 'new');
    expect(isSeparateNote(r.note), isTrue);
    expect(isSeparateNote(shared), isFalse);
    expect((await _get(repo, shared.id)).text, shared.text);
  });

  test('C2: a plain add joins the shared note, never a separate one', () async {
    final split = _n('00000000-split', 'herosi todos: Old\n\n## Old\nx');
    await repo.upsert(split);
    await repo.upsert(_n('bbbbbbbb-shared', shared.text, day: 2));
    final r = await addRepoTask(repo, repo: _repo, title: 'B');
    expect(r.appended, isTrue);
    expect(r.note.id, 'bbbbbbbb-shared');
    await repo.upsert(
      _n('bbbbbbbb-shared', 'x', day: 2).copyWith(status: Status.done),
    );
    final fresh = await addRepoTask(repo, repo: _repo, title: 'C');
    expect(fresh.appended, isFalse);
    expect(fresh.note.text, startsWith('herosi todos\n'));
  });

  test('C3: an exact title in another separate note merges into it', () async {
    final x = _n('cccccccc-x', 'herosi todos: Młody\n\n## Młody\nfirst');
    await repo.upsert(x);
    final r = await add('Młody');
    expect(r.kind, SplitKind.merged);
    expect(r.note.id, x.id);
    expect(r.note.text, '${x.text}\n\n## Młody\nwhat');
    expect(r.note.doneCheck, '( old ) && ( new )');
    expect(r.note.priority, Priority.high);
  });

  test('C4: shared-note, other-repo, done or near hits do not merge', () async {
    await repo.upsert(shared);
    await repo.upsert(
      _n('dddddddd-o', 'x todos: Hekser\n\n## Hekser\n', repo: 'kuhyx/x'),
    );
    await repo.upsert(_n('eeeeeeee-d', 'herosi todos: H\n\n## [x] Hekser\n'));
    await repo.upsert(_n('ffffffff-c', 'herosi todos: H\n\n## hekser \n'));
    await repo.upsert(
      _n('99999999-f', 'herosi todos: H\n\n```\n## Hekser\n```'),
    );
    expect((await add('Hekser')).kind, SplitKind.added);
    expect((await add('Mędrzec')).kind, SplitKind.added);
  });

  test(
    'C5: a running target is not edited; a separate note says why',
    () async {
      final x = _n('cccccccc-x', 'herosi todos: Młody\n\n## Młody\nfirst');
      await repo.upsert(x);
      final seen = <String>[];
      final r = await add(
        'Młody',
        busy: (n) async {
          seen.add(n.id);
          return true;
        },
      );
      expect(seen, [x.id]);
      expect(r.kind, SplitKind.fellBack);
      expect(r.note.id, isNot(x.id));
      expect(r.why, contains('cccccccc'));
      expect((await _get(repo, x.id)).text, x.text);
    },
  );

  test('C10: the one-time merge plans nothing for separate notes', () {
    final notes = [
      _n('a', 'herosi todos\n\n## One\nx', day: 1),
      _n('b', 'herosi todos: Two\n\n## Two\ny', day: 2),
      _n('c', 'herosi todos: Three\n\n## Three\nz', day: 3),
    ];
    expect(planRepoMerges(notes), isEmpty);
    final legacy = planRepoMerges([...notes, _n('d', 'Legacy\n\nl', day: 4)]);
    expect(legacy.single.kept.id, 'a');
    expect(legacy.single.removed.map((n) => n.id), ['d']);
  });

  group('startBlock', () {
    test('a real check and a normal body may start', () {
      expect(startBlock('test -f x', 'what'), isNull);
    });
    test('C6: none or low priority never starts', () {
      expect(startBlock(null, 'what'), 'done_check is none');
      expect(startBlock(' None ', 'what'), 'done_check is none');
      expect(startBlock('x', '\nLow priority\nrest'), 'marked low priority');
    });
  });
}
