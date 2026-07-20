// coverage:ignore-file
// Real-filesystem platform wiring, extracted verbatim from the
// `coverage:ignore` block it previously lived in inside capture_screen.dart.
// It resolves paths from the actual HOME/documents directory, so exercising it
// under test would write outside the sandbox; tests inject an in-memory
// LocalBackup instead. Verified by running the app.
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/local_backup.dart';

/// Builds the platform [LocalBackup] on a `dart:io` host (Android).
///
/// On mobile this lives in the app's documents directory, where Android Auto
/// Backup can pick it up.
LocalBackup createLocalBackup(NoteRepository repository) {
  Future<File> backupFile() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/todo-backlog.md');
    }
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    final dir = Directory('$home/todo')..createSync(recursive: true);
    return File('${dir.path}/BACKLOG.md');
  }

  return LocalBackup(
    fetch: repository.listNotes,
    reader: () async {
      final file = await backupFile();
      return file.existsSync() ? file.readAsString() : null;
    },
    writer: (markdown) async => (await backupFile()).writeAsString(markdown),
  );
}
