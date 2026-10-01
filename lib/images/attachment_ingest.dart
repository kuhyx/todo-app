/// Turning an incoming file into a stored attachment: re-encoded as an image
/// when it is one, kept byte-for-byte otherwise.
///
/// The one place that decides, shared by the Android store and the desktop
/// wrapper. The file lands on disk first and is classified from there, so its
/// size never reaches memory: only something that sniffs as a photo format
/// (see `looksLikeImage`) and is at most [kMaxImageDecodeBytes] is read whole,
/// to be decoded. An image that fails to decode is kept as a file rather than
/// refused.
///
/// Pure Dart + `dart:io`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:todo/images/attachment_ref.dart';
import 'package:todo/images/image_cache_store.dart';
import 'package:todo/images/image_processing.dart';

/// Stores incoming files in [store], queued for upload.
class AttachmentIngest {
  /// Creates an ingest over [store]; [prepare] is injectable for tests.
  AttachmentIngest(
    this.store, {
    Future<Uint8List?> Function(Uint8List)? prepare,
  }) : _prepare = prepare ?? prepareImageInBackground;

  /// Where attachments are kept.
  final ImageCacheStore store;

  final Future<Uint8List?> Function(Uint8List) _prepare;

  /// Stores [data], the contents of a file called [name], for [noteId].
  Future<Attachment> fromStream(
    String noteId,
    String name,
    Stream<List<int>> data,
  ) async {
    final ref = AttachmentRef.forFile(noteId, name);
    final tmp = store.tempFor(ref);
    await tmp.parent.create(recursive: true);
    return await _guarded(tmp, () async {
      final sink = tmp.openWrite();
      try {
        await sink.addStream(data);
      } finally {
        await sink.close();
      }
      return await _settle(ref, name, tmp);
    });
  }

  /// Stores the local file [source], called [name], for [noteId].
  ///
  /// With [move] (a picker's private copy, nobody else's file) it is renamed
  /// into place, so a multi-gigabyte pick is never on disk twice; otherwise,
  /// or across filesystems, it is copied.
  Future<Attachment> fromFile(
    String noteId,
    String name,
    File source, {
    required bool move,
  }) async {
    if (!move) return await fromStream(noteId, name, source.openRead());
    final ref = AttachmentRef.forFile(noteId, name);
    final tmp = store.tempFor(ref);
    await tmp.parent.create(recursive: true);
    try {
      await source.rename(tmp.path);
    } on FileSystemException {
      final attachment = await fromStream(noteId, name, source.openRead());
      await source.delete();
      return attachment;
    }
    return await _guarded(tmp, () => _settle(ref, name, tmp));
  }

  /// Runs [body], removing [tmp] if it fails so a failed attach leaves
  /// nothing behind.
  Future<Attachment> _guarded(
    File tmp,
    Future<Attachment> Function() body,
  ) async {
    try {
      return await body();
    } on Object {
      if (tmp.existsSync()) await tmp.delete();
      rethrow;
    }
  }

  Future<Attachment> _settle(AttachmentRef ref, String name, File tmp) async {
    if (await tmp.length() <= kMaxImageDecodeBytes && await _sniff(tmp)) {
      final jpeg = await _prepare(await tmp.readAsBytes());
      if (jpeg != null) {
        final image = AttachmentRef.create(ref.noteId);
        await store.put(image, jpeg);
        await tmp.delete();
        return Attachment(ref: image, name: name, isImage: true);
      }
    }
    await store.adopt(ref, tmp);
    return Attachment(ref: ref, name: name, isImage: false);
  }

  Future<bool> _sniff(File file) async {
    final head = <int>[];
    await file.openRead(0, kImageSniffBytes).forEach(head.addAll);
    return looksLikeImage(head);
  }
}
