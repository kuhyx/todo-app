/// Platform entry point for opening the note store.
///
/// Conditional export because `dart:io` cannot even be *imported* in a web
/// compile: mobile gets the file-backed store plus the legacy sqlite import,
/// web gets IndexedDB plus the desktop wrapper's disk copy.
library;

export 'repository_factory_io.dart'
    if (dart.library.js_interop) 'repository_factory_web.dart';
