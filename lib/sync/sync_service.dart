import 'dart:convert';

import 'package:sqlite_crdt/sqlite_crdt.dart';

import '../data/note_repository.dart';
import 'github_client.dart';

/// Outcome of a sync run, for surfacing in the UI.
class SyncResult {
  const SyncResult({
    required this.mergedDevices,
    required this.pushed,
  });

  /// How many other devices' changesets were pulled and merged.
  final int mergedDevices;

  /// Whether this device pushed its own changeset.
  final bool pushed;

  @override
  String toString() =>
      'SyncResult(mergedDevices: $mergedDevices, pushed: $pushed)';
}

/// Synchronises a [NoteRepository] with a GitHub repo used as dumb storage.
///
/// Design: each device owns exactly one file, `changesets/<nodeId>.json`,
/// holding its full CRDT changeset. Because no two devices ever write the
/// same file, there are **no git-level merge conflicts**. Data convergence
/// is handled entirely by the CRDT layer: pulling every other device's
/// changeset and [NoteRepository.merge]-ing it is commutative and
/// idempotent, so repeated syncs in any order converge to the same state.
class SyncService {
  const SyncService({this.changesetDir = 'changesets'});

  /// Directory in the repo under which per-device changeset files live.
  final String changesetDir;

  /// Runs a full pull-merge-push cycle. Safe to call repeatedly.
  Future<SyncResult> sync(NoteRepository repo, GitHubClient github) async {
    final nodeId = repo.nodeId;
    final ownFileName = '$nodeId.json';

    // 1. Pull: list all device changeset files, merge everyone else's.
    final files = await github.listDirectory(changesetDir);
    var merged = 0;
    String? ownSha;
    for (final file in files) {
      if (file.name == ownFileName) {
        ownSha = file.sha; // Remember our file's SHA so we can update it.
        continue;
      }
      final text = await github.getFileText(file.path);
      if (text == null) continue;
      await repo.merge(_decodeChangeset(text));
      merged++;
    }

    // 2. Push: upload our own (now-merged) changeset under our node id.
    final changeset = await repo.getChangeset();
    await github.putFileText(
      '$changesetDir/$ownFileName',
      _encodeChangeset(changeset),
      sha: ownSha,
      message: 'sync: $nodeId @ ${DateTime.now().toUtc().toIso8601String()}',
    );

    return SyncResult(mergedDevices: merged, pushed: true);
  }

  /// Serialises a changeset to pretty JSON. All values are already
  /// primitives (hlc/modified are stored as TEXT), so no custom encoding
  /// is needed.
  String _encodeChangeset(CrdtChangeset changeset) =>
      const JsonEncoder.withIndent('  ').convert(changeset);

  /// Parses a JSON changeset back into the typed shape that
  /// [NoteRepository.merge] expects.
  ///
  /// The `hlc` field must be revived from its string form into an [Hlc]
  /// object, because `validateChangeset` casts it directly to [Hlc].
  CrdtChangeset _decodeChangeset(String text) {
    final raw = jsonDecode(text) as Map<String, dynamic>;
    return raw.map(
      (table, records) => MapEntry(
        table,
        (records as List).map((r) {
          final record = (r as Map).cast<String, Object?>();
          record['hlc'] = Hlc.parse(record['hlc'] as String);
          return record;
        }).toList(),
      ),
    );
  }
}
