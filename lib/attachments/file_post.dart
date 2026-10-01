/// `postFile` for the current platform: the browser's own `fetch` on the
/// desktop web build, so a picked file streams from disk to the wrapper
/// without ever becoming a Dart byte list.
library;

export 'file_post_io.dart' if (dart.library.js_interop) 'file_post_web.dart';
