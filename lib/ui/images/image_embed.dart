/// One attached image as it appears in a note: the picture, or a placeholder
/// saying why it is not here yet. Tapping opens it full screen.
library;

import 'package:flutter/material.dart';

import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/attachments/image_store_scope.dart';
import 'package:todo/images/image_ref.dart';
import 'package:todo/ui/images/image_viewer_screen.dart';
import 'package:todo/ui/images/local_image.dart';

/// Placeholder text for an image this device does not have yet.
const kImageNotDownloaded = 'Not downloaded yet';

/// Tooltip on the badge of an image dufs has not accepted yet.
const kImageWaitingToUpload = 'Waiting to upload';

/// Renders [ref] from the nearest [ImageStoreScope].
class ImageEmbed extends StatelessWidget {
  /// Creates an embed; [fit] is `cover` for thumbnails, `contain` inline.
  const ImageEmbed({
    required this.ref,
    this.fit = BoxFit.cover,
    super.key,
  });

  /// The image to show.
  final ImageRef ref;

  /// How the picture fills the embed's box.
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final store = ImageStoreScope.of(context);
    final source = store.sourceFor(ref);
    final picture = imageFor(source, fit: fit);
    return Semantics(
      label: 'Attached image',
      button: source is! MissingImageSource,
      child: GestureDetector(
        onTap: source is MissingImageSource
            ? null
            : () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ImageViewerScreen(source: source),
                ),
              ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              picture,
              if (store.isPending(ref))
                const Positioned(
                  right: 4,
                  top: 4,
                  child: Tooltip(
                    message: kImageWaitingToUpload,
                    child: Icon(Icons.cloud_upload_outlined, size: 18),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The picture for [source], falling back to the not-downloaded placeholder
/// (also when a network load fails: the wrapper 404s until it has the file).
Widget imageFor(ImageSource source, {required BoxFit fit}) {
  Widget placeholder(BuildContext context, Object error, StackTrace? stack) =>
      const ImagePlaceholder();
  return switch (source) {
    LocalImageSource(:final path) => localImage(
      path,
      fit: fit,
      errorBuilder: placeholder,
    ),
    NetworkImageSource(:final url) => Image.network(
      url,
      fit: fit,
      errorBuilder: placeholder,
    ),
    MissingImageSource() => const ImagePlaceholder(),
  };
}

/// Grey box with [kImageNotDownloaded].
class ImagePlaceholder extends StatelessWidget {
  /// Creates the placeholder.
  const ImagePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            kImageNotDownloaded,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ),
    );
  }
}
