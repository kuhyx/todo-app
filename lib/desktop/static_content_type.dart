/// Content types for the web build's static assets, served by the wrapper.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Content type for [filePath].
///
/// Flutter web is strict here: CanvasKit refuses to instantiate a `.wasm`
/// served as anything but `application/wasm`, and the app silently fails to
/// render if the bootstrap `.js` is mislabelled.
ContentType staticContentTypeFor(String filePath) {
  switch (p.extension(filePath).toLowerCase()) {
    case '.html':
      return ContentType.html;
    case '.js' || '.mjs':
      return ContentType('text', 'javascript', charset: 'utf-8');
    case '.json':
      return ContentType.json;
    case '.wasm':
      return ContentType('application', 'wasm');
    case '.css':
      return ContentType('text', 'css', charset: 'utf-8');
    case '.png':
      return ContentType('image', 'png');
    case '.jpg' || '.jpeg':
      return ContentType('image', 'jpeg');
    case '.svg':
      return ContentType('image', 'svg+xml');
    case '.ttf':
      return ContentType('font', 'ttf');
    case '.otf':
      return ContentType('font', 'otf');
    case '.woff2':
      return ContentType('font', 'woff2');
    case '.bin' || '.symbols':
      return ContentType.binary;
    default:
      return ContentType.binary;
  }
}
