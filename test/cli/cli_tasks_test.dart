// Repo tasks through the CLI: create, list, search, close, id prefixes.
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/cli/cli_session.dart';

import 'cli_harness.dart';
import 'scripted_session.dart';

void main() {
  late CliHarness h;
  setUp(() => h = CliHarness());
  tearDown(() => h.dispose());

  Future<String> addTask(String text, String repo) => h.add(text, [
    '--repo',
    repo,
    '--done-check',
    'test -f "a b"',
    '--by',
    'claude',
  ]);

  test('a task created on one node shows its fields on another', () async {
    final id = await addTask('Fix gate', 'kuhyx/todo');
    expect(await h.run(['--get', id, '--data-dir', h.dir('b')]), 0);
    expect(
      h.out.toString(),
      allOf(
        contains('repo: kuhyx/todo'),
        contains('done_check: test -f "a b"'),
        contains('by: claude'),
        isNot(contains('evidence:')),
      ),
    );
  });

  test('--list filters by repo and status, one compact line each', () async {
    final todo = await addTask('Fix gate', 'kuhyx/todo');
    await addTask('Other', 'kuhyx/utils');
    await h.add('Plain idea');

    expect(await h.run(['--list', '--repo', 'kuhyx/todo']), 0);
    expect(
      h.out.toString(),
      '${todo.substring(0, 8)}\ttodo\tmedium\tkuhyx/todo\ttodo todos\n',
    );
    expect(await h.run(['--list', '--status', 'done']), 0);
    expect(h.out.toString(), isEmpty);
    expect(await h.run(['--list']), 0);
    expect(h.out.toString().trim().split('\n'), hasLength(3));
  });

  test('--search matches text and repo, case-insensitively', () async {
    await addTask('Fix the GATE', 'kuhyx/todo');
    await addTask('Other', 'kuhyx/utils');
    expect(await h.run(['--search', 'gate']), 0);
    expect(h.out.toString(), contains('\tkuhyx/todo\ttodo todos'));
    expect(h.out.toString(), isNot(contains('utils todos')));
    expect(await h.run(['--search', 'UTILS', '--repo', 'kuhyx/utils']), 0);
    expect(h.out.toString(), contains('utils todos'));
  });

  test('--close without evidence exits 2 before any network', () async {
    expect(await h.run(['--close', 'abcdefgh']), 2);
    expect(h.err.toString(), contains('--close needs --evidence'));
    expect(h.db.methods, isEmpty);
  });

  test(
    '--close by 8-char prefix sets done and evidence, keeps the note',
    () async {
      final id = await addTask('Fix gate', 'kuhyx/todo');
      final prefix = id.substring(0, 8);
      expect(
        await h.run([
          '--close', prefix, '--evidence', 'abc1234 exit 0', //
          '--data-dir', h.dir('b'),
        ]),
        0,
      );
      expect(h.out.toString().trim(), 'closed $id');
      expect(await h.run(['--get', prefix, '--data-dir', h.dir('c')]), 0);
      expect(h.out.toString(), contains('status: done'));
      expect(h.out.toString(), contains('evidence: abc1234 exit 0'));
      expect(h.out.toString(), contains('repo: kuhyx/todo'));
    },
  );

  test(
    'every id flag accepts a prefix; ambiguity names the candidates',
    () async {
      h.seedPeer([
        fixtureNote('12345678-a', 'First'),
        fixtureNote('12345678-b', 'Second'),
        fixtureNote('87654321-c', 'Third'),
      ]);
      expect(await h.run(['--set-status', '87654321', 'in_progress']), 0);
      expect(h.out.toString().trim(), '87654321-c\tin_progress');
      expect(await h.run(['--get', '12345678']), 1);
      expect(h.err.toString(), contains('12345678-a  First'));
      expect(h.err.toString(), contains('12345678-b  Second'));
      expect(await h.run(['--delete', '12345678']), 1);
      expect(await h.run(['--close', 'ffffffff', '--evidence', 'e']), 1);
      expect(h.err.toString(), contains('no live note with id ffffffff'));
      expect(await h.run(['--delete', '87654321']), 0);
    },
  );

  test('--close fails when the push reports nothing published', () async {
    Future<CliSession> opener(String d, {required String seedCredentials}) =>
        ScriptedSession.create(h.db.client, [true, false], noteId: 'stuck');
    expect(
      await h.run(['--close', 'stuck', '--evidence', 'e'], opener: opener),
      1,
    );
    expect(h.err.toString(), contains('close saved locally'));
  });
}
