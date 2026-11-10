/// Domain model for a single idea/note.
///
/// Notes are stored as crdt_sync records (see [NoteRepository] and
/// `note_record.dart`); the clocks and tombstones live there, the fields
/// here are the user-facing data only.
library;

/// Priority tier for a note, used for sorting and visual grouping.
///
/// Every note always has a priority (there is no "none"); [medium] is the
/// default. Stored as the integer [value] so ordering is trivial in SQL.
enum Priority {
  /// Lowest priority tier.
  low(1, 'Low'),

  /// Default priority tier for a new note.
  medium(2, 'Medium'),

  /// Highest priority tier.
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
  /// Default status for a new or legacy note.
  todo(0, 'To do'),

  /// Actively being worked on.
  inProgress(1, 'In progress'),

  /// Finished.
  done(2, 'Done'),

  /// Deliberately dropped, not finished.
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

/// The values the optional `by` and `created_by` fields may hold.
const Set<String> kNoteAuthors = {'claude', 'kuhy'};

/// An immutable idea/note record.
///
/// A note with a [repo] is a *repo task* (an outstanding piece of work in
/// that repository, closable with [evidence]); one without is a plain idea.
/// The four task fields are optional and set-once in practice: they are
/// written only when a user or the CLI sets them, never by ordinary edits of
/// an idea, which keeps such edits wire-identical to the v3 build.
class Note {
  /// Creates a [Note] from its stored fields.
  const Note({
    required this.id,
    required this.text,
    required this.priority,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.repo,
    this.doneCheck,
    this.by,
    this.evidence,
    this.createdBy,
  });

  /// Builds a [Note] from a raw CRDT query row.
  ///
  /// Timestamps are stored as ISO-8601 strings for human-readable,
  /// lexicographically sortable values.
  factory Note.fromRow(Map<String, Object?> row) {
    return Note(
      id: row['id']! as String,
      text: (row['text'] as String?) ?? '',
      priority: Priority.fromValue(row['priority'] as int?),
      status: Status.fromValue(row['status'] as int?),
      createdAt: DateTime.parse(row['created_at']! as String),
      updatedAt: DateTime.parse(row['updated_at']! as String),
    );
  }

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

  /// Repository a task belongs to (`kuhyx/<name>`); null for a plain idea.
  final String? repo;

  /// Shell command, run from the repo root, whose exit 0 proves the task done.
  final String? doneCheck;

  /// Who does the task: one of [kNoteAuthors].
  final String? by;

  /// Proof the task was closed (commit sha + the done check's exit code).
  final String? evidence;

  /// Who filed the note: one of [kNoteAuthors]; null (older notes) means kuhy.
  final String? createdBy;

  /// Whether Claude filed this note (hidden by default, sorted last).
  bool get isClaudeMade => createdBy == 'claude';

  /// Whether this note is a repo task rather than a plain idea.
  bool get isRepoTask => repo != null;

  /// The repo without its owner ("kartka" for "kuhyx/kartka"), or null.
  String? get repoName => repo?.split('/').last;

  /// Returns a copy with selected fields replaced.
  Note copyWith({
    String? text,
    Priority? priority,
    Status? status,
    DateTime? updatedAt,
    String? repo,
    String? doneCheck,
    String? by,
    String? evidence,
    String? createdBy,
  }) {
    return Note(
      id: id,
      text: text ?? this.text,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      repo: repo ?? this.repo,
      doneCheck: doneCheck ?? this.doneCheck,
      by: by ?? this.by,
      evidence: evidence ?? this.evidence,
      createdBy: createdBy ?? this.createdBy,
    );
  }
}
