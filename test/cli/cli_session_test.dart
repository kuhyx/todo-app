import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/cli/cli_session.dart';
import 'package:todo/data/note.dart';

import 'fake_rtdb.dart';

void main() {
  late Directory tmp;
  late FakeRtdb db;
  late String seed;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('cli_session_test');
    db = FakeRtdb();
    seed = writeSeedCredentials(tmp).path;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<CliSession> open(String name, {String? seedPath}) => CliSession.open(
    '${tmp.path}/$name',
    seedCredentials: seedPath ?? seed,
    httpClient: db.client,
  );

  Note note(String id) {
    final now = DateTime.utc(2026);
    return Note(
      id: id,
      text: 'Title\nbody',
      priority: Priority.medium,
      status: Status.todo,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('defaultDataDir', () {
    test('prefers XDG_DATA_HOME', () {
      expect(
        defaultDataDir({'XDG_DATA_HOME': '/x', 'HOME': '/h'}),
        '/x/todo-cli',
      );
    });

    test('falls back to ~/.local/share', () {
      expect(defaultDataDir({'HOME': '/h'}), '/h/.local/share/todo-cli');
      expect(
        defaultDataDir({'XDG_DATA_HOME': '', 'HOME': '/h'}),
        '/h/.local/share/todo-cli',
      );
    });

    test('survives a missing HOME', () {
      expect(defaultDataDir({}), '.local/share/todo-cli');
    });
  });

  group('open', () {
    test('creates an owner-only data dir and persists one node id', () async {
      final first = await open('data');
      final nodeId = first.repository.nodeId;
      await first.close();
      final dir = Directory('${tmp.path}/data');
      expect(dir.statSync().mode & 0x1ff, 448); // 0700
      expect(
        File('${dir.path}/${CliSession.nodeIdFileName}').readAsStringSync(),
        '$nodeId\n',
      );

      final second = await open('data');
      expect(second.repository.nodeId, nodeId);
      await second.close();
    });

    test('mints a fresh id when the stored one is blank', () async {
      Directory('${tmp.path}/blank').createSync();
      File(
        '${tmp.path}/blank/${CliSession.nodeIdFileName}',
      ).writeAsStringSync('  \n');
      final session = await open('blank');
      expect(session.repository.nodeId, isNotEmpty);
      await session.close();
    });

    test('fails without a Firebase session, naming the seed', () async {
      final missing = '${tmp.path}/missing.json';
      await expectLater(
        open('nosession', seedPath: missing),
        throwsA(
          isA<FirebaseAuthError>().having(
            (e) => e.toString(),
            'message',
            contains(missing),
          ),
        ),
      );
    });
  });

  group('sync', () {
    test('a pull-only sync never writes to the database', () async {
      final session = await open('pull');
      await session.repository.upsert(note('n1'));
      final result = await session.sync(push: false);
      expect(result.pushed, isTrue); // SyncService reports its own intent.
      expect(db.methods, isNot(contains('PUT')));
      expect(db.files, isEmpty);
      await session.close();
    });

    test('a push publishes the log, then skips an unchanged one', () async {
      final session = await open('push');
      await session.repository.upsert(note('n1'));
      final first = await session.sync(push: true);
      expect(first.pushed, isTrue);
      final node = session.repository.nodeId;
      expect(db.files.keys, contains('todo-sync/notes/$node~2Ejson'));
      expect(db.files.keys, contains('todo-sync/revs/$node'));
      expect(
        File('${tmp.path}/push/${CliSession.syncStateFileName}').existsSync(),
        isTrue,
      );

      final second = await session.sync(push: true);
      expect(second.pushed, isFalse);
      await session.close();
    });

    test('a second node sees the first node note', () async {
      final a = await open('a');
      await a.repository.upsert(note('shared'));
      await a.sync(push: true);
      await a.close();

      final b = await open('b');
      final result = await b.sync(push: false);
      expect(result.mergedDevices, 1);
      expect((await b.repository.listNotes()).single.id, 'shared');
      await b.close();
    });
  });
}
