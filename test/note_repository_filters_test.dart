/// Search, attribute/date filters, and NoteFilter itself.
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

  group('text search', () {
    test('matches a case-insensitive substring', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      await repo.upsert(noteFixture('a', 'Buy MILK and eggs'));
      await repo.upsert(noteFixture('b', 'call the dentist'));

      final notes = await repo.listNotes(
        filter: const NoteFilter(query: 'milk'),
      );
      expect(notes.map((n) => n.id), ['a']);
    });

    test('escapes LIKE wildcards so % is matched literally', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      await repo.upsert(noteFixture('pct', 'a%b'));
      await repo.upsert(noteFixture('plain', 'axb'));

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
      await repo.upsert(noteFixture('lo', 'l', priority: Priority.low));
      await repo.upsert(noteFixture('me', 'm', priority: Priority.medium));
      await repo.upsert(noteFixture('hi', 'h', priority: Priority.high));

      final notes = await repo.listNotes(
        filter: const NoteFilter(priorities: {Priority.low, Priority.high}),
      );
      expect(notes.map((n) => n.id).toSet(), {'lo', 'hi'});
    });

    test('status filter includes only the selected statuses', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      await repo.upsert(noteFixture('t', 'todo', status: Status.todo));
      await repo.upsert(noteFixture('d', 'done', status: Status.done));
      await repo.upsert(noteFixture('x', 'gone', status: Status.abandoned));

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
      await repo.upsert(
        noteFixture('j', 'jan', createdAt: jan, updatedAt: jan),
      );
      await repo.upsert(
        noteFixture('u', 'jun', createdAt: jun, updatedAt: jun),
      );

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
        noteFixture('e', 'edited later', createdAt: jan, updatedAt: jun),
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
      noteFixture(
        'match',
        'urgent report',
        priority: Priority.high,
        status: Status.inProgress,
      ),
    );
    await repo.upsert(
      noteFixture(
        'wrongPrio',
        'urgent report',
        priority: Priority.low,
        status: Status.inProgress,
      ),
    );
    await repo.upsert(
      noteFixture(
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

  test('date-range filters bound by whole calendar days', () async {
    final repo = await NoteRepository.openInMemory();
    addTearDown(repo.close);
    await repo.upsert(
      noteFixture(
        'jan',
        'january idea',
        createdAt: DateTime(2026, 1, 10),
        updatedAt: DateTime(2026, 1, 10),
      ),
    );
    await repo.upsert(
      noteFixture(
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
}
