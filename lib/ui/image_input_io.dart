import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/widgets.dart';

/// Receives pasted or dropped images and the count of non-image files.
typedef ImageInputCallback =
    void Function(List<Uint8List> images, int rejected);

/// Receives dropped files of any type.
typedef FileInputCallback = void Function(List<XFile> files);

/// Off the web there is no document to paste or drop onto (Android attaches
/// through the 📎 button), so this is just [child].
class ImageInputListener extends StatelessWidget {
  /// Wraps [child]; [onImages] is never called on this platform.
  const ImageInputListener({
    required this.onImages,
    required this.onFiles,
    required this.child,
    super.key,
  });

  /// Unused off the web.
  final ImageInputCallback onImages;

  /// Unused off the web.
  final FileInputCallback onFiles;

  /// The screen body.
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
