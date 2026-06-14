import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  Note note(String id, String text, {Priority priority = Priority.none}) {
    final now = DateTime.now();
    return Note(
      id: id,
      text: text,
      priority: priority,
      createdAt: now,
      updatedAt: now,
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

    // The tombstone must survive in the changeset so the deletion syncs.
    final changeset = await repo.getChangeset();
    final rows = changeset['notes']!;
    final deleted = rows.firstWhere((r) => r['id'] == 'b');
    expect(deleted['is_deleted'], 1);
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
}
