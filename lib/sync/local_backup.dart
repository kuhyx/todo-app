import 'dart:async';

import '../data/note.dart';
import 'notes_markdown.dart';

/// Keeps an always-current Markdown backup of all notes on local disk, and
/// recovers from it on launch.
///
/// This is a third durability layer alongside GitHub auto-sync and Android
/// Auto Backup: a plain human-readable file the user (or an LLM) can read
/// directly. File IO is injected ([reader]/[writer]) so the class is pure and
/// fully testable; the platform-specific path lives in the caller.
///
/// Writes are debounced so a burst of keystrokes produces a single export.
///
/// The note snapshot is pulled lazily via [fetch] only when the debounce
/// fires — never per keystroke — so serialising every note stays off the
/// typing hot path and the cost is independent of how fast the user types.
class LocalBackup {
  LocalBackup({
    required this.fetch,
    required this.reader,
    required this.writer,
    this.debounce = const Duration(seconds: 2),
  });

  /// Pulls the current notes to export. Invoked once per debounced write, so
  /// the O(notes) query + serialization happens at most once per idle window.
  final Future<List<Note>> Function() fetch;

  /// Reads the backup file's contents, or null if it does not exist.
  final Future<String?> Function() reader;

  /// Writes the given Markdown to the backup file (overwriting it).
  final Future<void> Function(String markdown) writer;

  /// How long to wait after the last change before writing.
  final Duration debounce;

  Timer? _timer;

  /// Schedules a debounced backup write. Repeated calls reset the timer, so a
  /// burst of writes collapses to one export of the latest snapshot. A zero
  /// [debounce] exports immediately (and schedules no timer).
  void schedule() {
    _timer?.cancel();
    if (debounce == Duration.zero) {
      unawaited(_export());
    } else {
      _timer = Timer(debounce, () => unawaited(_export()));
    }
  }

  /// Pulls the latest notes and writes the Markdown backup. Returned so tests
  /// (and a zero-debounce caller) can await the write.
  Future<void> _export() async {
    final notes = await fetch();
    await writer(NotesMarkdown.export(notes));
  }

  /// Reads the backup file and parses it into notes for recovery. Returns an
  /// empty list when there is no (usable) backup.
  Future<List<Note>> recover() async {
    final contents = await reader();
    if (contents == null || contents.trim().isEmpty) return const [];
    return NotesMarkdown.parse(contents);
  }

  /// Cancels any pending write. Call from the owner's dispose.
  void dispose() => _timer?.cancel();
}
