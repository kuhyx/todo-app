import 'package:sqlite_crdt/sqlite_crdt.dart';

import 'note.dart';

/// How the history list should be ordered.
enum NoteSort { createdDesc, modifiedDesc, alphabetical, priorityDesc }

/// Summary of an [NoteRepository.importNotes] run, for user feedback.
class ImportOutcome {
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

  /// Total notes considered in the import.
  int get total => added + updated + skipped;
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
      version: _schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return NoteRepository._(crdt);
  }

  /// Opens a transient in-memory database; intended for tests.
  static Future<NoteRepository> openInMemory() async {
    final crdt = await SqliteCrdt.openInMemory(
      version: _schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return NoteRepository._(crdt);
  }

  /// Current schema version. Bump when adding columns and add the matching
  /// branch to [_onUpgrade] so existing on-device databases migrate.
  static const int _schemaVersion = 3;

  /// Creates the schema for a brand-new database. Plain columns only; the
  /// CRDT layer adds its own bookkeeping columns transparently. ISO-8601
  /// strings keep timestamps human-readable and lexicographically sortable.
  static Future<void> _onCreate(CrdtTableExecutor db, int version) async {
    await db.execute('''
      CREATE TABLE notes (
        id TEXT NOT NULL,
        text TEXT NOT NULL DEFAULT '',
        priority INTEGER NOT NULL DEFAULT 2,
        status INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (id)
      )
    ''');
  }

  /// Migrates an existing database forward one version at a time.
  ///
  /// - v1 → v2 adds the [Status] column (rows back-fill to `Status.todo`).
  /// - v2 → v3 drops the old "none" priority: any legacy `0` becomes
  ///   `Priority.medium` (2) so every note has a real priority and shows up
  ///   in priority filters. This runs deterministically on every device, so
  ///   the back-fill converges without needing a synced changeset.
  static Future<void> _onUpgrade(CrdtTableExecutor db, int from, int to) async {
    if (from < 2) {
      await db.execute(
        'ALTER TABLE notes ADD COLUMN status INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (from < 3) {
      await db.execute('UPDATE notes SET priority = 2 WHERE priority = 0');
    }
  }

  /// Inserts a new note or updates the existing one with the same [id].
  ///
  /// This is the single write path used by the capture screen's
  /// character-by-character autosave: it is cheap and idempotent.
  Future<void> upsert(Note note) async {
    await _crdt.execute(
      '''
      INSERT INTO notes (id, text, priority, status, created_at, updated_at)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6)
      ON CONFLICT (id) DO UPDATE SET
        text = ?2,
        priority = ?3,
        status = ?4,
        updated_at = ?6
      ''',
      [
        note.id,
        note.text,
        note.priority.value,
        note.status.value,
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

  /// Merges [incoming] notes (e.g. from an imported file) into local storage.
  ///
  /// Safe by design — it never destroys a *newer* local edit: an incoming
  /// note overwrites the local one only when its [Note.updatedAt] is strictly
  /// newer, or when the id is not present locally. This makes re-importing a
  /// stale backup a no-op for notes you've since edited, upholding the
  /// "never lose ideas" guarantee. Notes absent from [incoming] are kept.
  Future<ImportOutcome> importNotes(List<Note> incoming) async {
    final existing = {for (final n in await listNotes()) n.id: n};
    var added = 0;
    var updated = 0;
    var skipped = 0;
    for (final note in incoming) {
      final local = existing[note.id];
      if (local == null) {
        await upsert(note);
        added++;
      } else if (note.updatedAt.isAfter(local.updatedAt)) {
        await upsert(note);
        updated++;
      } else {
        skipped++;
      }
    }
    return ImportOutcome(added: added, updated: updated, skipped: skipped);
  }

  /// Returns the live notes matching [filter], ordered by [sort].
  Future<List<Note>> listNotes({
    NoteSort sort = NoteSort.modifiedDesc,
    NoteFilter filter = const NoteFilter(),
  }) async {
    final (where, args) = _buildWhere(filter);
    final rows = await _crdt.query(
      'SELECT * FROM notes WHERE $where ${_orderBy(sort)}',
      args,
    );
    return rows.map(Note.fromRow).toList();
  }

  /// Emits the matching, ordered note list and re-emits whenever the table
  /// changes, so the UI can stay in sync without manual refreshes.
  ///
  /// [watch] takes an args *builder* (`() => args`); the captured [args]
  /// list is immutable for this call because [filter] is immutable, so the
  /// builder is safe to re-invoke.
  Stream<List<Note>> watchNotes({
    NoteSort sort = NoteSort.modifiedDesc,
    NoteFilter filter = const NoteFilter(),
  }) {
    final (where, args) = _buildWhere(filter);
    return _crdt
        .watch('SELECT * FROM notes WHERE $where ${_orderBy(sort)}', () => args)
        .map((rows) => rows.map(Note.fromRow).toList());
  }

  /// Emits the live count of non-deleted notes. Cheaper than [watchNotes]
  /// for a header badge: SQLite computes the count without materialising or
  /// parsing any rows, so per-keystroke autosave doesn't churn the UI.
  Stream<int> watchCount() {
    return _crdt
        .watch('SELECT COUNT(*) AS c FROM notes WHERE is_deleted = 0')
        .map((rows) => (rows.first['c'] as int?) ?? 0);
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

  /// Builds the parameterised WHERE clause for [filter].
  ///
  /// Returns the clause body (always rooted at `is_deleted = 0` so
  /// tombstones stay hidden) and the positional argument list. All user
  /// input is bound as parameters — never string-interpolated — so the
  /// query is injection-safe. Date bounds use ISO-8601 string comparison,
  /// which is valid because the stored timestamps are fixed-width and
  /// lexicographically ordered.
  (String, List<Object?>) _buildWhere(NoteFilter filter) {
    final clauses = <String>['is_deleted = 0'];
    final args = <Object?>[];

    final query = filter.query.trim();
    if (query.isNotEmpty) {
      // Escape LIKE wildcards in the user's text so a literal '%' or '_'
      // matches itself. LIKE is ASCII-case-insensitive by default.
      final escaped = query
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      clauses.add(r"text LIKE ? ESCAPE '\'");
      args.add('%$escaped%');
    }

    if (filter.priorities.isNotEmpty) {
      final placeholders = List.filled(
        filter.priorities.length,
        '?',
      ).join(', ');
      clauses.add('priority IN ($placeholders)');
      args.addAll(filter.priorities.map((p) => p.value));
    }

    if (filter.statuses.isNotEmpty) {
      final placeholders = List.filled(filter.statuses.length, '?').join(', ');
      clauses.add('status IN ($placeholders)');
      args.addAll(filter.statuses.map((s) => s.value));
    }

    _addDateBounds(
      clauses,
      args,
      'created_at',
      filter.createdFrom,
      filter.createdTo,
    );
    _addDateBounds(
      clauses,
      args,
      'updated_at',
      filter.updatedFrom,
      filter.updatedTo,
    );

    return (clauses.join(' AND '), args);
  }

  /// Appends inclusive day-granularity bounds for [column] to [clauses].
  ///
  /// [from]/[to] are treated as whole calendar days: `from` includes its
  /// entire day (compared from 00:00:00) and `to` includes its entire day
  /// (compared with `< to+1 day`), matching how a user reads a date range.
  void _addDateBounds(
    List<String> clauses,
    List<Object?> args,
    String column,
    DateTime? from,
    DateTime? to,
  ) {
    if (from != null) {
      clauses.add('$column >= ?');
      args.add(_startOfDay(from).toIso8601String());
    }
    if (to != null) {
      clauses.add('$column < ?');
      args.add(_startOfDay(to).add(const Duration(days: 1)).toIso8601String());
    }
  }

  /// Midnight (local) of [t]'s calendar day.
  static DateTime _startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);
}

/// An immutable set of constraints for querying notes.
///
/// All fields combine with logical AND. Empty/null fields impose no
/// constraint. Lives in the data layer so the SQL it drives never leaks
/// into the UI. Construct copies with [copyWith] when toggling one facet.
class NoteFilter {
  const NoteFilter({
    this.query = '',
    this.priorities = const {},
    this.statuses = const {},
    this.createdFrom,
    this.createdTo,
    this.updatedFrom,
    this.updatedTo,
  });

  /// Case-insensitive substring matched against the note body.
  final String query;

  /// Notes must have one of these priorities. Empty means "any priority".
  final Set<Priority> priorities;

  /// Notes must have one of these statuses. Empty means "any status".
  final Set<Status> statuses;

  /// Inclusive lower/upper bounds (by calendar day) on the creation date.
  final DateTime? createdFrom;
  final DateTime? createdTo;

  /// Inclusive lower/upper bounds (by calendar day) on the last-updated date.
  final DateTime? updatedFrom;
  final DateTime? updatedTo;

  /// True when no constraint is active (the unfiltered, full list).
  bool get isEmpty =>
      query.trim().isEmpty &&
      priorities.isEmpty &&
      statuses.isEmpty &&
      createdFrom == null &&
      createdTo == null &&
      updatedFrom == null &&
      updatedTo == null;

  /// Number of distinct active facets, for an "N filters" badge in the UI.
  int get activeCount {
    var n = 0;
    if (query.trim().isNotEmpty) n++;
    if (priorities.isNotEmpty) n++;
    if (statuses.isNotEmpty) n++;
    if (createdFrom != null || createdTo != null) n++;
    if (updatedFrom != null || updatedTo != null) n++;
    return n;
  }

  /// Returns a copy with selected facets replaced. A `null` argument keeps
  /// the current value; clearing a date is done via the dedicated [clear]
  /// flags so `null` can mean "unchanged".
  NoteFilter copyWith({
    String? query,
    Set<Priority>? priorities,
    Set<Status>? statuses,
    DateTime? createdFrom,
    DateTime? createdTo,
    DateTime? updatedFrom,
    DateTime? updatedTo,
    bool clearCreated = false,
    bool clearUpdated = false,
  }) {
    return NoteFilter(
      query: query ?? this.query,
      priorities: priorities ?? this.priorities,
      statuses: statuses ?? this.statuses,
      createdFrom: clearCreated ? null : (createdFrom ?? this.createdFrom),
      createdTo: clearCreated ? null : (createdTo ?? this.createdTo),
      updatedFrom: clearUpdated ? null : (updatedFrom ?? this.updatedFrom),
      updatedTo: clearUpdated ? null : (updatedTo ?? this.updatedTo),
    );
  }
}
