/// `Image.file` without importing `dart:io` into web code.
library;

export 'local_image_io.dart'
    if (dart.library.js_interop) 'local_image_web.dart';
