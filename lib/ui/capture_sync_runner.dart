/// Runs a sync pass for the capture screen and reports its outcome.
///
/// Split out of `capture_screen.dart` for file size, and it de-duplicates the
/// two callers at the same time: the manual button and the background tick
/// ran byte-identical `runSync` blocks that differed only in whether they
/// show a snackbar and what they log.
///
/// Deliberately has no `BuildContext` and no `setState`: the screen decides
/// what to show, this decides what to do.
library;

import 'package:crdt_sync/crdt_sync.dart';
import 'package:http/http.dart' as http;

import 'package:todo/analytics/analytics_service.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/run_sync.dart';
import 'package:todo/sync/sync_settings.dart';
import 'package:todo/ui/capture_status.dart';

/// What a sync attempt did, in the terms the capture screen cares about.
class CaptureSyncOutcome {
  /// Creates an outcome.
  const CaptureSyncOutcome({
    required this.ok,
    required this.detail,
    this.reconciled,
  });

  /// Whether the pass completed without throwing.
  final bool ok;

  /// One-line summary: merged/skipped counts on success, the error otherwise.
  final String detail;

  /// Settings reconciled during the pass, when the pass succeeded.
  final AppSettings? reconciled;
}

/// Runs sync passes against one repository and settings pair.
class CaptureSyncRunner {
  /// Creates a runner over the screen's injected dependencies.
  const CaptureSyncRunner({
    required this.repository,
    required this.status,
    this.analytics,
    this.httpClient,
    this.firebaseFactory,
    this.stateStore,
  });

  /// The store being synced.
  final NoteRepository repository;

  /// Where the outcome is recorded and persisted.
  final SyncStatusStore status;

  /// Optional analytics sink, passed straight through to [runSync].
  final AnalyticsService? analytics;

  /// Injected HTTP client, so tests run the real path without network.
  final http.Client? httpClient;

  /// Injected Firebase client factory, for the same reason.
  final Future<FirebaseRestClient?> Function()? firebaseFactory;

  /// Injected sync-state store.
  final SyncStateStore? stateStore;

  /// Runs one pass and records the outcome.
  ///
  /// [live] is the screen's `mounted` at the moment of recording -- the pass
  /// still finishes and still persists its outcome after the screen is gone,
  /// it just must not write the notifier.
  Future<CaptureSyncOutcome> run({
    required SyncSettings settings,
    required AppSettings appSettings,
    required bool Function() live,
  }) async {
    try {
      final result = await runSync(
        repository,
        settings,
        appSettings: appSettings,
        analytics: analytics,
        httpClient: httpClient,
        firebaseFactory: firebaseFactory,
        stateStore: stateStore,
      );
      final detail = describeSyncResult(result.syncResult);
      await status.record(ok: true, detail: detail, live: live());
      return CaptureSyncOutcome(
        ok: true,
        detail: detail,
        reconciled: result.appSettings,
      );
    } on Exception catch (e) {
      await status.record(ok: false, detail: '$e', live: live());
      return CaptureSyncOutcome(ok: false, detail: '$e');
    }
  }
}
