// Wire compatibility between the v4 note mapping (repo task fields) and
// devices still running the v3 build, which knows only the five original
// fields. Both builds share crdt_sync 0.11.1, so the v3 side is modelled by
// its own note<->record mapping, copied verbatim below.
import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';

/// The exact field set the v3 build writes for every note.
const _v3Keys = {'text', 'priority', 'status', 'created_at', 'updated_at'};

/// The v3 build's `_fieldsFor`, verbatim.
Map<String, Field> _v3FieldsFor(Note note, Hlc hlc) => {
  'text': (note.text, hlc),
  'priority': (note.priority.value, hlc),
  'status': (note.status.value, hlc),
  'created_at': (note.createdAt.toIso8601String(), hlc),
  'updated_at': (note.updatedAt.toIso8601String(), hlc),
};

/// The v3 build's `_toNote`, verbatim: unknown fields are never looked at.
Note _v3Read(Record record) => Note(
  id: record.id,
  text: record.fields['text']?.$1 as String? ?? '',
  priority: Priority.fromValue(record.fields['priority']?.$1 as int?),
  status: Status.fromValue(record.fields['status']?.$1 as int?),
  createdAt: DateTime.parse(record.fields['created_at']!.$1! as String),
  updatedAt: DateTime.parse(record.fields['updated_at']!.$1! as String),
);

Note _task({String text = 'Fix the gate'}) {
  final at = DateTime.utc(2026, 11);
  return Note(
    id: 'task-1',
    text: text,
    priority: Priority.high,
    status: Status.todo,
    createdAt: at,
    updatedAt: at,
    repo: 'kuhyx/todo',
    doneCheck: 'flutter test "test/a b.dart"',
    by: 'claude',
    evidence: 'abc123 exit 0',
  );
}

/// What a peer receives: the log as it travels through RTDB (JSON text).
Log _overTheWire(Log log) => logFromJson(logToJson(log));

void main() {
  test(
    'v3 peer merges and reads a v4 repo-task record without error',
    () async {
      final v4 = await NoteRepository.openInMemory(nodeId: 'v4');
      await v4.upsert(_task());

      final v3 = LogStore(persistence: MemoryPersistence(), nodeId: 'v3');
      await v3.load();
      await v3.replaceAll(
        mergeLogs(v3.snapshot(), _overTheWire(v4.exportLog())),
      );

      final seen = _v3Read(v3.snapshot()['task-1']!);
      expect(seen.text, 'Fix the gate');
      expect(seen.priority, Priority.high);
      // The v3 log still carries the fields it does not understand.
      expect(v3.snapshot()['task-1']!.fields['repo']!.$1, 'kuhyx/todo');
    },
  );

  test('a v3 edit drops the new fields locally; the next merge restores '
      'them and keeps the v3 edit', () async {
    final v4 = await NoteRepository.openInMemory(nodeId: 'v4');
    await v4.upsert(_task());

    final v3 = LogStore(persistence: MemoryPersistence(), nodeId: 'v3');
    await v3.load();
    await v3.replaceAll(mergeLogs(v3.snapshot(), _overTheWire(v4.exportLog())));
    final edited = _v3Read(v3.snapshot()['task-1']!).copyWith(
      text: 'Fix the gate (edited on v3)',
      updatedAt: DateTime.utc(2026, 11, 2),
    );
    // LogStore.upsert replaces the whole record with the v3 field set.
    await v3.upsert(
      Record(id: edited.id, fields: _v3FieldsFor(edited, v3.nextHlc())),
    );
    expect(v3.snapshot()['task-1']!.fields.keys.toSet(), _v3Keys);

    await v4.importLog(_overTheWire(v3.snapshot()));
    final merged = (await v4.listNotes()).single;
    expect(merged.text, 'Fix the gate (edited on v3)');
    expect(merged.repo, 'kuhyx/todo');
    expect(merged.doneCheck, 'flutter test "test/a b.dart"');
    expect(merged.by, 'claude');
    expect(merged.evidence, 'abc123 exit 0');

    // And the v3 device gets them back on its next pull.
    await v3.replaceAll(mergeLogs(v3.snapshot(), _overTheWire(v4.exportLog())));
    expect(v3.snapshot()['task-1']!.fields['repo']!.$1, 'kuhyx/todo');
  });

  test('v4 reads a v3 record (no new fields) as a plain idea', () async {
    final at = DateTime.utc(2026);
    final idea = Note(
      id: 'idea-1',
      text: 'Idea',
      priority: Priority.low,
      status: Status.todo,
      createdAt: at,
      updatedAt: at,
    );
    final hlc = Hlc(wallTimeMs: 1, counter: 0, nodeId: 'v3');
    final v4 = await NoteRepository.openInMemory(nodeId: 'v4');
    await v4.importLog({
      'idea-1': Record(id: 'idea-1', fields: _v3FieldsFor(idea, hlc)),
    });

    final read = (await v4.listNotes()).single;
    expect(read.text, 'Idea');
    expect(read.repo, isNull);
    expect(read.doneCheck, isNull);
    expect(read.by, isNull);
    expect(read.evidence, isNull);
  });

  test('v4 editing a plain idea writes exactly the v3 field set', () async {
    final v4 = await NoteRepository.openInMemory(nodeId: 'v4');
    final at = DateTime.utc(2026);
    final idea = Note(
      id: 'idea-1',
      text: 'Idea',
      priority: Priority.medium,
      status: Status.todo,
      createdAt: at,
      updatedAt: at,
    );
    await v4.upsert(idea);
    await v4.upsert(idea.copyWith(text: 'Idea, edited', status: Status.done));
    await v4.importNotes([idea.copyWith(updatedAt: DateTime.utc(2027))]);

    final record = _overTheWire(v4.exportLog())['idea-1']!;
    expect(record.fields.keys.toSet(), _v3Keys);
    expect(_v3Read(record).text, 'Idea');
  });

  test('a restored repo task keeps its fields at the note\'s own clock', () {
    final record = NoteRepository.recordAtNoteTime(_task(), 'n');
    expect(record.fields.keys.toSet(), {
      ..._v3Keys,
      'repo',
      'done_check',
      'by',
      'evidence',
    });
    expect(
      record.fields['repo']!.$2.wallTimeMs,
      DateTime.utc(2026, 11).millisecondsSinceEpoch,
    );
  });
}
