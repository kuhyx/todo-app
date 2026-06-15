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
class LocalBackup {
  LocalBackup({
    required this.reader,
    required this.writer,
    this.debounce = const Duration(seconds: 2),
  });

  /// Reads the backup file's contents, or null if it does not exist.
  final Future<String?> Function() reader;

  /// Writes the given Markdown to the backup file (overwriting it).
  final Future<void> Function(String markdown) writer;

  /// How long to wait after the last change before writing.
  final Duration debounce;

  Timer? _timer;

  /// Schedules a debounced export of [notes]. Repeated calls reset the timer,
  /// so only the latest snapshot is written. A zero [debounce] writes
  /// immediately (and schedules no timer).
  void scheduleExport(List<Note> notes) {
    _timer?.cancel();
    final markdown = NotesMarkdown.export(notes);
    if (debounce == Duration.zero) {
      writer(markdown);
    } else {
      _timer = Timer(debounce, () => writer(markdown));
    }
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
