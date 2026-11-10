/// What the CLI can be asked to do, and how a bad command line is reported.
library;

/// What the CLI was asked to do.
enum CliMode {
  /// Create a note and push it.
  add,

  /// Print every live note, one per line.
  list,

  /// Print one note in full.
  get,

  /// Tombstone one note and push the deletion.
  delete,

  /// Change one note's status and push it.
  setStatus,

  /// Replace one note's whole text and push it.
  setText,

  /// Set a task done with evidence and push it.
  close,

  /// Print the notes matching a query, as [list] does.
  search,

  /// Set `created_by` on notes that lack it.
  backfill,

  /// Print usage.
  help,
}

/// Thrown for a malformed command line; maps to exit code 2.
class UsageError implements Exception {
  /// Creates a [UsageError] carrying [message].
  UsageError(this.message);

  /// What was wrong with the arguments.
  final String message;

  @override
  String toString() => message;
}
