import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

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
  final home = Platform.environment['HOME'] ?? Directory.current.path;
  final dir = Directory('$home/todo');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final file = File('${dir.path}/BACKLOG.md');
  await file.writeAsString(markdown);
  return 'Exported $noteCount notes to ${file.path}';
}
