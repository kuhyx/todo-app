/// Platform entry point for the explicit "Export notes" action.
///
/// Conditional export because `dart:io` is unusable in a browser: mobile shares
/// a temp file, io desktop writes `~/todo/BACKLOG.md` directly, and the web
/// desktop app asks the local wrapper to write that same path.
library;

export 'backlog_export_io.dart'
    if (dart.library.js_interop) 'backlog_export_web.dart';
