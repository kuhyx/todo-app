import 'package:crdt_sync/crdt_sync.dart';

import 'package:todo/data/note_repository.dart';

/// Outcome of a sync run, for surfacing in the UI.
class SyncResult {
  /// Creates a [SyncResult] from a completed sync run's outcome.
  const SyncResult({
    required this.mergedDevices,
    required this.pushed,
    this.skippedFiles = const [],
    this.skippedUnchanged = 0,
    this.firebaseConnected = false,
  });

  /// How many other devices' logs were pulled and merged.
  final int mergedDevices;

  /// Whether this device pushed its own log.
  final bool pushed;

  /// Whether this run's primary backend was Firebase, rather than GitHub
  /// alone. Set by the caller ([runSync]), which is the only layer that
  /// knows which [RemoteStore] it built -- [SyncService] itself is
  /// deliberately agnostic to what [RemoteStore] it was handed.
  ///
  /// Exists so the status line can say so: reporting a plain "Synced" while
  /// this is false is what made a desktop stuck on GitHub-only look
  /// identical to one actually reaching Firebase, on a device that had in
  /// fact never connected.
  final bool firebaseConnected;

  /// Peer files that were listed but could not be fetched or decoded
  /// (vanished, corrupt, or foreign format) and were left out of the merge.
  /// Surfaced so a device silently dropping out of sync is visible.
  final List<String> skippedFiles;

  /// Peers whose logs were skipped because their revision was unchanged.
  ///
  /// Distinct from [skippedFiles]: this is the optimisation working, not a
  /// device dropping out.
  final int skippedUnchanged;

  /// Returns a copy with [firebaseConnected] set. [SyncService] never sets
  /// it -- only [runSync], which is the layer that knows which [RemoteStore]
  /// it built -- so this is the seam that lets it do that without
  /// [SyncService] taking on knowledge of Firebase at all.
  SyncResult withFirebaseConnected({required bool value}) => SyncResult(
    mergedDevices: mergedDevices,
    pushed: pushed,
    skippedFiles: skippedFiles,
    skippedUnchanged: skippedUnchanged,
    firebaseConnected: value,
  );

  @override
  String toString() =>
      'SyncResult(mergedDevices: $mergedDevices, pushed: $pushed, '
      'firebaseConnected: $firebaseConnected, skippedFiles: $skippedFiles)';
}

/// Synchronises a [NoteRepository] with a GitHub repo used as dumb storage.
///
/// Design: each device owns exactly one file, `todo-sync/notes/<nodeId>.json`,
/// holding its full crdt_sync note [Log]. Because no two devices ever write the
/// same file, there are **no git-level merge conflicts**; convergence is the
/// CRDT layer's job — pulling every other device's log and [NoteRepository]
/// merging it via `mergeLogs` is commutative and idempotent, so repeated syncs
/// in any order converge to the same state.
///
/// The directory is `notes/` (not the legacy `changesets/`): the on-the-wire
/// format changed from a `sqlite_crdt` changeset to a crdt_sync `Log`, so the
/// two never share a path and an old client can't misread a new file.
class SyncService {
  /// Creates a [SyncService], optionally overriding [notesDir].
  const SyncService({this.notesDir = 'todo-sync/notes', this.stateStore});

  /// Directory in the repo under which per-device note-log files live.
  final String notesDir;

  /// Remembers each peer's last-seen revision between runs.
  ///
  /// Without one, every sync downloads every peer's whole log — four files of
  /// roughly 150 KB here — whether or not anything changed. With one, an
  /// unchanged peer costs nothing beyond the shared revision map, which is
  /// what keeps this inside the Firebase free tier's monthly budget.
  final SyncStateStore? stateStore;

  /// Where revisions live, as a sibling of [notesDir].
  String get revsDir => defaultRevsPath(notesDir);

  /// Runs a full pull-merge-push cycle. Safe to call repeatedly.
  ///
  /// [remote] is any [RemoteStore]: GitHub alone before the cutover, or a
  /// [MirrorStore] with Firebase primary during it. Swapping backends is a
  /// change at the call site and nothing more.
  Future<SyncResult> sync(NoteRepository repo, RemoteStore remote) async {
    final nodeId = repo.nodeId;
    final ownFileName = '$nodeId.json';

    final state = await stateStore?.load() ?? const SyncState();
    final remoteRevs = stateStore == null
        ? const <String, String>{}
        : await _revisions(remote);
    final seenRevs = <String, String>{};

    // 1. Pull: list all device log files, merge everyone else's.
    final names = await remote.listDirectory(notesDir);
    var merged = 0;
    var skippedUnchanged = 0;
    final skipped = <String>[];
    for (final name in names) {
      if (name == ownFileName) continue; // our own file; skip it.
      final peer = name.endsWith('.json')
          ? name.substring(0, name.length - 5)
          : name;
      final remoteRev = remoteRevs[peer];
      if (remoteRev != null && remoteRev == state.peerRevs[peer]) {
        // Unchanged since we last merged it, and that merge is already in the
        // local log — so the ~150 KB download is pure waste. Carry the
        // revision forward so it stays skipped next time.
        seenRevs[peer] = remoteRev;
        skippedUnchanged++;
        continue;
      }
      final text = await remote.getFileText('$notesDir/$name');
      final remoteLog = text == null ? null : _decodeLog(text);
      if (remoteLog == null) {
        // A vanished or undecodable peer file must not abort the sync, but
        // it must not vanish silently either — that's how a device drops
        // out of sync unnoticed. Report it in the result instead.
        // Deliberately not recorded as seen: a corrupt push must be retried
        // next run, not remembered as merged.
        skipped.add(name);
        continue;
      }
      await repo.importLog(remoteLog);
      seenRevs[peer] = remoteRev ?? revisionOf(text!);
      merged++;
    }

    // 2. Push: upload our own (now-merged) log under our node id.
    // putFileText resolves our file's current sha itself.
    final encoded = logToJson(repo.exportLog());
    final revision = revisionOf(encoded);
    final unchanged = stateStore != null && revision == state.pushedRev;
    if (!unchanged) {
      await remote.putFileText(
        '$notesDir/$ownFileName',
        encoded,
        message: 'sync: $nodeId @ ${DateTime.now().toUtc().toIso8601String()}',
      );
      // Published after the log, never before: a peer that cached "seen rev X"
      // against a log it never received would skip it forever.
      if (stateStore != null) {
        await remote.putFileText(
          '$revsDir/$nodeId',
          revision,
          message: 'sync: revision $nodeId',
        );
      }
    }

    if (stateStore != null) {
      await stateStore!.save(
        SyncState(pushedRev: revision, peerRevs: seenRevs),
      );
    }

    return SyncResult(
      mergedDevices: merged,
      pushed: !unchanged,
      skippedFiles: skipped,
      skippedUnchanged: skippedUnchanged,
    );
  }

  /// Reads every peer's published revision in one request where possible.
  ///
  /// Degrades to an empty map — meaning "fetch everything", the old
  /// behaviour — on a backend without a bulk-map read, so correctness never
  /// depends on the optimisation being available.
  Future<Map<String, String>> _revisions(RemoteStore remote) async {
    if (remote is! BulkMapReader) return const {};
    return (remote as BulkMapReader).getStringMap(revsDir);
  }

  /// Parses a remote note log, returning `null` for a corrupt or wrong-shape
  /// payload so one bad device file never aborts the whole sync.
  Log? _decodeLog(String text) {
    try {
      return logFromJson(text);
    } on FormatException {
      return null;
    }
    // crdt_sync's logFromJson throws a raw TypeError (not a custom
    // exception) for a wrong-shape JSON payload from an untrusted peer
    // file; must be caught too so one bad device file never aborts the
    // whole sync (see doc comment above).
    // ignore: avoid_catching_errors
    on TypeError {
      return null;
    }
  }
}
