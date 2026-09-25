import 'dart:typed_data';

import 'package:flutter/widgets.dart';

/// Receives pasted or dropped images and the count of non-image files.
typedef ImageInputCallback =
    void Function(List<Uint8List> images, int rejected);

/// Off the web there is no document to paste or drop onto (Android attaches
/// through the 📎 button), so this is just [child].
class ImageInputListener extends StatelessWidget {
  /// Wraps [child]; [onImages] is never called on this platform.
  const ImageInputListener({
    required this.onImages,
    required this.child,
    super.key,
  });

  /// Unused off the web.
  final ImageInputCallback onImages;

  /// The screen body.
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
