/// Interaction-only usage analytics: what was tapped, selected, opened, for
/// how long — never note text or other free-form input.
///
/// Buffered in `SharedPreferences` (a JSON-encoded list, capped so a device
/// that never reaches Firebase can't grow it without bound) and flushed to
/// the shared `kuhy-syncs` Firebase RTDB project during the same sync pass
/// that already opens an authenticated client for notes and settings — see
/// `run_sync.dart`.
///
/// `SharedPreferences` rather than a new on-disk file or a new table in the
/// notes CRDT database: the desktop build has no filesystem (see
/// `local_backup_factory_web.dart`, which routes through the local wrapper
/// server for that reason), and a schema migration on the notes database
/// carries blast radius onto live user data for a feature that is allowed to
/// be lossy. `SharedPreferences` is already trusted for the sync-status
/// fields in `capture_screen.dart`.
library;

import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/analytics/analytics_event.dart';

/// Where a flushed batch lands in the shared RTDB project, sibling to
/// `changesets/<nodeId>.json` and `settings/advancedMode`.
String analyticsRemotePath(String nodeId, String batchId) =>
    'analytics/$nodeId/$batchId';

/// Buffers and flushes [AnalyticsEvent]s.
class AnalyticsService {
  /// Creates an [AnalyticsService] for the device identified by [nodeId].
  const AnalyticsService({required this.nodeId});

  /// This device's id, matching the one `SyncService` uses for its own
  /// changeset file — so a batch's origin is traceable without carrying any
  /// user-identifying data beyond what already syncs.
  final String nodeId;

  static const _kBuffer = 'analytics.buffer';

  /// Buffer cap: a device that never reaches Firebase must not grow this
  /// list without bound (`SharedPreferences` loads synchronously into memory
  /// at startup on Android). Oldest events are dropped first — analytics is
  /// lossy by nature, and a stalled flush must never slow app launch.
  static const maxBufferedEvents = 500;

  /// Appends [event] to the local buffer, dropping the oldest event first
  /// if already at [maxBufferedEvents].
  Future<void> logEvent(AnalyticsEvent event) async {
    final prefs = await SharedPreferences.getInstance();
    final buffered = _readBuffer(prefs)..add(event);
    final trimmed = buffered.length > maxBufferedEvents
        ? buffered.sublist(buffered.length - maxBufferedEvents)
        : buffered;
    await _writeBuffer(prefs, trimmed);
  }

  /// Flushes the current buffer to [client] as one batch.
  ///
  /// Claims the buffer (clears it locally) before the network call, rather
  /// than sending then subtracting by count: subtracting assumes the buffer
  /// only ever grows during the push, which [logEvent]'s cap-eviction breaks
  /// (it can trim from the *front*), so a mid-flush event could be counted
  /// as already sent and silently dropped. Claim-then-restore has a simpler
  /// failure mode instead: an event logged mid-flush lands in a buffer this
  /// call no longer owns and survives untouched; a failed push puts the
  /// claimed batch back in front of it, in original order.
  ///
  /// A push failure (offline, not signed in, expired session) leaves the
  /// buffer as if nothing happened; the next `runSync()` pass retries.
  /// Never throws.
  Future<void> flush(FirebaseRestClient? client) async {
    if (client == null) return;
    final prefs = await SharedPreferences.getInstance();
    final pending = _readBuffer(prefs);
    if (pending.isEmpty) return;
    await _writeBuffer(prefs, const []);
    final batchId = DateTime.now().toUtc().millisecondsSinceEpoch.toString();
    try {
      await client.putFileText(
        analyticsRemotePath(nodeId, batchId),
        jsonEncode([for (final e in pending) e.toJson()]),
        message: 'crdt_sync: analytics batch',
      );
    } on RemoteSyncError {
      // Catches FirebaseSyncError (network) and FirebaseAuthError (session
      // expired) alike — both are RemoteSyncError, and only catching the
      // narrower sibling type used to let an auth failure escape and turn
      // an otherwise-successful sync pass into a reported failure.
      final since = _readBuffer(prefs);
      await _writeBuffer(prefs, [...pending, ...since]);
    }
  }

  List<AnalyticsEvent> _readBuffer(SharedPreferences prefs) {
    final raw = prefs.getString(_kBuffer);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return [for (final entry in decoded) ?AnalyticsEvent.tryFromJson(entry)];
  }

  Future<void> _writeBuffer(
    SharedPreferences prefs,
    List<AnalyticsEvent> events,
  ) async {
    if (events.isEmpty) {
      await prefs.remove(_kBuffer);
      return;
    }
    await prefs.setString(
      _kBuffer,
      jsonEncode([for (final e in events) e.toJson()]),
    );
  }
}
