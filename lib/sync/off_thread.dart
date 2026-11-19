/// Runs CPU-heavy, pure work away from the UI thread where the platform can.
///
/// Conditional export because `dart:isolate` does not run in a browser: the
/// web desktop build runs the work inline, everything else on a fresh isolate.
library;

export 'off_thread_io.dart' if (dart.library.js_interop) 'off_thread_web.dart';
