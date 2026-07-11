import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// SqliteCrdt is needed to seed the legacy DB in migration tests; hide its Hlc
// so the crdt_sync Hlc/Record are unambiguous.
import 'package:sqlite_crdt/sqlite_crdt.dart' hide Hlc;
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  Note note(
    String id,
    String text, {
    Priority priority = Priority.medium,
    Status status = Status.todo,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final now = DateTime.now();
    return Note(
      id: id,
      text: text,
      priority: priority,
      status: status,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
    );
  }

  test('upsert then list returns the note', () async {
    final repo = await NoteRepository.openInMemory();
    addTearDown(repo.close);

    await repo.upsert(note('a', 'first idea'));
    final notes = await repo.listNotes();

    expect(notes, hasLength(1));
    expect(notes.single.text, 'first idea');
  });

  test('deleted notes are excluded from reads (tombstone filter)', () async {
    final repo = await NoteRepository.openInMemory();
    addTearDown(repo.close);

    await repo.upsert(note('a', 'keep me'));
    await repo.upsert(note('b', 'delete me'));
    await repo.delete('b');

    final notes = await repo.listNotes();
    expect(notes, hasLength(1));
    expect(notes.single.text, 'keep me');

    // The tombstone must survive in the exported log so the deletion syncs.
    final log = repo.exportLog();
    expect(log['b']!.deleted, isTrue);
  });

  test('priority sort orders highest first', () async {
    final repo = await NoteRepository.openInMemory();
    addTearDown(repo.close);

    await repo.upsert(note('a', 'low', priority: Priority.low));
    await repo.upsert(note('b', 'high', priority: Priority.high));

    final notes = await repo.listNotes(sort: NoteSort.priorityDesc);
    expect(notes.first.text, 'high');
    expect(notes.last.text, 'low');
  });

  test('priority sort breaks ties by most-recently-updated', () async {
    final repo = await NoteRepository.openInMemory();
    addTearDown(repo.close);

    await repo.upsert(
      note('a', 'older', priority: Priority.high, updatedAt: DateTime(2026)),
    );
    await repo.upsert(
      note('b', 'newer', priority: Priority.high, updatedAt: DateTime(2026, 6)),
    );

    final notes = await repo.listNotes(sort: NoteSort.priorityDesc);
    expect(notes.map((n) => n.text), ['newer', 'older']);
  });

  group('text search', () {
    test('matches a case-insensitive substring', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      await repo.upsert(note('a', 'Buy MILK and eggs'));
      await repo.upsert(note('b', 'call the dentist'));

      final notes = await repo.listNotes(
        filter: const NoteFilter(query: 'milk'),
      );
      expect(notes.map((n) => n.id), ['a']);
    });

    test('escapes LIKE wildcards so % is matched literally', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      await repo.upsert(note('pct', 'a%b'));
      await repo.upsert(note('plain', 'axb'));

      // Without escaping, 'a%b' as a LIKE pattern would also match 'axb'.
      final notes = await repo.listNotes(
        filter: const NoteFilter(query: 'a%b'),
      );
      expect(notes.map((n) => n.id), ['pct']);
    });
  });

  group('attribute filters', () {
    test('priority filter includes only the selected priorities', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      await repo.upsert(note('lo', 'l', priority: Priority.low));
      await repo.upsert(note('me', 'm', priority: Priority.medium));
      await repo.upsert(note('hi', 'h', priority: Priority.high));

      final notes = await repo.listNotes(
        filter: const NoteFilter(priorities: {Priority.low, Priority.high}),
      );
      expect(notes.map((n) => n.id).toSet(), {'lo', 'hi'});
    });

    test('status filter includes only the selected statuses', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      await repo.upsert(note('t', 'todo', status: Status.todo));
      await repo.upsert(note('d', 'done', status: Status.done));
      await repo.upsert(note('x', 'gone', status: Status.abandoned));

      final notes = await repo.listNotes(
        filter: const NoteFilter(statuses: {Status.todo, Status.inProgress}),
      );
      expect(notes.map((n) => n.id), ['t']);
    });
  });

  group('date range filters', () {
    final jan = DateTime(2026, 1, 15, 10);
    final jun = DateTime(2026, 6, 15, 10);

    test('created range bounds are inclusive by calendar day', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      await repo.upsert(note('j', 'jan', createdAt: jan, updatedAt: jan));
      await repo.upsert(note('u', 'jun', createdAt: jun, updatedAt: jun));

      // A single-day range on Jan 15 includes the 10:00 note that day.
      final notes = await repo.listNotes(
        filter: NoteFilter(
          createdFrom: DateTime(2026, 1, 15),
          createdTo: DateTime(2026, 1, 15),
        ),
      );
      expect(notes.map((n) => n.id), ['j']);
    });

    test('created and updated ranges apply independently', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      // Created in Jan, but last updated in Jun.
      await repo.upsert(
        note('e', 'edited later', createdAt: jan, updatedAt: jun),
      );

      // Matches on the updated range...
      final byUpdated = await repo.listNotes(
        filter: NoteFilter(
          updatedFrom: DateTime(2026, 6, 1),
          updatedTo: DateTime(2026, 6, 30),
        ),
      );
      expect(byUpdated.map((n) => n.id), ['e']);

      // ...but not when the created range excludes January.
      final byCreated = await repo.listNotes(
        filter: NoteFilter(
          createdFrom: DateTime(2026, 6, 1),
          createdTo: DateTime(2026, 6, 30),
        ),
      );
      expect(byCreated, isEmpty);
    });
  });

  test('filters combine with AND', () async {
    final repo = await NoteRepository.openInMemory();
    addTearDown(repo.close);
    await repo.upsert(
      note(
        'match',
        'urgent report',
        priority: Priority.high,
        status: Status.inProgress,
      ),
    );
    await repo.upsert(
      note(
        'wrongPrio',
        'urgent report',
        priority: Priority.low,
        status: Status.inProgress,
      ),
    );
    await repo.upsert(
      note(
        'wrongText',
        'casual note',
        priority: Priority.high,
        status: Status.inProgress,
      ),
    );

    final notes = await repo.listNotes(
      filter: const NoteFilter(
        query: 'urgent',
        priorities: {Priority.high},
        statuses: {Status.inProgress},
      ),
    );
    expect(notes.map((n) => n.id), ['match']);
  });

  group('priority defaults', () {
    test('fromValue maps legacy/unknown values to medium', () {
      expect(Priority.fromValue(0), Priority.medium); // old "none"
      expect(Priority.fromValue(null), Priority.medium);
      expect(Priority.fromValue(99), Priority.medium);
      // Known values still round-trip.
      expect(Priority.fromValue(1), Priority.low);
      expect(Priority.fromValue(2), Priority.medium);
      expect(Priority.fromValue(3), Priority.high);
    });
  });

  group('importNotes (safe merge)', () {
    test('adds notes whose id is not present locally', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      await repo.upsert(note('a', 'local'));

      final outcome = await repo.importNotes([note('b', 'incoming')]);

      expect(outcome.added, 1);
      expect(outcome.updated, 0);
      expect(outcome.skipped, 0);
      expect((await repo.listNotes()).map((n) => n.id).toSet(), {'a', 'b'});
    });

    test('overwrites a local note only when the import is newer', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      final old = DateTime(2026, 1, 1);
      final newer = DateTime(2026, 6, 1);
      await repo.upsert(note('a', 'local-old', updatedAt: old));

      final outcome = await repo.importNotes([
        note('a', 'imported-new', updatedAt: newer),
      ]);

      expect(outcome.updated, 1);
      final stored = (await repo.listNotes()).single;
      expect(stored.text, 'imported-new');
    });

    test('never clobbers a newer local edit with a stale import', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      final stale = DateTime(2026, 1, 1);
      final fresh = DateTime(2026, 6, 1);
      // Local note is the freshly-edited one.
      await repo.upsert(note('a', 'local-fresh', updatedAt: fresh));

      final outcome = await repo.importNotes([
        note('a', 'backup-stale', updatedAt: stale),
      ]);

      expect(outcome.skipped, 1);
      expect(outcome.updated, 0);
      // The newer local edit survives — "never lose ideas".
      expect((await repo.listNotes()).single.text, 'local-fresh');
    });
  });

  test('v2→v3 migration backfills priority 0 to medium', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('todo_migration');
    final path = '${dir.path}/notes.db';
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
    final repo = await NoteRepository.open(path);
    addTearDown(repo.close);
    final notes = await repo.listNotes();

    expect(notes.single.id, 'legacy');
    expect(notes.single.priority, Priority.medium);
  });

  test('v1→v2 migration adds the status column with a default', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('todo_migration_v1');
    final path = '${dir.path}/notes.db';
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
    final repo = await NoteRepository.open(path);
    addTearDown(repo.close);
    final notes = await repo.listNotes();
    expect(notes.single.id, 'old');
    expect(notes.single.status, Status.todo); // backfilled default
  });

  group('sorting and streams', () {
    test('createdDesc and alphabetical orderings', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      final t1 = DateTime(2026, 1, 1);
      final t2 = DateTime(2026, 2, 1);
      await repo.upsert(note('a', 'banana', createdAt: t1, updatedAt: t1));
      await repo.upsert(note('b', 'apple', createdAt: t2, updatedAt: t2));

      final byCreated = await repo.listNotes(sort: NoteSort.createdDesc);
      expect(byCreated.first.id, 'b'); // newest created first

      final alpha = await repo.listNotes(sort: NoteSort.alphabetical);
      expect(alpha.map((n) => n.text), ['apple', 'banana']);
    });

    test('watchNotes and watchCount emit current state', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      await repo.upsert(note('a', 'one'));

      expect(await repo.watchNotes().first, hasLength(1));
      expect(await repo.watchCount().first, 1);
    });
  });

  test('nodeId, log export/import merge and close', () async {
    // Each openInMemory repo owns its own in-memory log, so two of them model
    // two independent devices directly.
    final source = await NoteRepository.openInMemory(nodeId: 'source');
    final target = await NoteRepository.openInMemory(nodeId: 'target');
    addTearDown(target.close);

    expect(source.nodeId, 'source');
    await source.upsert(note('a', 'shared idea'));
    final log = source.exportLog();
    await source.close();

    await target.importLog(log);
    final merged = await target.listNotes();
    expect(merged.single.text, 'shared idea');
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

      final repo = await NoteRepository.open(path);
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
      await repo.upsert(note('new', 'added post-migration'));
      await repo.close();
      final reopened = await NoteRepository.open(path);
      addTearDown(reopened.close);
      final texts = (await reopened.listNotes()).map((n) => n.text).toSet();
      expect(texts, {'kept idea', 'added post-migration'});
    });

    test('a fresh install with no legacy DB starts empty', () async {
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('todo_fresh');
      addTearDown(() => dir.delete(recursive: true));

      final repo = await NoteRepository.open('${dir.path}/todo.db');
      addTearDown(repo.close);

      expect(await repo.listNotes(), isEmpty);
      expect(repo.nodeId, isNotEmpty);
    });
  });

  test('watchNotes emits the seed then re-emits after each change', () async {
    final repo = await NoteRepository.openInMemory();
    addTearDown(repo.close);
    final lengths = <int>[];
    final sub = repo.watchNotes().listen((notes) => lengths.add(notes.length));

    await repo.upsert(note('a', 'first'));
    await repo.upsert(note('b', 'second'));
    await pumpEventQueue();
    await sub.cancel();

    expect(lengths.first, 0); // seed
    expect(lengths.last, 2); // after both writes
  });

  test('watchCount emits the seed then re-emits after a change', () async {
    final repo = await NoteRepository.openInMemory();
    addTearDown(repo.close);
    final counts = <int>[];
    final sub = repo.watchCount().listen(counts.add);

    await repo.upsert(note('a', 'x'));
    await pumpEventQueue();
    await sub.cancel();

    expect(counts.first, 0);
    expect(counts.last, 1);
  });

  test('a foreign record missing timestamps falls back to the epoch', () async {
    // A note this app writes always has both timestamps; this guards a
    // malformed record arriving from another device via importLog.
    final repo = await NoteRepository.openInMemory();
    addTearDown(repo.close);
    await repo.importLog({
      'partial': Record(
        id: 'partial',
        fields: {'text': ('no dates', Hlc.newTick('other'))},
      ),
    });

    final only = (await repo.listNotes()).single;
    expect(only.text, 'no dates');
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    expect(only.createdAt, epoch);
    expect(only.updatedAt, epoch);
  });

  test('date-range filters bound by whole calendar days', () async {
    final repo = await NoteRepository.openInMemory();
    addTearDown(repo.close);
    await repo.upsert(
      note(
        'jan',
        'january idea',
        createdAt: DateTime(2026, 1, 10),
        updatedAt: DateTime(2026, 1, 10),
      ),
    );
    await repo.upsert(
      note(
        'mar',
        'march idea',
        createdAt: DateTime(2026, 3, 10),
        updatedAt: DateTime(2026, 3, 10),
      ),
    );

    final byCreated = await repo.listNotes(
      filter: NoteFilter(
        createdFrom: DateTime(2026, 2, 1),
        createdTo: DateTime(2026, 4, 1),
      ),
    );
    expect(byCreated.map((n) => n.text), ['march idea']);

    final byUpdated = await repo.listNotes(
      filter: NoteFilter(
        updatedFrom: DateTime(2026, 1, 1),
        updatedTo: DateTime(2026, 1, 31),
      ),
    );
    expect(byUpdated.map((n) => n.text), ['january idea']);
  });

  group('NoteFilter', () {
    test('a default filter is empty (all facets cleared)', () {
      // Evaluates the full conjunction in `isEmpty`, including the date bounds.
      const filter = NoteFilter();
      expect(filter.isEmpty, isTrue);
      expect(filter.activeCount, 0);
    });

    test('a filter with any facet set is not empty', () {
      expect(const NoteFilter(query: 'x').isEmpty, isFalse);
      expect(const NoteFilter(statuses: {Status.done}).isEmpty, isFalse);
    });

    test('copyWith with no arguments preserves every facet', () {
      final base = NoteFilter(
        query: 'milk',
        priorities: const {Priority.high},
        statuses: const {Status.todo},
        createdFrom: DateTime(2026, 1, 1),
        updatedTo: DateTime(2026, 2, 2),
      );
      final clone = base.copyWith();
      expect(clone.query, base.query);
      expect(clone.priorities, base.priorities);
      expect(clone.statuses, base.statuses);
      expect(clone.createdFrom, base.createdFrom);
      expect(clone.updatedTo, base.updatedTo);
    });
  });

  group('changes', () {
    test('ticks once per write across upsert, delete, and merge', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      var ticks = 0;
      final sub = repo.changes.listen((_) => ticks++);
      addTearDown(sub.cancel);

      await repo.upsert(note('a', 'x'));
      await repo.delete('a');

      // A log from another device, merged in, must also tick.
      final other = await NoteRepository.openInMemory(nodeId: 'other');
      addTearDown(other.close);
      await other.upsert(note('b', 'from other'));
      await repo.importLog(other.exportLog());

      await pumpEventQueue(); // let the broadcast events dispatch
      expect(ticks, 3);
    });

    test('importNotes ticks once per note it writes', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      var ticks = 0;
      final sub = repo.changes.listen((_) => ticks++);
      addTearDown(sub.cancel);

      await repo.importNotes([note('a', 'x'), note('b', 'y')]);

      await pumpEventQueue();
      expect(ticks, 2); // two new notes → two upserts → two ticks
    });
  });
}
