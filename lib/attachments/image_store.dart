/// `openImageStore()` for the current platform: app storage + direct dufs on
/// Android, the local wrapper's `/images/*` routes on the desktop web build.
library;

export 'image_store_api.dart';
export 'image_store_io.dart'
    if (dart.library.js_interop) 'image_store_web.dart';
