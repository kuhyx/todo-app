import 'package:todo/data/desktop_backup_client.dart';
import 'package:todo/sync/desktop_wrapper.dart';

/// Writes the Markdown export through the desktop wrapper, so an explicit
/// Export still lands at the canonical `~/todo/BACKLOG.md` path the user's
/// tooling reads — the browser itself cannot write there.
Future<String> exportBacklog(String markdown, int noteCount) async {
  final client = DesktopBackupClient(baseUrl: desktopWrapperOrigin);
  await client.writeBacklog(markdown);
  return 'Exported $noteCount notes to ~/todo/BACKLOG.md';
}
