/// The capture screen's in-progress note, and how it reaches storage.
///
/// Split out of `capture_screen.dart` for file size. It is the model behind
/// the app's central invariant — every keystroke is already persisted — so it
/// is kept free of Flutter state: the screen decides when to rebuild, this
/// decides what is saved.
///
/// The row is created lazily, on the first non-empty keystroke, so an
/// untouched template never reaches storage.
library;

import 'package:flutter/foundation.dart';

import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/local_backup.dart';
import 'package:todo/sync/local_backup_factory.dart';
import 'package:uuid/uuid.dart';

/// Holds the draft being captured and writes it through to [repository].
class CaptureDraft {
  /// Creates a draft writing to [repository].
  CaptureDraft(this.repository);

  /// Where the draft is persisted on every change.
  final NoteRepository repository;

  final Uuid _uuid = const Uuid();

  /// When the draft was last written locally; null until the first save.
  final ValueNotifier<DateTime?> lastSavedAt = ValueNotifier<DateTime?>(null);

  String _text = '';
  String? _id;
  DateTime? _createdAt;

  /// The draft's priority, applied to every write.
  Priority priority = Priority.defaultValue;

  /// The draft's status, applied to every write.
  Status status = Status.todo;

  /// Persists [text], creating the note row on the first non-empty keystroke.
  ///
  /// Returns whether the row was created by this call, so the caller can log
  /// it once rather than on every keystroke.
  Future<bool> write(String text, {required bool Function() live}) async {
    _text = text;
    var created = false;
    if (_id == null) {
      // A note is only created once the user actually fills something in, so
      // an empty template (no section typed yet) never hits storage.
      if (text.trim().isEmpty) return false;
      _id = _uuid.v4();
      _createdAt = DateTime.now();
      created = true;
    }
    await _save(live: live);
    return created;
  }

  /// Re-saves when only priority/status changed.
  ///
  /// Does nothing before the row exists: the new value is already held here
  /// and will be applied by the first keystroke that creates it.
  Future<void> persistMetadata({required bool Function() live}) async {
    if (_id == null) return;
    await _save(live: live);
  }

  Future<void> _save({required bool Function() live}) async {
    final now = DateTime.now();
    await repository.upsert(
      Note(
        id: _id!,
        text: _text,
        priority: priority,
        status: status,
        createdAt: _createdAt!,
        updatedAt: now,
      ),
    );
    if (live()) lastSavedAt.value = now;
  }

  /// Forgets the current draft so the next keystroke starts a new note.
  ///
  /// Nothing is lost: every keystroke was already persisted, which is why
  /// the field going blank is the only feedback the screen needs to give.
  void reset() {
    _text = '';
    _id = null;
    _createdAt = null;
    priority = Priority.defaultValue;
    status = Status.todo;
    lastSavedAt.value = null;
  }

  /// Releases the notifier.
  void dispose() => lastSavedAt.dispose();
}

// coverage:ignore-start
// Platform file IO for the local backup: BACKLOG.md under ~/todo on desktop
// (the path the user's workflow already reads), or the app documents dir on
// mobile (which Android Auto Backup includes). Exercised by running the app;
// tests inject an in-memory LocalBackup instead.
/// The local backup implementation for whichever platform this is.
LocalBackup platformLocalBackup(NoteRepository repository) =>
    createLocalBackup(repository);
// coverage:ignore-end
