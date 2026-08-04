/// One place that decides *how* a sync runs, for every screen that
/// triggers one.
///
/// The capture screen syncs on a timer and on demand, the settings screen on a
/// button; before this they each built their own client, so a change to the
/// backend meant editing four call sites and hoping none was missed.
library;

import 'package:crdt_sync/crdt_sync.dart';
import 'package:http/http.dart' as http;
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/firebase_backend.dart';
import 'package:todo/sync/sync_service.dart';
import 'package:todo/sync/sync_settings.dart';
import 'package:todo/sync/sync_state_factory.dart';

/// Runs one sync, choosing the backend and carrying the revision cache.
///
/// Firebase is the primary when this device has been set up for it, with
/// GitHub kept as a mirror so a device that has not moved yet still
/// converges. Not being set up is a normal state, not an error — sync runs
/// over GitHub exactly as it did before.
///
/// [firebaseFactory] and [stateStore] exist for tests, which must not reach
/// the OS keystore or an application-support directory.
Future<SyncResult> runSync(
  NoteRepository repository,
  SyncSettings settings, {
  http.Client? httpClient,
  Future<FirebaseRestClient?> Function()? firebaseFactory,
  SyncStateStore? stateStore,
}) async {
  final github = GitHubClient(
    owner: settings.owner,
    repo: settings.repo,
    token: settings.token,
    httpClient: httpClient,
  );
  final factory = firebaseFactory ?? openFirebase;
  final firebase = await factory();
  try {
    final service = SyncService(
      // The production default resolves a real application-support directory
      // through path_provider, which has no binding under `flutter test`;
      // every test injects a store instead.
      // coverage:ignore-start
      stateStore: stateStore ?? await openSyncStateStore(),
      // coverage:ignore-end
    );
    return await service.sync(
      repository,
      firebase == null
          ? github
          : MirrorStore(primary: firebase, mirror: github),
    );
  } finally {
    // Close both: unlike the long-lived desktop callers, each screen builds
    // these per run.
    github.close();
    firebase?.close();
  }
}
