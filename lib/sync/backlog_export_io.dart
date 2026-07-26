import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Resolves the home directory the desktop export writes under.
///
/// Overridable **so the test suite never writes to the real `~/todo`**. This is
/// not hypothetical: before this seam existed, running `flutter test` exported
/// a fake note over the user's canonical `~/todo/BACKLOG.md` every time.
String Function() resolveExportHome = () =>
    Platform.environment['HOME'] ?? Directory.current.path;

/// Writes the Markdown export somewhere the user can get at it, and returns a
/// human-readable description of where it went.
///
/// On mobile this opens the system share sheet; on a `dart:io` desktop host it
/// writes the canonical `~/todo/BACKLOG.md`.
Future<String> exportBacklog(String markdown, int noteCount) async {
  // coverage:ignore-start
  // Mobile-only share path: Platform.isAndroid/isIOS are always false on the
  // Linux test host, so these lines are structurally unreachable in CI and
  // excluded from the coverage denominator. Verified on-device.
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/todo-backlog.md');
    await file.writeAsString(markdown);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/markdown')],
        subject: 'todo backlog ($noteCount notes)',
      ),
    );
    return 'Shared $noteCount notes';
  }
  // coverage:ignore-end
  final home = resolveExportHome();
  final dir = Directory('$home/todo');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final file = File('${dir.path}/BACKLOG.md');
  await file.writeAsString(markdown);
  return 'Exported $noteCount notes to ${file.path}';
}
