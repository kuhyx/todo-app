// created_by: record mapping, merge safety against older builds, list order,
// the hide filter and backfill classification.
import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/created_by_backfill.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';

Note _note(
  String id, {
  String? createdBy,
  Priority priority = Priority.medium,
  DateTime? updated,
}) {
  final at = updated ?? DateTime.utc(2026, 11);
  return Note(
    id: id,
    text: 'note $id',
    priority: priority,
    status: Status.todo,
    createdAt: at,
    updatedAt: at,
    createdBy: createdBy,
  );
}

/// What an older build writes: no created_by, replacing the record locally.
Map<String, Field> _oldFields(Note n, Hlc hlc) => {
  'text': (n.text, hlc),
  'priority': (n.priority.value, hlc),
  'status': (n.status.value, hlc),
  'created_at': (n.createdAt.toIso8601String(), hlc),
  'updated_at': (n.updatedAt.toIso8601String(), hlc),
};

Log _overTheWire(Log log) => logFromJson(logToJson(log));

void main() {
  group('record mapping', () {
    test('created_by is written only when set and read back', () {
      final hlc = Hlc(wallTimeMs: 1, counter: 0, nodeId: 'n');
      expect(
        noteFields(_note('a'), hlc).containsKey('created_by'),
        isFalse,
        reason: 'an unset field keeps the record wire-identical',
      );
      final fields = noteFields(_note('a', createdBy: 'claude'), hlc);
      expect(fields['created_by']!.$1, 'claude');
      final back = noteFromRecord(Record(id: 'a', fields: fields));
      expect(back.createdBy, 'claude');
      expect(back.isClaudeMade, isTrue);
      expect(_note('b', createdBy: 'kuhy').isClaudeMade, isFalse);
      expect(_note('c').isClaudeMade, isFalse);
    });

    test('copyWith keeps createdBy unless replaced', () {
      final n = _note('a', createdBy: 'claude');
      expect(n.copyWith(text: 'x').createdBy, 'claude');
      expect(n.copyWith(createdBy: 'kuhy').createdBy, 'kuhy');
    });
  });

  group('merge safety', () {
    test(
      'an older build upsert (no created_by) does not wipe a peer value',
      () async {
        final current = await NoteRepository.openInMemory(nodeId: 'new');
        await current.upsert(_note('a', createdBy: 'claude'));

        final old = LogStore(persistence: MemoryPersistence(), nodeId: 'old');
        await old.load();
        await old.replaceAll(
          mergeLogs(old.snapshot(), _overTheWire(current.exportLog())),
        );
        final edited = _note('a', updated: DateTime.utc(2026, 11, 2));
        await old.upsert(
          Record(id: 'a', fields: _oldFields(edited, old.nextHlc())),
        );
        expect(old.snapshot()['a']!.fields.containsKey('created_by'), isFalse);

        await current.importLog(_overTheWire(old.snapshot()));
        expect((await current.listNotes()).single.createdBy, 'claude');

        // Pulling the other way restores it on the older device too.
        await old.replaceAll(
          mergeLogs(old.snapshot(), _overTheWire(current.exportLog())),
        );
        expect(old.snapshot()['a']!.fields['created_by']!.$1, 'claude');
      },
    );

    test('upserting a note without createdBy keeps the stored value', () async {
      final repo = await NoteRepository.openInMemory();
      await repo.upsert(_note('a', createdBy: 'claude'));
      await repo.upsert(_note('a', updated: DateTime.utc(2026, 11, 3)));
      expect((await repo.listNotes()).single.createdBy, 'claude');
      await repo.importNotes([_note('a', updated: DateTime.utc(2027))]);
      expect((await repo.listNotes()).single.createdBy, 'claude');
    });
  });

  group('order and hiding', () {
    final claudeHigh = _note('c', createdBy: 'claude', priority: Priority.high);
    final humanLow = _note('h', createdBy: 'kuhy', priority: Priority.low);
    final legacy = _note('l', priority: Priority.medium);

    test(
      'human notes come first under every sort, then the old order',
      () async {
        final repo = await NoteRepository.openInMemory();
        for (final n in [claudeHigh, humanLow, legacy]) {
          await repo.upsert(n);
        }
        for (final sort in NoteSort.values) {
          final ids = [for (final n in await repo.listNotes(sort: sort)) n.id];
          expect(ids.last, 'c', reason: '$sort');
        }
        final byPriority = await repo.listNotes();
        expect([for (final n in byPriority) n.id], ['l', 'h', 'c']);
      },
    );

    test('hideClaude drops Claude-made notes and is not a user facet', () {
      const filter = NoteFilter(hideClaude: true);
      expect(matchesFilter(claudeHigh, filter), isFalse);
      expect(matchesFilter(humanLow, filter), isTrue);
      expect(matchesFilter(legacy, filter), isTrue);
      expect(matchesFilter(claudeHigh, const NoteFilter()), isTrue);
      expect(filter.isEmpty, isTrue);
      expect(filter.activeCount, 0);
      expect(filter.copyWith(query: 'x').hideClaude, isTrue);
      expect(filter.copyWith(hideClaude: false).hideClaude, isFalse);
    });
  });

  group('backfill', () {
    Record rec(String id, String node, {String? createdBy, bool dead = false}) {
      final hlc = Hlc(wallTimeMs: 5, counter: 0, nodeId: node);
      return Record(
        id: id,
        fields: {...noteFields(_note(id, createdBy: createdBy), hlc)},
        deleted: dead,
        deletedHlc: dead ? hlc : null,
      );
    }

    test('classifies by the node that wrote created_at', () {
      const claude = {'mcp', 'cli'};
      expect(classifyCreatedBy(rec('a', 'mcp'), claude), 'claude');
      expect(classifyCreatedBy(rec('a', 'cli'), claude), 'claude');
      expect(classifyCreatedBy(rec('a', 'phone'), claude), 'kuhy');
      const bare = Record(id: 'x', fields: {});
      expect(classifyCreatedBy(bare, claude), 'kuhy');
    });

    test('writes only unset, live records, and only that field', () async {
      final repo = await NoteRepository.openInMemory(nodeId: 'cli');
      await repo.importLog({
        'a': rec('a', 'mcp'),
        'b': rec('b', 'phone'),
        'c': rec('c', 'phone', createdBy: 'claude'),
        'd': rec('d', 'mcp', dead: true),
      });
      const claude = {'mcp', 'cli'};
      final dry = await repo.backfillCreatedBy(claude, dryRun: true);
      expect(dry, {'a': 'claude', 'b': 'kuhy'});
      expect(repo.exportLog()['a']!.fields.containsKey('created_by'), isFalse);

      final done = await repo.backfillCreatedBy(claude);
      expect(done, dry);
      final log = repo.exportLog();
      expect(log['a']!.fields['created_by']!.$1, 'claude');
      expect(log['b']!.fields['created_by']!.$1, 'kuhy');
      expect(log['c']!.fields['created_by']!.$1, 'claude');
      expect(log['d']!.fields.containsKey('created_by'), isFalse);
      // created_at keeps its original clock: the signal is not destroyed.
      expect(log['b']!.fields['created_at']!.$2.nodeId, 'phone');
      expect(await repo.backfillCreatedBy(claude), isEmpty);
    });
  });
}
