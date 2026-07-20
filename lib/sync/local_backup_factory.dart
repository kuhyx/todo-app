/// Platform entry point for building the Markdown backlog backup.
///
/// Conditional export because `dart:io` is unusable in a browser: mobile writes
/// the file directly, the web desktop app hands it to the local wrapper.
library;

export 'local_backup_factory_io.dart'
    if (dart.library.js_interop) 'local_backup_factory_web.dart';
