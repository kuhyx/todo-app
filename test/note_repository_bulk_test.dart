/// Bulk status/priority and save-replacing: one store write each.
library;

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';

import 'note_repository_helpers.dart';

/// Counts log writes, so "one write" is measured, not assumed.
class _CountingPersistence implements LogPersistence {
  final _inner = MemoryPersistence();
  int writes = 0;

  @override
  Future<String?> read() => _inner.read();

  @override
  Future<void> write(String text) {
    writes++;
    return _inner.write(text);
  }
}

Future<(NoteRepository, _CountingPersistence)> _open() async {
  final p = _CountingPersistence();
  final repo = await NoteRepository.openWith(persistence: p, nodeId: 'dev');
  addTearDown(repo.close);
  return (repo, p);
}

Hlc _clock(NoteRepository repo, String id, String field) =>
    repo.exportLog()[id]!.fields[field]!.$2;

void main() {
  test('sets status and priority on every id in ONE write', () async {
    final (repo, p) = await _open();
    for (final id in ['a', 'b', 'c']) {
      await repo.upsert(
        noteFixture(id, 'note $id').copyWith(createdBy: 'kuhy'),
      );
    }
    final textClock = _clock(repo, 'a', 'text');
    final createdClock = _clock(repo, 'a', 'created_at');
    p.writes = 0;

    await repo.bulkUpdate(
      {'a', 'b', 'c'},
      status: Status.inProgress,
      priority: Priority.high,
    );

    expect(p.writes, 1);
    final notes = {for (final n in await repo.listNotes()) n.id: n};
    for (final n in notes.values) {
      expect(n.status, Status.inProgress);
      expect(n.priority, Priority.high);
      expect(n.createdBy, 'kuhy');
    }
    expect(_clock(repo, 'a', 'text'), textClock);
    expect(_clock(repo, 'a', 'created_at'), createdClock);
    expect(_clock(repo, 'a', 'status') > textClock, isTrue);
    expect(_clock(repo, 'a', 'updated_at') > textClock, isTrue);
  });

  test('touches only fields whose value changes', () async {
    final (repo, _) = await _open();
    await repo.upsert(noteFixture('a', 'A', priority: Priority.high));
    final priorityClock = _clock(repo, 'a', 'priority');

    await repo.bulkUpdate({'a'}, priority: Priority.high, status: Status.done);

    expect(_clock(repo, 'a', 'priority'), priorityClock);
    expect((await repo.listNotes()).single.status, Status.done);
  });

  test(
    'a stored value Dart would format differently keeps its clock',
    () async {
      final (repo, _) = await _open();
      final peer = Hlc(wallTimeMs: 1000, counter: 0, nodeId: 'mcp');
      // A peer's (or a web build's) timestamp text, and no priority field.
      await repo.importLog({
        'a': Record(
          id: 'a',
          fields: {
            'text': ('A', peer),
            'status': (0, peer),
            'created_at': ('2026-01-01T00:00:00Z', peer),
            'updated_at': ('2026-01-01T00:00:00Z', peer),
          },
        ),
      });

      await repo.bulkUpdate({'a'}, status: Status.done);

      final fields = repo.exportLog()['a']!.fields;
      expect(fields['created_at'], ('2026-01-01T00:00:00Z', peer));
      expect(fields.containsKey('priority'), isFalse);
      expect(fields['status']!.$2.nodeId, 'dev');
    },
  );

  test('no write when nothing changes or ids are unknown/deleted', () async {
    final (repo, p) = await _open();
    await repo.upsert(noteFixture('a', 'A'));
    await repo.upsert(noteFixture('gone', 'G'));
    await repo.delete('gone');
    p.writes = 0;

    await repo.bulkUpdate({'a'}, priority: Priority.medium);
    await repo.bulkUpdate({'missing', 'gone'}, status: Status.done);
    await repo.bulkUpdate({'a'});

    expect(p.writes, 0);
    expect(repo.exportLog().containsKey('missing'), isFalse);
    expect(repo.exportLog()['gone']!.fields.containsKey('status'), isTrue);
  });

  test('saveReplacing saves one note and tombstones the rest', () async {
    final (repo, p) = await _open();
    await repo.upsert(noteFixture('a', 'A').copyWith(createdBy: 'kuhy'));
    await repo.upsert(noteFixture('b', 'B'));
    await repo.upsert(noteFixture('keep', 'K'));
    p.writes = 0;

    final saved = noteFixture('a', 'A2', status: Status.inProgress);
    await repo.saveReplacing(saved, ['b', 'missing']);

    expect(p.writes, 1);
    final notes = {for (final n in await repo.listNotes()) n.id: n};
    expect(notes.keys, unorderedEquals(['a', 'keep']));
    expect(notes['a']!.text, 'A2');
    expect(notes['a']!.createdBy, 'kuhy');
    expect(repo.exportLog()['b']!.deleted, isTrue);
    expect(repo.exportLog().containsKey('missing'), isFalse);
  });
}
