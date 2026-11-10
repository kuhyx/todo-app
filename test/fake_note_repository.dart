import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';

/// In-memory stand-in for [NoteRepository] used by widget tests.
///
/// It implements the same public API but backs it with a plain list and a
/// broadcast [StreamController] — no SQLite, so no pending sqflite timers to
/// fight the widget tester's fake-async clock. Streams emit synchronously on
/// every change, making tests fast and deterministic.
///
/// It also records the last [NoteSort]/[NoteFilter] passed to [watchNotes],
/// so list-screen tests can assert the UI built the right query without
/// re-testing the repository's SQL (covered separately by unit tests).
class FakeNoteRepository implements NoteRepository {
  FakeNoteRepository([List<Note>? initial, this.applyFilter = false])
    : _notes = [...?initial];

  /// When true, [watchNotes] applies the real filter + sort like the SQL
  /// repository; off by default so older tests keep seeing every note.
  final bool applyFilter;

  final List<Note> _notes;
  final _controller = StreamController<List<Note>>.broadcast();
  final _changesController = StreamController<void>.broadcast();

  NoteSort? lastSort;
  NoteFilter? lastFilter;

  /// Calls to [upsert] and to the one-write [bulkUpdate], so a bulk action
  /// can be shown to be one call rather than one write per note.
  int upsertCalls = 0;
  int bulkCalls = 0;

  /// Emits the current snapshot to a new subscriber first (so late-binding
  /// [StreamBuilder]s get the seed), then forwards subsequent changes.
  Stream<List<Note>> _snapshots() async* {
    yield List.unmodifiable(_notes);
    yield* _controller.stream;
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(List.unmodifiable(_notes));
    if (!_changesController.isClosed) _changesController.add(null);
  }

  @override
  Stream<void> get changes => _changesController.stream;

  @override
  Future<void> upsert(Note note) async {
    upsertCalls++;
    _notes
      ..removeWhere((n) => n.id == note.id)
      ..add(note);
    _emit();
  }

  @override
  Future<void> bulkUpdate(
    Set<String> ids, {
    Priority? priority,
    Status? status,
  }) async {
    bulkCalls++;
    for (final (i, n) in _notes.indexed.toList()) {
      if (ids.contains(n.id)) {
        _notes[i] = n.copyWith(priority: priority, status: status);
      }
    }
    _emit();
  }

  @override
  Future<void> saveReplacing(Note note, Iterable<String> removed) async {
    final gone = {...removed, note.id};
    _notes
      ..removeWhere((n) => gone.contains(n.id))
      ..add(note);
    _emit();
  }

  @override
  Future<void> delete(String id) async {
    _notes.removeWhere((n) => n.id == id);
    _emit();
  }

  @override
  Future<ImportOutcome> importNotes(List<Note> incoming) async {
    var added = 0;
    var updated = 0;
    var skipped = 0;
    for (final note in incoming) {
      final i = _notes.indexWhere((n) => n.id == note.id);
      if (i < 0) {
        _notes.add(note);
        added++;
      } else if (note.updatedAt.isAfter(_notes[i].updatedAt)) {
        _notes[i] = note;
        updated++;
      } else {
        skipped++;
      }
    }
    _emit();
    return ImportOutcome(added: added, updated: updated, skipped: skipped);
  }

  @override
  Future<List<Note>> listNotes({
    NoteSort sort = NoteSort.modifiedDesc,
    NoteFilter filter = const NoteFilter(),
  }) async => List.unmodifiable(
    applyFilter ? _notes.where((n) => matchesFilter(n, filter)) : _notes,
  );

  @override
  Stream<List<Note>> watchNotes({
    NoteSort sort = NoteSort.modifiedDesc,
    NoteFilter filter = const NoteFilter(),
  }) {
    lastSort = sort;
    lastFilter = filter;
    if (!applyFilter) return _snapshots();
    return _snapshots().map(
      (all) => [
        for (final n in all)
          if (matchesFilter(n, filter)) n,
      ]..sort(comparatorFor(sort)),
    );
  }

  @override
  Stream<int> watchCount() => _snapshots().map((n) => n.length);

  @override
  Future<Map<String, String>> backfillCreatedBy(
    Set<String> claudeNodes, {
    bool dryRun = false,
  }) async => {};

  @override
  String get nodeId => 'fake-node';

  @override
  Log exportLog() => <String, Record>{};

  @override
  Future<void> importLog(Log remote) async {}

  @override
  Future<void> seedFrom(Log log) async {}

  @override
  Future<void> close() async {
    await _controller.close();
    await _changesController.close();
  }
}
