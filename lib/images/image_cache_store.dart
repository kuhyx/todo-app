/// The on-device copy of every attachment a note links to, plus the upload
/// queue.
///
/// One directory, `<root>/<noteId>/<uuid>.<ext>`, mirrors dufs'
/// `todo-images/`. An attachment added while offline gets a
/// `<uuid>.<ext>.pending` marker next to it; the marker is the queue, so it
/// survives restarts with no separate bookkeeping, and it is only removed
/// after dufs has accepted the upload.
///
/// Files are never held in memory whole: uploads stream from disk and
/// downloads stream to a `.tmp` beside the target, renamed only once complete,
/// so an interrupted download cannot leave a truncated file that looks done.
///
/// Used as-is by the Android app and by the desktop wrapper (the web page
/// never talks to dufs). Pure Dart + `dart:io`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:todo/images/attachment_ref.dart';
import 'package:todo/images/dufs_image_client.dart';
import 'package:todo/images/reconcile_report.dart';

export 'package:todo/images/reconcile_report.dart';

/// How long a cached, unreferenced attachment is kept before eviction, and
/// how old an abandoned `.tmp` must be before it is swept.
///
/// Covers the gap between writing an attachment and its link reaching the
/// note store (and, on desktop, the page's next reconcile): without it a
/// reconcile landing in that gap would delete a fresh attachment.
const kEvictionGrace = Duration(minutes: 10);

/// Local attachment files and their upload queue under [root].
class ImageCacheStore {
  /// Creates a store rooted at [root]; [now] is injectable for tests.
  ImageCacheStore(this.root, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Directory holding `<noteId>/<uuid>.<ext>`.
  final Directory root;

  final DateTime Function() _now;

  // Passes run one at a time. Calls arriving before the next pass starts
  // merge into it (see [reconcile]).
  Future<void> _tail = Future.value();
  Future<ReconcileReport>? _scheduled;
  _Pass? _scheduledPass;

  /// The cached file for [ref] (it may not exist).
  File fileFor(AttachmentRef ref) =>
      File(p.join(root.path, ref.noteId, ref.file));

  /// Scratch file next to [ref]'s, for writes that must land whole.
  File tempFor(AttachmentRef ref) => File('${fileFor(ref).path}.tmp');

  File _marker(AttachmentRef ref) => File('${fileFor(ref).path}.pending');

  /// Whether [ref] is waiting to upload.
  bool isPending(AttachmentRef ref) => _marker(ref).existsSync();

  /// Stores [bytes] as [ref] and queues it for upload.
  Future<void> put(AttachmentRef ref, Uint8List bytes) async {
    final tmp = tempFor(ref);
    await tmp.parent.create(recursive: true);
    await tmp.writeAsBytes(bytes, flush: true);
    await adopt(ref, tmp);
  }

  /// Moves the complete file [tmp] into place as [ref] and queues it for
  /// upload. [tmp] must be on the same filesystem (see [tempFor]).
  Future<void> adopt(AttachmentRef ref, File tmp) async {
    await fileFor(ref).parent.create(recursive: true);
    // Marker first: a crash between the two then leaves a marker with no
    // file (skipped by reconcile), never a file that silently never uploads.
    await _marker(ref).writeAsString('');
    await tmp.rename(fileFor(ref).path);
  }

  /// Every attachment waiting to upload.
  List<AttachmentRef> pending() => [
    for (final marker in _files('.pending'))
      ?AttachmentRef.tryParse(_relative(marker).replaceFirst('.pending', '')),
  ];

  /// Uploads the queue, fetches linked attachments this device lacks, and
  /// evicts cached ones nothing links to any more.
  ///
  /// Without a [client] (no password set yet) only eviction runs. Eviction is
  /// skipped entirely when [referenced] is empty — an empty set far more
  /// likely means "notes not loaded yet" than "everything unlinked" — and it
  /// never touches a queued attachment or one younger than [kEvictionGrace].
  ///
  /// Overlapping calls do not run in parallel: calls made before the next
  /// pass starts share it, with their refs unioned and the newest client.
  Future<ReconcileReport> reconcile(
    Set<AttachmentRef> referenced,
    DufsImageClient? client,
  ) {
    // Merge into a pass that has not started yet: union the refs (an
    // upload-only call right after an attach must not wipe a full pass's
    // refs) and keep the newest client.
    final waiting = _scheduledPass;
    _scheduledPass = waiting == null
        ? _Pass(referenced, client)
        : _Pass({
            ...waiting.referenced,
            ...referenced,
          }, client ?? waiting.client);
    final scheduled = _scheduled;
    if (scheduled != null) return scheduled;
    final future = _tail.then((_) {
      final pass = _scheduledPass!;
      _scheduledPass = null;
      _scheduled = null;
      return _run(pass);
    });
    _scheduled = future;
    _tail = future.then<void>((_) {}, onError: (Object _) {});
    return future;
  }

  Future<ReconcileReport> _run(_Pass pass) async {
    var uploaded = 0;
    var downloaded = 0;
    final client = pass.client;
    if (client != null) {
      for (final ref in pending()) {
        final file = fileFor(ref);
        if (!file.existsSync()) continue;
        final length = await file.length();
        if (await client.upload(ref, file.openRead(), length)) {
          await _marker(ref).delete();
          uploaded++;
        }
      }
      for (final ref in pass.referenced) {
        if (fileFor(ref).existsSync()) continue;
        if (await _download(ref, client)) downloaded++;
      }
    }
    final evicted = pass.referenced.isEmpty ? 0 : _evict(pass.referenced);
    return ReconcileReport(
      uploaded: uploaded,
      downloaded: downloaded,
      evicted: evicted,
      pending: pending().length,
      missing: pass.referenced.where((r) => !fileFor(r).existsSync()).length,
    );
  }

  Future<bool> _download(AttachmentRef ref, DufsImageClient client) async {
    final body = await client.openDownload(ref);
    if (body == null) return false;
    final tmp = tempFor(ref);
    try {
      await tmp.parent.create(recursive: true);
      final sink = tmp.openWrite();
      try {
        await sink.addStream(body);
      } finally {
        await sink.close();
      }
      await tmp.rename(fileFor(ref).path);
      return true;
    } on Exception {
      // A dropped connection mid-body: retry from scratch next pass.
      if (tmp.existsSync()) await tmp.delete();
      return false;
    }
  }

  int _evict(Set<AttachmentRef> referenced) {
    final cutoff = _now().subtract(kEvictionGrace);
    var evicted = 0;
    for (final file in _files('')) {
      if (file.lastModifiedSync().isAfter(cutoff)) continue;
      // An abandoned write (killed mid-download or mid-attach): unreachable
      // by any ref, and possibly gigabytes.
      if (file.path.endsWith('.tmp')) {
        file.deleteSync();
        continue;
      }
      final ref = AttachmentRef.tryParse(_relative(file));
      if (ref == null || referenced.contains(ref) || isPending(ref)) continue;
      file.deleteSync();
      evicted++;
    }
    return evicted;
  }

  List<File> _files(String suffix) {
    if (!root.existsSync()) return const [];
    return [
      for (final entity in root.listSync(recursive: true))
        if (entity is File && entity.path.endsWith(suffix)) entity,
    ];
  }

  String _relative(File file) =>
      p.split(p.relative(file.path, from: root.path)).join('/');
}

class _Pass {
  const _Pass(this.referenced, this.client);

  final Set<AttachmentRef> referenced;
  final DufsImageClient? client;
}
