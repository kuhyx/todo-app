/// Two small companions of [NoteRepository]: the result of an import, and
/// the in-memory store its test constructor uses.
///
/// Split out of `note_repository.dart` for file size; that file re-exports
/// this one.
library;

import 'package:crdt_sync/crdt_sync.dart';

/// Summary of an [NoteRepository.importNotes] run, for user feedback.
class ImportOutcome {
  /// Creates an [ImportOutcome] from its per-category counts.
  const ImportOutcome({
    required this.added,
    required this.updated,
    required this.skipped,
  });

  /// Notes that did not exist locally and were created.
  final int added;

  /// Existing notes overwritten because the import was newer.
  final int updated;

  /// Notes skipped because the local copy was the same age or newer.
  final int skipped;
}

/// In-memory [LogPersistence] for [NoteRepository.openInMemory] (tests).
class MemoryPersistence implements LogPersistence {
  String? _text;

  @override
  Future<String?> read() async => _text;

  @override
  Future<void> write(String text) async => _text = text;
}
