/// Default on-disk locations the desktop wrapper reads and writes.
///
/// Split out of `wrapper_server.dart` (file-length cap); re-exported from
/// there, so callers keep importing the server.
library;

import 'package:path/path.dart' as p;

/// The canonical backlog file for [home], i.e. `~/src/todo/BACKLOG.md`.
///
/// Lives here rather than in `bin/todo_desktop.dart` so it is covered: the
/// entry point is `coverage:ignore-file` thin wiring, and this path silently
/// broke once already. The 2026-09-11 `~` reorganisation moved every repo
/// under `~/src`, but the migration's rewriter only matched *literal*
/// `/home/kuhy/todo` strings — a path assembled from segments was invisible
/// to it, so the wrapper went on exporting to the dead `~/todo` while the
/// `todo` MCP read `~/src/todo`. Every backlog read between 2026-09-11 and
/// 2026-09-12 got a stale file.
String defaultBacklogPath(String home) =>
    p.join(home, 'src', 'todo', 'BACKLOG.md');

/// The wrapper's image cache and upload queue,
/// `~/.local/share/todo-desktop/images` — beside the note-log copy.
String defaultImageCachePath(String home) =>
    p.join(home, '.local', 'share', 'todo-desktop', 'images');
