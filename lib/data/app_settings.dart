/// App-wide, non-sync preferences (currently just `advancedMode`).
///
/// Mirrors [SyncSettings]'s shape: `SharedPreferences` is the source of
/// truth for instant, offline reads; a Firebase mirror lets the same choice
/// follow the user to their other devices without blocking the UI on a
/// network round trip.
///
/// Unlike [SyncSettings], the remote calls here take an already-open
/// [FirebaseRestClient] rather than opening their own: `runSync()` in
/// `run_sync.dart` is the one place that owns a Firebase session per sync
/// pass, and reconciling this flag rides along on that same client instead
/// of paying for a second sign-in/token-refresh round trip.
library;

import 'package:crdt_sync/crdt_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the mirrored value lives in the shared `kuhy-syncs` RTDB project,
/// sibling to `changesets/<nodeId>.json`.
const String kAdvancedModeRemotePath = 'settings/advancedMode';

/// App-wide, non-sync preferences (currently just `advancedMode`).
class AppSettings {
  /// Creates an [AppSettings] from its stored fields.
  const AppSettings({required this.advancedMode, this.advancedModeUpdatedAt});

  /// Whether the priority/status/template/mode chrome and the routine
  /// save/sync status text are shown. Off by default: casual capture needs
  /// none of it. A sync *failure* is always surfaced regardless of this
  /// flag — that is the one state the user might need to act on.
  final bool advancedMode;

  /// When [advancedMode] was last changed, used to reconcile a value written
  /// on another device with the local one (most recent write wins). Null for
  /// a value that has never round-tripped through Firebase.
  final DateTime? advancedModeUpdatedAt;

  static const _kAdvancedMode = 'app.advancedMode';
  static const _kAdvancedModeUpdatedAt = 'app.advancedMode.updatedAt';

  /// Loads settings, defaulting `advancedMode` to false.
  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final updatedAtMillis = prefs.getInt(_kAdvancedModeUpdatedAt);
    return AppSettings(
      advancedMode: prefs.getBool(_kAdvancedMode) ?? false,
      advancedModeUpdatedAt: updatedAtMillis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(updatedAtMillis),
    );
  }

  /// Persists [value] locally (stamping [advancedModeUpdatedAt] to now so a
  /// later reconciliation can tell which write is newer) and, when [client]
  /// is a live Firebase session, best-effort mirrors it remotely. A push
  /// failure — network (`FirebaseSyncError`) or an expired/wrong-account
  /// session (`FirebaseAuthError`), both `RemoteSyncError` — is swallowed:
  /// the local write already succeeded, and the next successful sync will
  /// retry via [reconcileWithRemote].
  Future<AppSettings> withAdvancedMode({
    required bool value,
    FirebaseRestClient? client,
  }) async {
    final updatedAt = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAdvancedMode, value);
    await prefs.setInt(
      _kAdvancedModeUpdatedAt,
      updatedAt.millisecondsSinceEpoch,
    );
    final updated = AppSettings(
      advancedMode: value,
      advancedModeUpdatedAt: updatedAt,
    );
    if (client != null) {
      try {
        // getStringMap() only keeps entries whose JSON value is a string,
        // so both fields are written as strings rather than a bool/int.
        await client.patchValues(kAdvancedModeRemotePath, {
          'value': value.toString(),
          'updatedAtMillis': updatedAt.millisecondsSinceEpoch.toString(),
        });
      } on RemoteSyncError {
        // Offline, a transient failure, or an expired/wrong-account session:
        // the local write stands, and the next runSync() reconciliation will
        // push it again.
      }
    }
    return updated;
  }

  /// Pulls the remote value from [client] and, if it is newer than the
  /// local one, applies it locally and returns the reconciled settings.
  /// Returns this instance unchanged when [client] is null, there is
  /// nothing remote, the remote value is not newer, or the fetch fails with
  /// a [RemoteSyncError] — network, or an expired/wrong-account session
  /// (offline sync is a normal state, not an error).
  Future<AppSettings> reconcileWithRemote(FirebaseRestClient? client) async {
    if (client == null) return this;
    try {
      final remote = await client.getStringMap(kAdvancedModeRemotePath);
      if (!remote.containsKey('value')) return this;
      final remoteUpdatedMillis = int.tryParse(
        remote['updatedAtMillis'] ?? '',
      );
      if (remoteUpdatedMillis == null) return this;
      final remoteUpdatedAt = DateTime.fromMillisecondsSinceEpoch(
        remoteUpdatedMillis,
      );
      final candidate = AppSettings(
        advancedMode: remote['value'] == 'true',
        advancedModeUpdatedAt: remoteUpdatedAt,
      );
      final adopted = adopt(candidate);
      if (identical(adopted, this)) return this;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kAdvancedMode, adopted.advancedMode);
      await prefs.setInt(_kAdvancedModeUpdatedAt, remoteUpdatedMillis);
      return adopted;
    } on RemoteSyncError {
      return this;
    }
  }

  /// Returns [candidate] if it carries a strictly newer
  /// [advancedModeUpdatedAt] than this instance, otherwise returns this
  /// instance unchanged. Shared by every call site that reconciles a
  /// remote-or-otherwise-external value against the current in-memory
  /// settings (`reconcileWithRemote` above, and the capture/settings
  /// screens after a sync completes), so the "newer write wins" rule is
  /// defined once instead of copied at each call site.
  AppSettings adopt(AppSettings? candidate) {
    if (candidate == null) return this;
    final candidateAt = candidate.advancedModeUpdatedAt;
    if (candidateAt == null) return this;
    final currentAt = advancedModeUpdatedAt;
    if (currentAt != null && !candidateAt.isAfter(currentAt)) return this;
    return candidate;
  }
}
