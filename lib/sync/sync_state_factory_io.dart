import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:crdt_sync/crdt_sync_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// File holding the revision cache, beside the note log it describes.
const kSyncStateFileName = 'sync_state.json';

/// Opens the revision cache on a `dart:io` platform (Android).
// coverage:ignore-start
// Resolves the real per-platform application-support directory, so it cannot
// run under test; [openSyncStateStoreIn] holds the logic and is covered.
Future<SyncStateStore> openSyncStateStore() async {
  final dir = await getApplicationSupportDirectory();
  return openSyncStateStoreIn(dir.path);
}
// coverage:ignore-end

/// Opens the revision cache rooted at [dirPath].
///
/// Lives next to the log it describes and must be cleared with it: skipping
/// an unchanged peer is only sound because that peer's records are already
/// merged into the local log, so state that outlived its log would skip peers
/// whose data had been lost.
SyncStateStore openSyncStateStoreIn(String dirPath) => PersistedSyncStateStore(
  FileLogPersistence(File(p.join(dirPath, kSyncStateFileName))),
);
