/// Domain model for a single idea/note.
///
/// Notes are stored locally in a CRDT-backed SQLite table (see
/// [NoteRepository]). The CRDT layer manages its own metadata columns
/// (`hlc`, `node_id`, `modified`, `is_deleted`); the fields here are the
/// user-facing data only.
library;

/// Priority tier for a note, used for sorting and visual grouping.
///
/// Every note always has a priority (there is no "none"); [medium] is the
/// default. Stored as the integer [value] so ordering is trivial in SQL.
enum Priority {
  low(1, 'Low'),
  medium(2, 'Medium'),
  high(3, 'High');

  const Priority(this.value, this.label);

  /// The default applied to new notes and to any legacy/unknown value.
  static const Priority defaultValue = Priority.medium;

  /// Integer persisted in the database; higher means more important.
  final int value;

  /// Human-readable label for UI controls (pickers, filters, list rows).
  final String label;

  /// Rebuilds a [Priority] from its stored [value], defaulting to
  /// [defaultValue] for any unknown/legacy value (e.g. the old `0` = none)
  /// so reads never throw and pre-existing notes show as Medium.
  static Priority fromValue(int? value) {
    return Priority.values.firstWhere(
      (p) => p.value == value,
      orElse: () => defaultValue,
    );
  }
}

/// Workflow state of a note, independent of its [Priority].
///
/// Stored as the integer [value]. [todo] is the default (0) so existing
/// notes created before this field existed read back as "to do".
enum Status {
  todo(0, 'To do'),
  inProgress(1, 'In progress'),
  done(2, 'Done'),
  abandoned(3, 'Abandoned');

  const Status(this.value, this.label);

  /// Integer persisted in the database.
  final int value;

  /// Human-readable label for UI controls.
  final String label;

  /// Rebuilds a [Status] from its stored [value], defaulting to [todo]
  /// for any unknown/legacy value so reads never throw.
  static Status fromValue(int? value) {
    return Status.values.firstWhere(
      (s) => s.value == value,
      orElse: () => Status.todo,
    );
  }
}

/// An immutable idea/note record.
class Note {
  const Note({
    required this.id,
    required this.text,
    required this.priority,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Stable unique id (UUID v4). Also the CRDT primary key.
  final String id;

  /// The markdown body of the idea.
  final String text;

  /// Priority tier for sorting/filtering.
  final Priority priority;

  /// Workflow state (to do / in progress / done / abandoned).
  final Status status;

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
      status: Status.fromValue(row['status'] as int?),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  /// Returns a copy with selected fields replaced.
  Note copyWith({
    String? text,
    Priority? priority,
    Status? status,
    DateTime? updatedAt,
  }) {
    return Note(
      id: id,
      text: text ?? this.text,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
