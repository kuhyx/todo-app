import 'package:crdt_sync/crdt_sync.dart';

import '../data/note_repository.dart';

/// Outcome of a sync run, for surfacing in the UI.
class SyncResult {
  const SyncResult({required this.mergedDevices, required this.pushed});

  /// How many other devices' logs were pulled and merged.
  final int mergedDevices;

  /// Whether this device pushed its own log.
  final bool pushed;

  @override
  String toString() =>
      'SyncResult(mergedDevices: $mergedDevices, pushed: $pushed)';
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
  const SyncService({this.notesDir = 'todo-sync/notes'});

  /// Directory in the repo under which per-device note-log files live.
  final String notesDir;

  /// Runs a full pull-merge-push cycle. Safe to call repeatedly.
  Future<SyncResult> sync(NoteRepository repo, GitHubClient github) async {
    final nodeId = repo.nodeId;
    final ownFileName = '$nodeId.json';

    // 1. Pull: list all device log files, merge everyone else's.
    final names = await github.listDirectory(notesDir);
    var merged = 0;
    for (final name in names) {
      if (name == ownFileName) continue; // our own file; skip it.
      final text = await github.getFileText('$notesDir/$name');
      if (text == null) continue;
      final remote = _decodeLog(text);
      if (remote == null) continue; // Skip a corrupt/foreign file.
      await repo.importLog(remote);
      merged++;
    }

    // 2. Push: upload our own (now-merged) log under our node id.
    // putFileText resolves our file's current sha itself.
    await github.putFileText(
      '$notesDir/$ownFileName',
      logToJson(repo.exportLog()),
      message: 'sync: $nodeId @ ${DateTime.now().toUtc().toIso8601String()}',
    );

    return SyncResult(mergedDevices: merged, pushed: true);
  }

  /// Parses a remote note log, returning `null` for a corrupt or wrong-shape
  /// payload so one bad device file never aborts the whole sync.
  Log? _decodeLog(String text) {
    try {
      return logFromJson(text);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
