/// What the UI asks of attached images, independent of platform.
///
/// Android keeps images itself (an `ImageCacheStore` in app storage, talking
/// to dufs directly); the desktop web page delegates everything to the local
/// wrapper's `/images/*` routes. Both implement [ImageStore], picked by the
/// conditional export in `image_store.dart`.
library;

import 'package:flutter/foundation.dart';

import 'package:todo/images/image_ref.dart';

/// Where to draw an image from right now.
sealed class ImageSource {
  const ImageSource();
}

/// A file on this device.
final class LocalImageSource extends ImageSource {
  /// Creates a source for the file at [path].
  const LocalImageSource(this.path);

  /// Absolute path of the cached JPEG.
  final String path;
}

/// A same-origin URL served by the desktop wrapper.
final class NetworkImageSource extends ImageSource {
  /// Creates a source for [url].
  const NetworkImageSource(this.url);

  /// The wrapper URL, e.g. `http://localhost:8730/images/<noteId>/<uuid>.jpg`.
  final String url;
}

/// Not on this device yet (it downloads on the next reconcile).
final class MissingImageSource extends ImageSource {
  /// The one instance.
  const MissingImageSource();
}

/// Summary for the settings screen.
class ImageStoreStatus {
  /// Creates a status.
  const ImageStoreStatus({required this.configured, required this.pending});

  /// Whether a dufs login is available to this device.
  final bool configured;

  /// Images waiting to upload.
  final int pending;
}

/// Thrown by [ImageStore.attach] when the image could not be stored at all.
class ImageStoreException implements Exception {
  /// Creates an exception carrying [message].
  const ImageStoreException(this.message);

  /// What went wrong, shown to the user.
  final String message;

  @override
  String toString() => message;
}

/// Stores, shows and syncs the images notes link to. Notifies when an image
/// becomes available or changes state, so embeds can redraw.
abstract class ImageStore extends ChangeNotifier {
  /// Stores [bytes] (any image format) for [noteId] and queues the upload.
  ///
  /// Returns the new ref, or null when [bytes] is not an image. Throws
  /// [ImageStoreException] when it cannot be stored.
  Future<ImageRef?> attach(String noteId, Uint8List bytes);

  /// Uploads the queue, fetches every image [noteTexts] link to that this
  /// device lacks, and evicts cached images no note links to.
  Future<void> reconcile(Iterable<String> noteTexts);

  /// Where to draw [ref] from.
  ImageSource sourceFor(ImageRef ref);

  /// Whether [ref] is still waiting to upload (always false when unknown).
  bool isPending(ImageRef ref);

  /// Login and queue summary.
  Future<ImageStoreStatus> status();
}

/// Every image ref across [noteTexts].
Set<ImageRef> imageRefsAcross(Iterable<String> noteTexts) => {
  for (final text in noteTexts) ...imageRefsIn(text),
};

/// The store used where none was provided (tests, and any screen built
/// outside the app root): attaching is refused, nothing is ever available.
class NoImageStore extends ImageStore {
  @override
  Future<ImageRef?> attach(String noteId, Uint8List bytes) async =>
      throw const ImageStoreException('Images are not available here');

  @override
  Future<void> reconcile(Iterable<String> noteTexts) async {}

  @override
  ImageSource sourceFor(ImageRef ref) => const MissingImageSource();

  @override
  bool isPending(ImageRef ref) => false;

  @override
  Future<ImageStoreStatus> status() async =>
      const ImageStoreStatus(configured: false, pending: 0);
}
