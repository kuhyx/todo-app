/// The on-device copy of every image a note links to, plus the upload queue.
///
/// One directory, `<root>/<noteId>/<uuid>.jpg`, mirrors dufs' `todo-images/`.
/// An image attached while offline gets a `<uuid>.jpg.pending` marker next to
/// it; the marker is the queue, so it survives restarts with no separate
/// bookkeeping, and it is only removed after dufs has accepted the upload.
///
/// Used as-is by the Android app and by the desktop wrapper (the web page
/// never talks to dufs). Pure Dart + `dart:io`.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:todo/images/dufs_image_client.dart';
import 'package:todo/images/image_ref.dart';

/// How long a cached, unreferenced image is kept before eviction.
///
/// Covers the gap between writing an image and its link reaching the note
/// store (and, on desktop, the page's next reconcile): without it a
/// reconcile landing in that gap would delete a fresh image.
const kEvictionGrace = Duration(minutes: 10);

/// Counts from one [ImageCacheStore.reconcile] pass.
class ReconcileReport {
  /// Creates a report.
  const ReconcileReport({
    this.uploaded = 0,
    this.downloaded = 0,
    this.evicted = 0,
    this.pending = 0,
    this.missing = 0,
  });

  /// Queued images dufs accepted this pass.
  final int uploaded;

  /// Linked images fetched from dufs this pass.
  final int downloaded;

  /// Unlinked cached images deleted.
  final int evicted;

  /// Images still waiting to upload after the pass.
  final int pending;

  /// Linked images still not on this device after the pass.
  final int missing;

  /// JSON form, for the wrapper's `/images/reconcile` response.
  Map<String, int> toJson() => {
    'uploaded': uploaded,
    'downloaded': downloaded,
    'evicted': evicted,
    'pending': pending,
    'missing': missing,
  };
}

/// Local image files and their upload queue under [root].
class ImageCacheStore {
  /// Creates a store rooted at [root]; [now] is injectable for tests.
  ImageCacheStore(this.root, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Directory holding `<noteId>/<uuid>.jpg`.
  final Directory root;

  final DateTime Function() _now;

  // Passes run one at a time. Calls arriving before the next pass starts
  // merge into it (see [reconcile]).
  Future<void> _tail = Future.value();
  Future<ReconcileReport>? _scheduled;
  _Pass? _scheduledPass;

  /// The cached file for [ref] (it may not exist).
  File fileFor(ImageRef ref) => File(p.join(root.path, ref.noteId, ref.file));

  File _marker(ImageRef ref) => File('${fileFor(ref).path}.pending');

  /// Whether [ref] is waiting to upload.
  bool isPending(ImageRef ref) => _marker(ref).existsSync();

  /// Stores [bytes] as [ref] and queues it for upload.
  Future<void> put(ImageRef ref, Uint8List bytes) async {
    final file = fileFor(ref);
    await file.parent.create(recursive: true);
    // Marker first: a crash between the two writes then leaves a marker with
    // no file (skipped by reconcile), never a file that silently never uploads.
    await _marker(ref).writeAsString('');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }

  /// Every image waiting to upload.
  List<ImageRef> pending() => [
    for (final marker in _files('.pending'))
      ?ImageRef.tryParse(_relative(marker).replaceFirst('.pending', '')),
  ];

  /// Uploads the queue, fetches linked images this device lacks, and evicts
  /// cached images nothing links to any more.
  ///
  /// Without a [client] (no password set yet) only eviction runs. Eviction is
  /// skipped entirely when [referenced] is empty — an empty set far more
  /// likely means "notes not loaded yet" than "every image unlinked" — and it
  /// never touches a queued image or one younger than [kEvictionGrace].
  ///
  /// Overlapping calls do not run in parallel: calls made before the next
  /// pass starts share it, with their refs unioned and the newest client.
  Future<ReconcileReport> reconcile(
    Set<ImageRef> referenced,
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
        if (await client.upload(ref, await file.readAsBytes())) {
          await _marker(ref).delete();
          uploaded++;
        }
      }
      for (final ref in pass.referenced) {
        if (fileFor(ref).existsSync()) continue;
        final bytes = await client.download(ref);
        if (bytes == null) continue;
        final file = fileFor(ref);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
        downloaded++;
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

  int _evict(Set<ImageRef> referenced) {
    final cutoff = _now().subtract(kEvictionGrace);
    var evicted = 0;
    for (final file in _files('.jpg')) {
      final ref = ImageRef.tryParse(_relative(file));
      if (ref == null || referenced.contains(ref) || isPending(ref)) continue;
      if (file.lastModifiedSync().isAfter(cutoff)) continue;
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

  final Set<ImageRef> referenced;
  final DufsImageClient? client;
}
