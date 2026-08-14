/// Core CRUD, tombstones, sorting, and priority defaults.
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

  test('upsert then list returns the note', () async {
    final repo = await NoteRepository.openInMemory();
    addTearDown(repo.close);

    await repo.upsert(noteFixture('a', 'first idea'));
    final notes = await repo.listNotes();

    expect(notes, hasLength(1));
    expect(notes.single.text, 'first idea');
  });

  test('deleted notes are excluded from reads (tombstone filter)', () async {
    final repo = await NoteRepository.openInMemory();
    addTearDown(repo.close);

    await repo.upsert(noteFixture('a', 'keep me'));
    await repo.upsert(noteFixture('b', 'delete me'));
    await repo.delete('b');

    final notes = await repo.listNotes();
    expect(notes, hasLength(1));
    expect(notes.single.text, 'keep me');

    // The tombstone must survive in the exported log so the deletion syncs.
    final log = repo.exportLog();
    expect(log['b']!.deleted, isTrue);
  });

  test('modifiedDesc sort orders most-recently-updated first', () async {
    final repo = await NoteRepository.openInMemory();
    addTearDown(repo.close);

    await repo.upsert(noteFixture('a', 'older', updatedAt: DateTime(2026)));
    await repo.upsert(noteFixture('b', 'newer', updatedAt: DateTime(2026, 6)));

    final notes = await repo.listNotes(sort: NoteSort.modifiedDesc);
    expect(notes.map((n) => n.text), ['newer', 'older']);
  });

  test('priority sort orders highest first', () async {
    final repo = await NoteRepository.openInMemory();
    addTearDown(repo.close);

    await repo.upsert(noteFixture('a', 'low', priority: Priority.low));
    await repo.upsert(noteFixture('b', 'high', priority: Priority.high));

    final notes = await repo.listNotes(sort: NoteSort.priorityDesc);
    expect(notes.first.text, 'high');
    expect(notes.last.text, 'low');
  });

  test('priority sort breaks ties by most-recently-updated', () async {
    final repo = await NoteRepository.openInMemory();
    addTearDown(repo.close);

    await repo.upsert(
      noteFixture(
        'a',
        'older',
        priority: Priority.high,
        updatedAt: DateTime(2026),
      ),
    );
    await repo.upsert(
      noteFixture(
        'b',
        'newer',
        priority: Priority.high,
        updatedAt: DateTime(2026, 6),
      ),
    );

    final notes = await repo.listNotes(sort: NoteSort.priorityDesc);
    expect(notes.map((n) => n.text), ['newer', 'older']);
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
}
