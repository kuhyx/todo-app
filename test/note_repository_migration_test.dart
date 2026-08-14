/// Schema migrations from the legacy sqlite_crdt database.
///
/// One of four files `note_repository_test.dart` was split into for the
/// 250-line cap. Each carries its own `setUpAll(sqfliteFfiInit)`: without it
/// sqflite is never initialised and every test in the file fails.
library;

import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// SqliteCrdt is needed to seed the legacy DB in migration tests; hide its Hlc
// so the crdt_sync Hlc/Record are unambiguous.
import 'package:sqlite_crdt/sqlite_crdt.dart' hide Hlc;
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/data/repository_factory_io.dart';

import 'note_repository_helpers.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('v2→v3 migration backfills priority 0 to medium', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('todo_migration');
    final path = '${dir.path}/todo.db';
    addTearDown(() => dir.delete(recursive: true));

    // Build a v2 database (status column present, no priority backfill) and
    // insert a legacy note with the old priority 0 ("none").
    final v2 = await SqliteCrdt.open(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE notes (
            id TEXT NOT NULL,
            text TEXT NOT NULL DEFAULT '',
            priority INTEGER NOT NULL DEFAULT 0,
            status INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (id)
          )
        ''');
      },
    );
    final now = DateTime.now().toIso8601String();
    await v2.execute(
      'INSERT INTO notes (id, text, priority, status, created_at, updated_at) '
      'VALUES (?1, ?2, ?3, ?4, ?5, ?6)',
      ['legacy', 'old idea', 0, 0, now, now],
    );
    await v2.close();

    // Reopening through the repository runs onUpgrade to v3.
    final repo = await openRepositoryIn(p.dirname(path));
    addTearDown(repo.close);
    final notes = await repo.listNotes();

    expect(notes.single.id, 'legacy');
    expect(notes.single.priority, Priority.medium);
  });

  test('v1→v2 migration adds the status column with a default', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('todo_migration_v1');
    final path = '${dir.path}/todo.db';
    addTearDown(() => dir.delete(recursive: true));

    // v1 schema predates the status column entirely.
    final v1 = await SqliteCrdt.open(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE notes (
            id TEXT NOT NULL,
            text TEXT NOT NULL DEFAULT '',
            priority INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (id)
          )
        ''');
      },
    );
    final now = DateTime.now().toIso8601String();
    await v1.execute(
      'INSERT INTO notes (id, text, priority, created_at, updated_at) '
      'VALUES (?1, ?2, ?3, ?4, ?5)',
      ['old', 'pre-status idea', 1, now, now],
    );
    await v1.close();

    // Reopening runs onUpgrade v1→v2 (adds status, default todo) then v2→v3.
    final repo = await openRepositoryIn(p.dirname(path));
    addTearDown(repo.close);
    final notes = await repo.listNotes();
    expect(notes.single.id, 'old');
    expect(notes.single.status, Status.todo); // backfilled default
  });

  group('migration from a legacy sqlite_crdt database', () {
    // Writes a v3 legacy DB at [path] with one live note and one tombstone,
    // exactly as the pre-crdt_sync app would have left it.
    Future<String> seedLegacyDb(String dir) async {
      final path = '$dir/todo.db';
      final legacy = await SqliteCrdt.open(
        path,
        version: 3,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE notes (
              id TEXT NOT NULL,
              text TEXT NOT NULL DEFAULT '',
              priority INTEGER NOT NULL DEFAULT 2,
              status INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              PRIMARY KEY (id)
            )
          ''');
        },
      );
      Future<void> insert(String id, String text, int status) => legacy.execute(
        'INSERT INTO notes (id, text, priority, status, created_at, '
        'updated_at) VALUES (?1, ?2, 3, ?3, ?4, ?4)',
        [id, text, status, '2026-01-01T00:00:00.000'],
      );
      await insert('live', 'kept idea', Status.inProgress.value);
      await insert('gone', 'deleted idea', Status.todo.value);
      await legacy.execute('DELETE FROM notes WHERE id = ?1', ['gone']);
      await legacy.close();
      return path;
    }

    test('imports live notes and preserves tombstones, once', () async {
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('todo_migrate');
      addTearDown(() => dir.delete(recursive: true));
      final path = await seedLegacyDb(dir.path);

      final repo = await openRepositoryIn(p.dirname(path));
      addTearDown(repo.close);

      // The live note migrated with its fields intact...
      final notes = await repo.listNotes();
      expect(notes.map((n) => n.text), ['kept idea']);
      expect(notes.single.priority, Priority.high);
      expect(notes.single.status, Status.inProgress);
      // ...and the deletion carried over as a sticky tombstone.
      expect(repo.exportLog()['gone']!.deleted, isTrue);
      expect(repo.nodeId, isNotEmpty);

      // Reopening does not re-run migration: a note added after the first open
      // survives, and the (still-present) legacy DB is not re-imported.
      await repo.upsert(noteFixture('new', 'added post-migration'));
      await repo.close();
      final reopened = await openRepositoryIn(p.dirname(path));
      addTearDown(reopened.close);
      final texts = (await reopened.listNotes()).map((n) => n.text).toSet();
      expect(texts, {'kept idea', 'added post-migration'});
    });

    test('a fresh install with no legacy DB starts empty', () async {
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('todo_fresh');
      addTearDown(() => dir.delete(recursive: true));

      final repo = await openRepositoryIn(dir.path);
      addTearDown(repo.close);

      expect(await repo.listNotes(), isEmpty);
      expect(repo.nodeId, isNotEmpty);
    });
  });
}
