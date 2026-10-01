/// What the UI asks of attachments (images and any other file),
/// independent of platform.
///
/// Android keeps attachments itself (an `ImageCacheStore` in app storage,
/// talking to dufs directly); the desktop web page delegates everything to
/// the local wrapper's `/images/*` routes. Both implement [ImageStore],
/// picked by the conditional export in `image_store.dart`.
library;

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/foundation.dart';

import 'package:todo/images/attachment_links.dart';
import 'package:todo/images/attachment_ref.dart';

export 'package:file_selector/file_selector.dart' show XFile;

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

/// Stores, shows and syncs the attachments notes link to. Notifies when one
/// becomes available or changes state, so embeds can redraw.
abstract class ImageStore extends ChangeNotifier {
  /// Stores [bytes] (any image format) for [noteId] and queues the upload.
  ///
  /// Returns the new ref, or null when [bytes] is not an image. Throws
  /// [ImageStoreException] when it cannot be stored.
  Future<AttachmentRef?> attach(String noteId, Uint8List bytes);

  /// Stores the picked or dropped [file] for [noteId] — re-encoded when it is
  /// an image, byte-for-byte otherwise, whatever its size — and queues the
  /// upload. Throws [ImageStoreException] when it cannot be stored.
  Future<Attachment> attachFile(String noteId, XFile file);

  /// Uploads the queue, fetches every attachment [noteTexts] link to that
  /// this device lacks, and evicts cached ones no note links to.
  Future<void> reconcile(Iterable<String> noteTexts);

  /// Where to draw [ref] from.
  ImageSource sourceFor(AttachmentRef ref);

  /// Whether [ref] is still waiting to upload (always false when unknown).
  bool isPending(AttachmentRef ref);

  /// Size in bytes of [ref] on this device, or null when it is not here yet.
  Future<int?> sizeOf(AttachmentRef ref);

  /// Login and queue summary.
  Future<ImageStoreStatus> status();
}

/// Every attachment ref across [noteTexts].
Set<AttachmentRef> attachmentRefsAcross(Iterable<String> noteTexts) => {
  for (final text in noteTexts) ...attachmentRefsIn(text),
};

/// The store used where none was provided (tests, and any screen built
/// outside the app root): attaching is refused, nothing is ever available.
class NoImageStore extends ImageStore {
  @override
  Future<AttachmentRef?> attach(String noteId, Uint8List bytes) async =>
      throw const ImageStoreException('Images are not available here');

  @override
  Future<Attachment> attachFile(String noteId, XFile file) async =>
      throw const ImageStoreException('Attachments are not available here');

  @override
  Future<void> reconcile(Iterable<String> noteTexts) async {}

  @override
  ImageSource sourceFor(AttachmentRef ref) => const MissingImageSource();

  @override
  bool isPending(AttachmentRef ref) => false;

  @override
  Future<int?> sizeOf(AttachmentRef ref) async => null;

  @override
  Future<ImageStoreStatus> status() async =>
      const ImageStoreStatus(configured: false, pending: 0);
}
