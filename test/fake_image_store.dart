/// An in-memory [ImageStore] for widget tests.
///
/// Deliberately NOT named `*_test.dart`: the runner would collect it.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/images/attachment_ref.dart';

/// Records attaches and reconciles; every image is "local" at a fake path
/// unless listed in [missing].
class FakeImageStore extends ImageStore {
  /// Bytes accepted per ref, in attach order.
  final Map<AttachmentRef, Uint8List> attached = {};

  /// Files accepted through [attachFile], in order.
  final List<XFile> attachedFiles = [];

  /// What [sizeOf] reports for an attachment on this device.
  int size = 2048;

  /// Note texts passed to each reconcile.
  final List<List<String>> reconciles = [];

  /// Refs reported as not on this device.
  final Set<AttachmentRef> missing = {};

  /// Refs reported as waiting to upload.
  final Set<AttachmentRef> pending = {};

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
  Future<AttachmentRef?> attach(String noteId, Uint8List bytes) async {
    await gate;
    final failure = this.failure;
    if (failure != null) throw failure;
    if (bytes.isNotEmpty && bytes.first == notImageMarker) return null;
    final ref = AttachmentRef.create(noteId);
    attached[ref] = bytes;
    return ref;
  }

  /// Files whose name ends in `.png` or `.jpg` come back as images.
  @override
  Future<Attachment> attachFile(String noteId, XFile file) async {
    await gate;
    final failure = this.failure;
    if (failure != null) throw failure;
    attachedFiles.add(file);
    final isImage = file.name.endsWith('.png') || file.name.endsWith('.jpg');
    return Attachment(
      ref: isImage
          ? AttachmentRef.create(noteId)
          : AttachmentRef.forFile(noteId, file.name),
      name: file.name,
      isImage: isImage,
    );
  }

  @override
  Future<int?> sizeOf(AttachmentRef ref) async =>
      missing.contains(ref) ? null : size;

  @override
  Future<void> reconcile(Iterable<String> noteTexts) async =>
      reconciles.add(noteTexts.toList());

  @override
  ImageSource sourceFor(AttachmentRef ref) {
    if (missing.contains(ref)) return const MissingImageSource();
    return network
        ? NetworkImageSource('http://localhost/images/$ref')
        : LocalImageSource(localPath);
  }

  @override
  bool isPending(AttachmentRef ref) => pending.contains(ref);

  @override
  Future<ImageStoreStatus> status() async =>
      ImageStoreStatus(configured: true, pending: pending.length);

  /// Lets a test fire a change notification.
  void changed() => notifyListeners();
}
