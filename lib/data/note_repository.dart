import 'package:sqlite_crdt/sqlite_crdt.dart';

import 'note.dart';

/// How the history list should be ordered.
enum NoteSort {
  createdDesc,
  modifiedDesc,
  alphabetical,
  priorityDesc,
}

/// Local-first persistence for [Note]s, backed by a CRDT SQLite database.
///
/// Every write goes straight to local storage so the app works fully
/// offline. The CRDT metadata (Hybrid Logical Clock timestamps per row)
/// lets a future sync layer merge two devices conflict-free using
/// last-writer-wins per note. This class owns the schema and exposes a
/// small, intention-revealing API; SQL never leaks past this boundary.
class NoteRepository {
  NoteRepository._(this._crdt);

  final SqliteCrdt _crdt;

  /// Opens (or creates) the database at [path] and ensures the schema.
  ///
  /// [path] should be an absolute file path on desktop/mobile, or the
  /// special in-memory path used by tests.
  static Future<NoteRepository> open(String path) async {
    final crdt = await SqliteCrdt.open(
      path,
      version: 1,
      onCreate: (db, version) async {
        // Plain columns only; the CRDT layer adds its own bookkeeping
        // columns transparently. ISO-8601 strings keep timestamps both
        // human-readable and lexicographically sortable.
        await db.execute('''
          CREATE TABLE notes (
            id TEXT NOT NULL,
            text TEXT NOT NULL DEFAULT '',
            priority INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (id)
          )
        ''');
      },
    );
    return NoteRepository._(crdt);
  }

  /// Opens a transient in-memory database; intended for tests.
  static Future<NoteRepository> openInMemory() async {
    final crdt = await SqliteCrdt.openInMemory(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE notes (
            id TEXT NOT NULL,
            text TEXT NOT NULL DEFAULT '',
            priority INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (id)
          )
        ''');
      },
    );
    return NoteRepository._(crdt);
  }

  /// Inserts a new note or updates the existing one with the same [id].
  ///
  /// This is the single write path used by the capture screen's
  /// character-by-character autosave: it is cheap and idempotent.
  Future<void> upsert(Note note) async {
    await _crdt.execute(
      '''
      INSERT INTO notes (id, text, priority, created_at, updated_at)
      VALUES (?1, ?2, ?3, ?4, ?5)
      ON CONFLICT (id) DO UPDATE SET
        text = ?2,
        priority = ?3,
        updated_at = ?5
      ''',
      [
        note.id,
        note.text,
        note.priority.value,
        note.createdAt.toIso8601String(),
        note.updatedAt.toIso8601String(),
      ],
    );
  }

  /// Soft-deletes a note. The CRDT keeps a tombstone so the deletion
  /// propagates on the next sync instead of resurrecting the row.
  Future<void> delete(String id) async {
    await _crdt.execute('DELETE FROM notes WHERE id = ?1', [id]);
  }

  /// Returns all live notes ordered by [sort].
  Future<List<Note>> listNotes({
    NoteSort sort = NoteSort.modifiedDesc,
  }) async {
    final rows = await _crdt
        .query('SELECT * FROM notes WHERE is_deleted = 0 ${_orderBy(sort)}');
    return rows.map(Note.fromRow).toList();
  }

  /// Emits the ordered note list and re-emits whenever the table changes,
  /// so the UI can stay in sync without manual refreshes.
  Stream<List<Note>> watchNotes({
    NoteSort sort = NoteSort.modifiedDesc,
  }) {
    return _crdt
        .watch('SELECT * FROM notes WHERE is_deleted = 0 ${_orderBy(sort)}')
        .map((rows) => rows.map(Note.fromRow).toList());
  }

  /// This device's stable CRDT node id. Used to name its changeset file
  /// in the sync repo so two devices never write the same file.
  String get nodeId => _crdt.nodeId;

  /// Returns this device's full CRDT changeset for upload.
  Future<CrdtChangeset> getChangeset() => _crdt.getChangeset();

  /// Merges a remote changeset into local storage (conflict-free,
  /// last-writer-wins per row via the Hybrid Logical Clock).
  Future<void> merge(CrdtChangeset changeset) => _crdt.merge(changeset);

  /// Closes the underlying database.
  Future<void> close() => _crdt.close();

  /// Maps a [NoteSort] to a SQL ORDER BY clause. Centralised so the sort
  /// options used by the live and one-shot queries can never drift apart.
  String _orderBy(NoteSort sort) {
    switch (sort) {
      case NoteSort.createdDesc:
        return 'ORDER BY created_at DESC';
      case NoteSort.modifiedDesc:
        return 'ORDER BY updated_at DESC';
      case NoteSort.alphabetical:
        return 'ORDER BY text COLLATE NOCASE ASC';
      case NoteSort.priorityDesc:
        return 'ORDER BY priority DESC, updated_at DESC';
    }
  }
}
