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
  FakeNoteRepository([List<Note>? initial]) : _notes = [...?initial];

  final List<Note> _notes;
  final _controller = StreamController<List<Note>>.broadcast();
  final _changesController = StreamController<void>.broadcast();

  NoteSort? lastSort;
  NoteFilter? lastFilter;

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
    _notes
      ..removeWhere((n) => n.id == note.id)
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
  }) async => List.unmodifiable(_notes);

  @override
  Stream<List<Note>> watchNotes({
    NoteSort sort = NoteSort.modifiedDesc,
    NoteFilter filter = const NoteFilter(),
  }) {
    lastSort = sort;
    lastFilter = filter;
    return _snapshots();
  }

  @override
  Stream<int> watchCount() => _snapshots().map((n) => n.length);

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
