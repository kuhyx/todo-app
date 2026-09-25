import 'package:flutter/material.dart';

import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/ui/images/image_embed.dart';

/// One image, full screen, pinch/scroll to zoom.
class ImageViewerScreen extends StatelessWidget {
  /// Creates the viewer for [source].
  const ImageViewerScreen({required this.source, super.key});

  /// Where the image is drawn from.
  final ImageSource source;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: InteractiveViewer(
        maxScale: 8,
        child: Center(child: imageFor(source, fit: BoxFit.contain)),
      ),
    );
  }
}
