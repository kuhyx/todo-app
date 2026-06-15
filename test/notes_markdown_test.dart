import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/sync/notes_markdown.dart';

void main() {
  Note note(
    String id,
    String text, {
    Priority priority = Priority.medium,
    Status status = Status.todo,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final t = DateTime(2026, 6, 15, 9, 30, 15, 123);
    return Note(
      id: id,
      text: text,
      priority: priority,
      status: status,
      createdAt: createdAt ?? t,
      updatedAt: updatedAt ?? t,
    );
  }

  test('export then parse round-trips every field', () {
    final original = [
      note('a', 'first idea', priority: Priority.high, status: Status.done),
      note(
        'b',
        'multi-line\nbody with - dashes\nand 1. a list',
        priority: Priority.low,
        status: Status.inProgress,
      ),
    ];

    final parsed = NotesMarkdown.parse(NotesMarkdown.export(original));

    expect(parsed, hasLength(2));
    for (var i = 0; i < original.length; i++) {
      expect(parsed[i].id, original[i].id);
      expect(parsed[i].text, original[i].text);
      expect(parsed[i].priority, original[i].priority);
      expect(parsed[i].status, original[i].status);
      expect(parsed[i].createdAt, original[i].createdAt);
      expect(parsed[i].updatedAt, original[i].updatedAt);
    }
  });

  test('export of an empty list yields just the header', () {
    final out = NotesMarkdown.export([]);
    expect(out.trim(), NotesMarkdown.header);
    expect(NotesMarkdown.parse(out), isEmpty);
  });

  test('parse tolerates missing/unknown fields with defaults', () {
    const content = '''
<!-- todo-backlog v1 -->

<!-- @note priority="bogus" status="" -->
a hand-written note with no id
''';
    final parsed = NotesMarkdown.parse(content);

    expect(parsed, hasLength(1));
    expect(parsed.single.text, 'a hand-written note with no id');
    // Missing id => a fresh UUID is generated (non-empty).
    expect(parsed.single.id, isNotEmpty);
    // Unknown/blank enum names fall back to the defaults.
    expect(parsed.single.priority, Priority.medium);
    expect(parsed.single.status, Status.todo);
  });

  test('parse ignores text before the first note marker', () {
    const content = '''
<!-- todo-backlog v1 -->
Some preamble a user typed that is not a note.

<!-- @note id="x" priority="medium" status="todo" -->
real note
''';
    final parsed = NotesMarkdown.parse(content);
    expect(parsed.map((n) => n.text), ['real note']);
  });
}
