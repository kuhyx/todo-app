/// Domain model for a single idea/note.
///
/// Notes are stored locally in a CRDT-backed SQLite table (see
/// [NoteRepository]). The CRDT layer manages its own metadata columns
/// (`hlc`, `node_id`, `modified`, `is_deleted`); the fields here are the
/// user-facing data only.
library;

/// Priority tier for a note, used for sorting and visual grouping.
///
/// Stored as the integer [value] so ordering is trivial in SQL.
enum Priority {
  none(0),
  low(1),
  medium(2),
  high(3);

  const Priority(this.value);

  /// Integer persisted in the database; higher means more important.
  final int value;

  /// Rebuilds a [Priority] from its stored [value], defaulting to [none]
  /// for any unknown/legacy value so reads never throw.
  static Priority fromValue(int? value) {
    return Priority.values.firstWhere(
      (p) => p.value == value,
      orElse: () => Priority.none,
    );
  }
}

/// An immutable idea/note record.
class Note {
  const Note({
    required this.id,
    required this.text,
    required this.priority,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Stable unique id (UUID v4). Also the CRDT primary key.
  final String id;

  /// The markdown body of the idea.
  final String text;

  /// Priority tier for sorting/filtering.
  final Priority priority;

  /// When the note was first created (set once, never changed).
  final DateTime createdAt;

  /// When the note's content was last modified locally.
  final DateTime updatedAt;

  /// Builds a [Note] from a raw CRDT query row.
  ///
  /// Timestamps are stored as ISO-8601 strings for human-readable,
  /// lexicographically sortable values.
  factory Note.fromRow(Map<String, Object?> row) {
    return Note(
      id: row['id'] as String,
      text: (row['text'] as String?) ?? '',
      priority: Priority.fromValue(row['priority'] as int?),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  /// Returns a copy with selected fields replaced.
  Note copyWith({String? text, Priority? priority, DateTime? updatedAt}) {
    return Note(
      id: id,
      text: text ?? this.text,
      priority: priority ?? this.priority,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
