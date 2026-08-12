/// One place that decides *how* a sync runs, for every screen that
/// triggers one.
///
/// The capture screen syncs on a timer and on demand, the settings screen on a
/// button; before this they each built their own client, so a change to the
/// backend meant editing four call sites and hoping none was missed.
library;

import 'package:crdt_sync/crdt_sync.dart';
import 'package:http/http.dart' as http;
import 'package:todo/analytics/analytics_service.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/firebase_backend.dart';
import 'package:todo/sync/sync_service.dart';
import 'package:todo/sync/sync_settings.dart';
import 'package:todo/sync/sync_state_factory.dart';

/// Bundles a [SyncResult] with the [AppSettings] as reconciled against the
/// same Firebase session — so a settings change made on another device is
/// picked up without a second authenticated round trip.
class SyncRunResult {
  /// Creates a [SyncRunResult] from a completed run's outcomes.
  const SyncRunResult({required this.syncResult, this.appSettings});

  /// Outcome of the note sync itself.
  final SyncResult syncResult;

  /// [AppSettings] after reconciling with the remote mirror, or null when
  /// the caller did not pass one in to reconcile.
  final AppSettings? appSettings;
}

/// Runs one sync, choosing the backend and carrying the revision cache.
///
/// Firebase is the primary when this device has been set up for it, with
/// GitHub kept as a mirror so a device that has not moved yet still
/// converges. Not being set up is a normal state, not an error — sync runs
/// over GitHub exactly as it did before.
///
/// [appSettings] and [analytics], when given, are reconciled/flushed
/// against the Firebase mirror using this same call's already-open client —
/// riding along on the one authenticated session this function opens,
/// rather than each concern (notes, settings, analytics) opening and
/// closing its own.
///
/// [firebaseFactory] and [stateStore] exist for tests, which must not reach
/// the OS keystore or an application-support directory.
Future<SyncRunResult> runSync(
  NoteRepository repository,
  SyncSettings settings, {
  AppSettings? appSettings,
  AnalyticsService? analytics,
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
    final result = await service.sync(
      repository,
      firebase == null
          ? github
          : MirrorStore(primary: firebase, mirror: github),
    );
    await analytics?.flush(firebase);
    return SyncRunResult(
      syncResult: result.withFirebaseConnected(value: firebase != null),
      appSettings: await appSettings?.reconcileWithRemote(firebase),
    );
  } finally {
    // Close both: unlike the long-lived desktop callers, each screen builds
    // these per run.
    github.close();
    firebase?.close();
  }
}
