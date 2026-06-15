import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';

void main() {
  group('Priority', () {
    test('fromValue maps known, legacy and unknown values', () {
      expect(Priority.fromValue(1), Priority.low);
      expect(Priority.fromValue(2), Priority.medium);
      expect(Priority.fromValue(3), Priority.high);
      expect(Priority.fromValue(0), Priority.medium); // legacy "none"
      expect(Priority.fromValue(null), Priority.medium);
      expect(Priority.fromValue(99), Priority.medium);
    });

    test('labels and default', () {
      expect(Priority.high.label, 'High');
      expect(Priority.defaultValue, Priority.medium);
    });
  });

  group('Status', () {
    test('fromValue maps known and unknown values', () {
      expect(Status.fromValue(0), Status.todo);
      expect(Status.fromValue(1), Status.inProgress);
      expect(Status.fromValue(2), Status.done);
      expect(Status.fromValue(3), Status.abandoned);
      expect(Status.fromValue(null), Status.todo);
      expect(Status.fromValue(42), Status.todo);
    });

    test('labels', () {
      expect(Status.inProgress.label, 'In progress');
      expect(Status.abandoned.label, 'Abandoned');
    });
  });

  test('fromRow builds a Note from a raw column map', () {
    final note = Note.fromRow({
      'id': 'x',
      'text': 'hello',
      'priority': 3,
      'status': 1,
      'created_at': '2026-06-15T09:00:00.000',
      'updated_at': '2026-06-15T10:00:00.000',
    });
    expect(note.id, 'x');
    expect(note.text, 'hello');
    expect(note.priority, Priority.high);
    expect(note.status, Status.inProgress);
    expect(note.createdAt, DateTime(2026, 6, 15, 9));
    expect(note.updatedAt, DateTime(2026, 6, 15, 10));
  });

  test('fromRow tolerates a null text column', () {
    final note = Note.fromRow({
      'id': 'x',
      'text': null,
      'priority': 2,
      'status': 0,
      'created_at': '2026-06-15T09:00:00.000',
      'updated_at': '2026-06-15T09:00:00.000',
    });
    expect(note.text, '');
  });

  test('copyWith replaces selected fields and keeps identity', () {
    final base = Note(
      id: 'id',
      text: 'a',
      priority: Priority.low,
      status: Status.todo,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
    final updated = base.copyWith(
      text: 'b',
      priority: Priority.high,
      status: Status.done,
      updatedAt: DateTime(2026, 2, 2),
    );
    expect(updated.id, 'id');
    expect(updated.createdAt, DateTime(2026, 1, 1)); // unchanged
    expect(updated.text, 'b');
    expect(updated.priority, Priority.high);
    expect(updated.status, Status.done);
    expect(updated.updatedAt, DateTime(2026, 2, 2));
  });

  test('copyWith with no arguments preserves every field', () {
    // Exercises the `?? this.x` fallback on each field — the path that the
    // selective-replace test above never hits because it always supplies
    // a value.
    final base = Note(
      id: 'id',
      text: 'a',
      priority: Priority.high,
      status: Status.inProgress,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 3, 3),
    );
    final clone = base.copyWith();
    expect(clone.id, base.id);
    expect(clone.text, base.text);
    expect(clone.priority, base.priority);
    expect(clone.status, base.status);
    expect(clone.createdAt, base.createdAt);
    expect(clone.updatedAt, base.updatedAt);
  });
}
