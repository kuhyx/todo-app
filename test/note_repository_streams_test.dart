/// Import merging, watch streams, and the changes tick.
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

  group('importNotes (safe merge)', () {
    test('restores at the note\'s own edit time, not "now"', () async {
      // Regression guard. Recovery used to stamp fresh clocks on every
      // restored note, so a device that recovered from a backup outranked
      // every other device under per-field last-writer-wins and silently
      // overwrote newer edits made elsewhere. Observed for real: a restored
      // desktop rewrote 245 of 330 field clocks to "now".
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      final edited = DateTime(2026, 3, 4, 5, 6, 7);

      await repo.importNotes([
        noteFixture(
          'restored',
          'from a backup',
          createdAt: edited,
          updatedAt: edited,
        ),
      ]);

      final field = repo.exportLog()['restored']!.fields['text']!;
      expect(
        field.$2.wallTimeMs,
        edited.millisecondsSinceEpoch,
        reason:
            'clock must come from updatedAt so a restore cannot outrank '
            'genuinely newer data on another device',
      );
    });

    test('adds notes whose id is not present locally', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      await repo.upsert(noteFixture('a', 'local'));

      final outcome = await repo.importNotes([noteFixture('b', 'incoming')]);

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
      await repo.upsert(noteFixture('a', 'local-old', updatedAt: old));

      final outcome = await repo.importNotes([
        noteFixture('a', 'imported-new', updatedAt: newer),
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
      await repo.upsert(noteFixture('a', 'local-fresh', updatedAt: fresh));

      final outcome = await repo.importNotes([
        noteFixture('a', 'backup-stale', updatedAt: stale),
      ]);

      expect(outcome.skipped, 1);
      expect(outcome.updated, 0);
      // The newer local edit survives — "never lose ideas".
      expect((await repo.listNotes()).single.text, 'local-fresh');
    });
  });

  group('sorting and streams', () {
    test('createdDesc and alphabetical orderings', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      final t1 = DateTime(2026, 1, 1);
      final t2 = DateTime(2026, 2, 1);
      await repo.upsert(
        noteFixture('a', 'banana', createdAt: t1, updatedAt: t1),
      );
      await repo.upsert(
        noteFixture('b', 'apple', createdAt: t2, updatedAt: t2),
      );

      final byCreated = await repo.listNotes(sort: NoteSort.createdDesc);
      expect(byCreated.first.id, 'b'); // newest created first

      final alpha = await repo.listNotes(sort: NoteSort.alphabetical);
      expect(alpha.map((n) => n.text), ['apple', 'banana']);
    });

    test('watchNotes and watchCount emit current state', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      await repo.upsert(noteFixture('a', 'one'));

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
    await source.upsert(noteFixture('a', 'shared idea'));
    final log = source.exportLog();
    await source.close();

    await target.importLog(log);
    final merged = await target.listNotes();
    expect(merged.single.text, 'shared idea');
  });

  test('watchNotes emits the seed then re-emits after each change', () async {
    final repo = await NoteRepository.openInMemory();
    addTearDown(repo.close);
    final lengths = <int>[];
    final sub = repo.watchNotes().listen((notes) => lengths.add(notes.length));

    await repo.upsert(noteFixture('a', 'first'));
    await repo.upsert(noteFixture('b', 'second'));
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

    await repo.upsert(noteFixture('a', 'x'));
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

  group('changes', () {
    test('ticks once per write across upsert, delete, and merge', () async {
      final repo = await NoteRepository.openInMemory();
      addTearDown(repo.close);
      var ticks = 0;
      final sub = repo.changes.listen((_) => ticks++);
      addTearDown(sub.cancel);

      await repo.upsert(noteFixture('a', 'x'));
      await repo.delete('a');

      // A log from another device, merged in, must also tick.
      final other = await NoteRepository.openInMemory(nodeId: 'other');
      addTearDown(other.close);
      await other.upsert(noteFixture('b', 'from other'));
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

      await repo.importNotes([noteFixture('a', 'x'), noteFixture('b', 'y')]);

      await pumpEventQueue();
      expect(ticks, 2); // two new notes → two upserts → two ticks
    });
  });
}
