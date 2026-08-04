/// Platform entry point for the sync revision cache.
///
/// A conditional export because `dart:io` cannot even be *imported* in a web
/// compile: Android gets a file, the Chrome-wrapper desktop build gets a
/// `SharedPreferences` entry.
library;

export 'sync_state_factory_io.dart'
    if (dart.library.js_interop) 'sync_state_factory_web.dart';
