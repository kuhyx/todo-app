// `--repo` adds keep ONE open note per repo; the merge tool collapses the
// notes that existed before the invariant.
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/cli/cli_session.dart';
import 'package:todo/cli/merge_repo_notes.dart';

import 'cli_harness.dart';
import 'scripted_session.dart';

void main() {
  late CliHarness h;
  setUp(() => h = CliHarness());
  tearDown(() => h.dispose());

  Future<String> addTask(String text, {String check = 'true'}) =>
      h.add(text, ['--repo', 'kuhyx/wake-alarm', '--done-check', check]);

  test(
    'the second --repo add appends to the first and reuses its id',
    () async {
      final first = await addTask('Fix A\n\nwhat: a', check: 'ca');
      expect(
        await h.run([
          '--data-dir',
          h.dir('a'),
          '--text',
          'Fix B\n\nwhat: b',
          '--repo',
          'kuhyx/wake-alarm',
          '--done-check',
          'cb',
        ]),
        0,
      );
      expect(h.out.toString().trim(), first);
      expect(h.err.toString(), contains('appended'));

      expect(await h.run(['--get', first, '--data-dir', h.dir('b')]), 0);
      expect(
        h.out.toString(),
        allOf(
          contains('wake-alarm todos'),
          contains('## Fix A\nwhat: a'),
          contains('## Fix B\nwhat: b'),
          contains('done_check: ( ca ) && ( cb )'),
        ),
      );
      expect(await h.run(['--list', '--repo', 'kuhyx/wake-alarm']), 0);
      expect(h.out.toString().trim().split('\n'), hasLength(1));
    },
  );

  test('notes without --repo are never merged', () async {
    await h.add('idea one');
    await h.add('idea two');
    expect(await h.run(['--list']), 0);
    expect(h.out.toString().trim().split('\n'), hasLength(2));
  });

  group('merge tool', () {
    Future<int> merge(List<String> extra, String data) => runMergeRepoNotes(
      ['--data-dir', h.dir(data), ...extra],
      env: h.env,
      out: h.out,
      err: h.err,
      open: (d, {required seedCredentials}) => h.open(d, seedCredentials),
    );

    void seed() => h.seedPeer([
      fixtureNote('11111111-a', 'First', repo: 'kuhyx/wake-alarm'),
      fixtureNote('22222222-b', 'Second\n\nbody', repo: 'kuhyx/wake-alarm'),
      fixtureNote('33333333-c', 'Third', repo: 'kuhyx/wake-alarm'),
      fixtureNote('44444444-d', 'Lone', repo: 'kuhyx/todo'),
      fixtureNote('55555555-e', 'An idea'),
    ]);

    test('dry run changes nothing and prints nothing but the map', () async {
      seed();
      expect(await merge([], 'a'), 0);
      expect(h.out.toString().trim().split('\n'), [
        '22222222-b\t11111111-a\tkuhyx/wake-alarm',
        '33333333-c\t11111111-a\tkuhyx/wake-alarm',
      ]);
      expect(await h.run(['--list', '--data-dir', h.dir('b')]), 0);
      expect(h.out.toString().trim().split('\n'), hasLength(5));
    });

    test('apply keeps the oldest id, deletes the rest, syncs', () async {
      seed();
      expect(await merge(['--apply'], 'a'), 0);
      expect(h.out.toString(), contains('22222222-b\t11111111-a'));
      expect(await h.run(['--list', '--data-dir', h.dir('b')]), 0);
      final lines = h.out.toString().trim().split('\n');
      expect(lines, hasLength(3));
      expect(lines.where((l) => l.contains('kuhyx/wake-alarm')), hasLength(1));
      expect(await h.run(['--get', '11111111', '--data-dir', h.dir('b')]), 0);
      expect(
        h.out.toString(),
        allOf(
          contains('wake-alarm todos'),
          contains('## First'),
          contains('## Second\nbody'),
          contains('## Third'),
        ),
      );
      expect(await h.run(['--get', '44444444', '--data-dir', h.dir('b')]), 0);
      expect(h.out.toString(), contains('todo todos'));
    });

    test('a second apply is a no-op', () async {
      seed();
      expect(await merge(['--apply'], 'a'), 0);
      h.out.clear();
      expect(await merge(['--apply'], 'a'), 0);
      expect(h.out.toString().trim(), isEmpty);
    });

    test('--dry-run is accepted and a missing session is an error', () async {
      final code = await runMergeRepoNotes(
        ['--dry-run'],
        env: {'HOME': h.tmp.path, 'XDG_DATA_HOME': h.dir('xdg2')},
        out: h.out,
        err: h.err,
      );
      expect(code, 1);
      expect(h.err.toString(), contains('no Firebase session'));
    });

    test('a push that publishes nothing fails the run', () async {
      final code = await runMergeRepoNotes(
        ['--apply'],
        env: h.env,
        out: h.out,
        err: h.err,
        open: (d, {required seedCredentials}) async {
          final s = await ScriptedSession.create(h.db.client, [true, false]);
          await s.repository.upsert(
            fixtureNote('x', 'Lone', repo: 'kuhyx/todo'),
          );
          return s;
        },
      );
      expect(code, 1);
      expect(h.err.toString(), contains('nothing was pushed'));
    });

    test('unknown flags are a usage error', () async {
      expect(await merge(['--bogus'], 'a'), 2);
    });
  });
}
