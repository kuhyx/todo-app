import 'package:todo/data/desktop_backup_client.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/desktop_wrapper.dart';
import 'package:todo/sync/local_backup.dart';

/// Builds the [LocalBackup] for the browser-hosted desktop app.
///
/// A browser cannot write to the filesystem, so the wrapper that serves the
/// build owns the file. This keeps `~/todo/BACKLOG.md` current — the user's
/// tooling and the `todo` MCP server read it, and without this the move to a
/// web build would let it silently go stale.
LocalBackup createLocalBackup(NoteRepository repository) {
  final client = DesktopBackupClient(baseUrl: desktopWrapperOrigin);
  return LocalBackup(
    fetch: repository.listNotes,
    // Recovery reads the same file back through the wrapper, so a cleared
    // browser profile can still restore from the on-disk backlog.
    reader: client.readBacklog,
    writer: client.writeBacklog,
  );
}
