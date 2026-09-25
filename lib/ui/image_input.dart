/// [ImageInputListener] for the current platform: paste and drag-and-drop on
/// the desktop web build, a pass-through elsewhere.
library;

export 'image_input_io.dart'
    if (dart.library.js_interop) 'image_input_web.dart';
