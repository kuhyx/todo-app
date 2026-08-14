/// Shared fixtures for the note_repository test files.
///
/// `note_repository_test.dart` was split by concern for file size; these are
/// the pieces every split needs. Deliberately NOT named `*_test.dart`: the
/// runner would collect it and fail on the missing `main()`.
library;

import 'package:todo/data/note.dart';

/// A note with sensible defaults, timestamped now unless told otherwise.
///
/// Each test file builds its own notes rather than sharing a corpus, so a
/// change to one file's fixtures cannot silently retune another's assertions.
Note noteFixture(
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
