import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/cli/cli_runner.dart';
import 'package:todo/cli/cli_session.dart';

import 'fake_rtdb.dart';
import 'scripted_session.dart';

void main() {
  late Directory tmp;
  late FakeRtdb db;
  late Map<String, String> env;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cli_runner_test');
    db = FakeRtdb();
    final home = Directory('${tmp.path}/home')..createSync();
    Directory('${home.path}/.config/todo').createSync(recursive: true);
    writeSeedCredentials(
      tmp,
    ).copySync('${home.path}/.config/todo/firebase_auth.json');
    env = {'HOME': home.path, 'XDG_DATA_HOME': '${tmp.path}/xdg'};
    out = StringBuffer();
    err = StringBuffer();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<CliSession> open(String dir, {required String seedCredentials}) =>
      CliSession.open(
        dir,
        seedCredentials: seedCredentials,
        httpClient: db.client,
      );

  Future<int> run(
    List<String> argv, {
    String stdin = '',
    SessionOpener? opener,
  }) async {
    out.clear();
    err.clear();
    return await runCli(
      argv,
      env: env,
      out: out,
      err: err,
      readStdin: () async => stdin,
      open: opener ?? open,
    );
  }

  String dir(String name) => '${tmp.path}/$name';

  Future<String> add(
    String name,
    String text, [
    List<String> extra = const [],
  ]) async {
    expect(await run(['--data-dir', dir(name), '--text', text, ...extra]), 0);
    return out.toString().trim();
  }

  group('argument handling', () {
    test('--help prints usage and exits 0', () async {
      expect(await run(['--help']), 0);
      expect(out.toString(), contains('Usage: dart run bin/todo_note.dart'));
    });

    test('a bad flag prints the error and usage, exits 2', () async {
      expect(await run(['--nope']), 2);
      expect(err.toString(), contains('unknown argument: --nope'));
      expect(err.toString(), contains('Usage:'));
    });

    test('an empty note is refused before touching the network', () async {
      expect(await run(['--data-dir', dir('d')], stdin: '  \n'), 2);
      expect(err.toString(), contains('empty note'));
      expect(db.methods, isEmpty);
    });
  });

  group('add', () {
    test('pushes an ordinary CRDT log and prints the new id', () async {
      final id = await add('a', 'Title\n\nbody', ['--priority', 'high']);
      expect(id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(db.files.keys.where((k) => k.contains('notes/')), hasLength(1));
      expect(err.toString(), isEmpty);
    });

    test('reads the text from stdin when --text is absent', () async {
      expect(await run(['--data-dir', dir('a')], stdin: 'From stdin'), 0);
      expect(await run(['--list', '--data-dir', dir('a')]), 0);
      expect(out.toString(), contains('\tmedium\ttodo\tFrom stdin'));
    });

    test('uses the XDG data dir by default', () async {
      expect(await run(['--text', 'Default dir']), 0);
      expect(Directory('${tmp.path}/xdg/todo-cli').existsSync(), isTrue);
    });

    test('fails when the push reports nothing published', () async {
      Future<CliSession> opener(String d, {required String seedCredentials}) =>
          ScriptedSession.create(db.client, [false]);
      expect(await run(['--text', 'x'], opener: opener), 1);
      expect(err.toString(), contains('saved locally but nothing was pushed'));
    });
  });

  group('list and get', () {
    test('a second node lists and gets what the first one added', () async {
      final id = await add('a', 'Title\n\nbody', [
        '--priority',
        'high',
        '--status',
        'in_progress',
      ]);

      expect(await run(['--list', '--data-dir', dir('b')]), 0);
      expect(out.toString().trim(), '$id\thigh\tin_progress\tTitle');

      expect(await run(['--get', id, '--data-dir', dir('b')]), 0);
      expect(out.toString(), contains('id: $id'));
      expect(out.toString(), contains('priority: high'));
      expect(out.toString(), contains('status: in_progress'));
      expect(out.toString(), contains('---\nTitle\n\nbody'));
    });

    test('--get of an unknown id exits 1', () async {
      expect(await run(['--get', 'nope', '--data-dir', dir('b')]), 1);
      expect(err.toString(), contains('no live note with id nope'));
    });

    test('an unmergeable peer file is reported as a warning', () async {
      db.files['todo-sync/notes/bad~2Ejson'] = 'not json';
      expect(await run(['--list', '--data-dir', dir('b')]), 0);
      expect(err.toString(), contains('could not merge peer file bad.json'));
    });
  });

  group('delete', () {
    test('tombstones a note created elsewhere and pushes', () async {
      final id = await add('a', 'Gone soon');
      expect(await run(['--delete', id, '--data-dir', dir('b')]), 0);
      expect(out.toString().trim(), 'deleted $id');

      expect(await run(['--list', '--data-dir', dir('c')]), 0);
      expect(out.toString().trim(), isEmpty);
    });

    test('an unknown id exits 1', () async {
      expect(await run(['--delete', 'nope', '--data-dir', dir('b')]), 1);
      expect(err.toString(), contains('no live note with id nope'));
    });

    test('fails when the deletion push reports nothing published', () async {
      Future<CliSession> opener(String d, {required String seedCredentials}) =>
          ScriptedSession.create(db.client, [true, false], noteId: 'stuck');
      expect(await run(['--delete', 'stuck'], opener: opener), 1);
      expect(err.toString(), contains('deletion saved locally'));
    });
  });

  group('set-status', () {
    test('changes the status of a note created elsewhere and pushes', () async {
      final id = await add('a', 'Ship it', ['--priority', 'high']);
      expect(
        await run(['--set-status', id, 'done', '--data-dir', dir('b')]),
        0,
      );
      expect(out.toString().trim(), '$id\tdone');

      expect(await run(['--get', id, '--data-dir', dir('c')]), 0);
      expect(out.toString(), contains('status: done'));
      expect(out.toString(), contains('priority: high'));
      expect(out.toString(), contains('---\nShip it'));
    });

    test('an unknown id exits 1', () async {
      expect(
        await run(['--set-status', 'nope', 'done', '--data-dir', dir('b')]),
        1,
      );
      expect(err.toString(), contains('no live note with id nope'));
    });

    test('fails when the status push reports nothing published', () async {
      Future<CliSession> opener(String d, {required String seedCredentials}) =>
          ScriptedSession.create(db.client, [true, false], noteId: 'stuck');
      expect(await run(['--set-status', 'stuck', 'done'], opener: opener), 1);
      expect(err.toString(), contains('status change saved locally'));
    });
  });

  group('failures', () {
    test('a missing Firebase session exits 1 with re-seed advice', () async {
      File('${env['HOME']}/.config/todo/firebase_auth.json').deleteSync();
      expect(await run(['--list', '--data-dir', dir('a')]), 1);
      expect(err.toString(), contains('seed_session.py'));
    });

    test('a rejected database exits 1', () async {
      db.failWith = 403;
      expect(await run(['--list', '--data-dir', dir('a')]), 1);
      expect(err.toString(), contains('rejected: HTTP 403'));
    });

    test('a filesystem failure exits 1', () async {
      Future<CliSession> boom(String d, {required String seedCredentials}) =>
          throw const FileSystemException('disk full');
      expect(await run(['--list'], opener: boom), 1);
      expect(err.toString(), contains('disk full'));
    });
  });
}
