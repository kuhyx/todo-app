import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:todo/data/note.dart';

// Deliberately free of `dart:io`: the desktop app is a web build, and a single
// `dart:io` import anywhere in the graph makes the whole app fail to compile
// for web. Opening a repository for a real platform lives behind the
// conditional export in `repository_factory.dart`; the legacy sqlite migration
// lives in the io-only `legacy_sqlite_migration.dart`.

/// How the history list should be ordered.
enum NoteSort {
  /// Newest created first.
  createdDesc,

  /// Most recently modified first.
  modifiedDesc,

  /// A-Z by note text.
  alphabetical,

  /// Highest [Priority] first.
  priorityDesc,
}

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

  /// Total notes considered in the import.
  int get total => added + updated + skipped;
}

/// Local-first persistence for [Note]s, backed by the shared `crdt_sync`
/// [LogStore] (was `sqlite_crdt`).
///
/// Every write goes straight to local storage so the app works fully offline.
/// Each [Note] is stored *as* a crdt_sync [Record] (id + per-field
/// last-writer-wins map + sticky tombstone), so the on-disk log **is** the
/// sync wire format — no separate adapter. Filtering and sorting run in Dart
/// over the in-memory log (the record fields are opaque to the library); the
/// note count of a personal backlog is small enough that this is cheap. This
/// class owns the note↔record mapping and exposes a small, intention-revealing
/// API; the log never leaks past this boundary.
class NoteRepository {
  NoteRepository._(this._store, this._nodeId);

  final LogStore _store;
  final String _nodeId;

  /// Fires after each successful write ([upsert], [delete], [importLog], and
  /// transitively [importNotes]). Emits `void` — pull the data on demand.
  Stream<void> get changes => _store.changes;

  // Field names inside each note [Record]; kept identical to the legacy SQL
  // column names so a migrated log round-trips through the same [Note] mapping.
  static const _fText = 'text';
  static const _fPriority = 'priority';
  static const _fStatus = 'status';
  static const _fCreatedAt = 'created_at';
  static const _fUpdatedAt = 'updated_at';

  /// SharedPreferences key holding this device's stable CRDT node id.
  static const kNodeId = 'crdt.nodeId';

  /// SharedPreferences key recording that the legacy sqlite import already ran.
  static const kMigrated = 'crdt.migratedFromSqlite';

  /// File name of the persisted log, used by the io factory.
  static const logFileName = 'todo_notes.json';

  /// Opens (or creates) the note log backed by [persistence].
  ///
  /// Platform wiring — where the log lives, and the one-time legacy sqlite
  /// import — belongs to the callers in `repository_factory_*.dart`, so that
  /// this class stays free of `dart:io` and can compile for web.
  static Future<NoteRepository> openWith({
    required LogPersistence persistence,
    required String nodeId,
  }) async {
    final store = LogStore(persistence: persistence, nodeId: nodeId);
    await store.load();
    return NoteRepository._(store, nodeId);
  }

  /// Replaces the whole log, used by the one-time legacy sqlite migration.
  ///
  /// Distinct from [importLog], which merges: migration seeds a store that is
  /// known to be empty and must preserve the records' own clocks verbatim.
  Future<void> seedFrom(Log log) async {
    if (log.isNotEmpty) await _store.replaceAll(log);
  }

  /// Opens a transient in-memory log; intended for tests.
  static Future<NoteRepository> openInMemory({
    String nodeId = 'test-node',
  }) async {
    final store = LogStore(persistence: _MemoryPersistence(), nodeId: nodeId);
    await store.load();
    return NoteRepository._(store, nodeId);
  }

  /// Builds the record for one migrated legacy note, tombstones included.
  ///
  /// Each note's field clocks are seeded from its own `updated_at`, not "now",
  /// so that when two devices migrate independently, a pre-cutover edit still
  /// wins by real edit time under per-field last-writer-wins instead of being
  /// resolved arbitrarily. Public because the migration that calls it lives in
  /// the io-only library, which cannot reach private members here.
  static Record legacyRecordFor(
    Note note,
    String nodeId, {
    bool deleted = false,
  }) {
    final hlc = Hlc(
      wallTimeMs: note.updatedAt.millisecondsSinceEpoch,
      counter: 0,
      nodeId: nodeId,
    );
    return Record(
      id: note.id,
      fields: _fieldsFor(note, hlc),
      deleted: deleted,
      deletedHlc: deleted ? hlc : null,
    );
  }

  /// Inserts a new note or updates the existing one with the same [id].
  ///
  /// This is the single write path used by the capture screen's
  /// character-by-character autosave: it is cheap and idempotent. All fields
  /// share one fresh monotonic clock (they are written together).
  Future<void> upsert(Note note) async {
    await _store.upsert(
      Record(id: note.id, fields: _fieldsFor(note, _store.nextHlc())),
    );
  }

  /// Soft-deletes a note. The log keeps a sticky tombstone so the deletion
  /// propagates on the next sync instead of resurrecting the record.
  Future<void> delete(String id) => _store.delete(id);

  /// Merges [incoming] notes (e.g. from an imported file) into local storage.
  ///
  /// Safe by design — it never destroys a *newer* local edit: an incoming
  /// note overwrites the local one only when its [Note.updatedAt] is strictly
  /// newer, or when the id is not present locally. Re-importing a stale backup
  /// is therefore a no-op for notes you've since edited. Notes absent from
  /// [incoming] are kept.
  Future<ImportOutcome> importNotes(List<Note> incoming) async {
    final existing = {for (final n in _liveNotes()) n.id: n};
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
  }) async => _query(sort, filter);

  /// Emits the matching, ordered note list immediately and re-emits whenever
  /// the log changes, so the UI stays in sync without manual refreshes.
  Stream<List<Note>> watchNotes({
    NoteSort sort = NoteSort.modifiedDesc,
    NoteFilter filter = const NoteFilter(),
  }) => _watch(() => _query(sort, filter));

  /// Emits the live count of non-deleted notes immediately and on each change.
  Stream<int> watchCount() => _watch(_liveCount);

  /// A stream that emits `compute()` synchronously when first listened to (the
  /// seed), then again on every log change. Seeding in `onListen` — rather than
  /// lazily in an `async*` body — avoids a race where a write between `listen`
  /// and the first generator tick would swallow the initial snapshot.
  Stream<T> _watch<T>(T Function() compute) {
    StreamSubscription<void>? sub;
    late final StreamController<T> controller;
    controller = StreamController<T>(
      onListen: () {
        controller.add(compute());
        sub = _store.changes.listen((_) => controller.add(compute()));
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  /// This device's stable node id. Names its file in the sync repo so two
  /// devices never write the same path.
  String get nodeId => _nodeId;

  /// Returns this device's full note log for upload.
  Log exportLog() => _store.snapshot();

  /// Merges a remote log into local storage (conflict-free, per-field
  /// last-writer-wins with sticky deletes via [mergeLogs]).
  Future<void> importLog(Log remote) async {
    await _store.replaceAll(mergeLogs(_store.snapshot(), remote));
  }

  /// Closes the underlying log and its change stream.
  Future<void> close() => _store.close();

  // --- note <-> record mapping & querying ------------------------------------

  static Map<String, Field> _fieldsFor(Note note, Hlc hlc) => {
    _fText: (note.text, hlc),
    _fPriority: (note.priority.value, hlc),
    _fStatus: (note.status.value, hlc),
    _fCreatedAt: (note.createdAt.toIso8601String(), hlc),
    _fUpdatedAt: (note.updatedAt.toIso8601String(), hlc),
  };

  Note _toNote(Record record) {
    final fields = record.fields;
    return Note(
      id: record.id,
      text: fields[_fText]?.$1 as String? ?? '',
      priority: Priority.fromValue(fields[_fPriority]?.$1 as int?),
      status: Status.fromValue(fields[_fStatus]?.$1 as int?),
      createdAt: _parseDate(fields[_fCreatedAt]?.$1 as String?),
      updatedAt: _parseDate(fields[_fUpdatedAt]?.$1 as String?),
    );
  }

  static DateTime _parseDate(String? iso) => iso == null
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : DateTime.parse(iso);

  Iterable<Note> _liveNotes() =>
      _store.values.where((r) => !r.deleted).map(_toNote);

  int _liveCount() => _store.values.where((r) => !r.deleted).length;

  List<Note> _query(NoteSort sort, NoteFilter filter) {
    final notes = _liveNotes().where((n) => _matches(n, filter)).toList()
      ..sort(_comparator(sort));
    return notes;
  }

  bool _matches(Note note, NoteFilter filter) {
    final query = filter.query.trim().toLowerCase();
    if (query.isNotEmpty && !note.text.toLowerCase().contains(query)) {
      return false;
    }
    if (filter.priorities.isNotEmpty &&
        !filter.priorities.contains(note.priority)) {
      return false;
    }
    if (filter.statuses.isNotEmpty && !filter.statuses.contains(note.status)) {
      return false;
    }
    if (!_withinDays(note.createdAt, filter.createdFrom, filter.createdTo)) {
      return false;
    }
    if (!_withinDays(note.updatedAt, filter.updatedFrom, filter.updatedTo)) {
      return false;
    }
    return true;
  }

  /// Inclusive day-granularity range check, matching the old SQL bounds:
  /// `from` includes its whole day; `to` includes its whole day.
  static bool _withinDays(DateTime value, DateTime? from, DateTime? to) {
    if (from != null && value.isBefore(_startOfDay(from))) return false;
    if (to != null &&
        !value.isBefore(_startOfDay(to).add(const Duration(days: 1)))) {
      return false;
    }
    return true;
  }

  static Comparator<Note> _comparator(NoteSort sort) {
    switch (sort) {
      case NoteSort.createdDesc:
        return (a, b) => b.createdAt.compareTo(a.createdAt);
      case NoteSort.modifiedDesc:
        return (a, b) => b.updatedAt.compareTo(a.updatedAt);
      case NoteSort.alphabetical:
        return (a, b) => a.text.toLowerCase().compareTo(b.text.toLowerCase());
      case NoteSort.priorityDesc:
        return (a, b) {
          final byPriority = b.priority.value.compareTo(a.priority.value);
          return byPriority != 0
              ? byPriority
              : b.updatedAt.compareTo(a.updatedAt);
        };
    }
  }

  /// Midnight (local) of [t]'s calendar day.
  static DateTime _startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);
}

/// In-memory [LogPersistence] for [NoteRepository.openInMemory] (tests).
class _MemoryPersistence implements LogPersistence {
  String? _text;

  @override
  Future<String?> read() async => _text;

  @override
  Future<void> write(String text) async => _text = text;
}

/// An immutable set of constraints for querying notes.
///
/// All fields combine with logical AND. Empty/null fields impose no
/// constraint. Lives in the data layer so the filtering it drives never leaks
/// into the UI. Construct copies with [copyWith] when toggling one facet.
class NoteFilter {
  /// Creates a [NoteFilter] from its constraint fields.
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

  /// Inclusive lower bound (by calendar day) on the creation date.
  final DateTime? createdFrom;

  /// Inclusive upper bound (by calendar day) on the creation date.
  final DateTime? createdTo;

  /// Inclusive lower bound (by calendar day) on the last-updated date.
  final DateTime? updatedFrom;

  /// Inclusive upper bound (by calendar day) on the last-updated date.
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
  /// the current value; clearing a date is done via the dedicated clear
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
