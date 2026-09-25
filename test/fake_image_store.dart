/// An in-memory [ImageStore] for widget tests.
///
/// Deliberately NOT named `*_test.dart`: the runner would collect it.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/images/image_ref.dart';

/// Records attaches and reconciles; every image is "local" at a fake path
/// unless listed in [missing].
class FakeImageStore extends ImageStore {
  /// Bytes accepted per ref, in attach order.
  final Map<ImageRef, Uint8List> attached = {};

  /// Note texts passed to each reconcile.
  final List<List<String>> reconciles = [];

  /// Refs reported as not on this device.
  final Set<ImageRef> missing = {};

  /// Refs reported as waiting to upload.
  final Set<ImageRef> pending = {};

  /// Inputs whose first byte is this are "not an image".
  int notImageMarker = 0;

  /// When set, attach throws this.
  ImageStoreException? failure;

  /// Where local images appear to live, e.g. a real temp file.
  String localPath = '/nonexistent/image.jpg';

  /// Returns [NetworkImageSource]s instead of local ones.
  bool network = false;

  /// When set, attach waits for it first (to act mid-attach).
  Future<void>? gate;

  @override
  Future<ImageRef?> attach(String noteId, Uint8List bytes) async {
    await gate;
    final failure = this.failure;
    if (failure != null) throw failure;
    if (bytes.isNotEmpty && bytes.first == notImageMarker) return null;
    final ref = ImageRef.create(noteId);
    attached[ref] = bytes;
    return ref;
  }

  @override
  Future<void> reconcile(Iterable<String> noteTexts) async =>
      reconciles.add(noteTexts.toList());

  @override
  ImageSource sourceFor(ImageRef ref) {
    if (missing.contains(ref)) return const MissingImageSource();
    return network
        ? NetworkImageSource('http://localhost/images/$ref')
        : LocalImageSource(localPath);
  }

  @override
  bool isPending(ImageRef ref) => pending.contains(ref);

  @override
  Future<ImageStoreStatus> status() async =>
      ImageStoreStatus(configured: true, pending: pending.length);

  /// Lets a test fire a change notification.
  void changed() => notifyListeners();
}
