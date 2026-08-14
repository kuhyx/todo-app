/// The capture screen's small shared pieces: its sync-status record and the
/// metadata dropdown used for priority and status.
///
/// Split out of `capture_screen.dart` for file size. [SyncStatus] was already
/// public; [MetaDropdown] is public only because Dart privacy is
/// library-scoped.
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:todo/sync/sync_service.dart';

/// Formats [t] as HH:MM:SS for the status line.
String formatSyncTime(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// Outcome of a sync attempt, shown in the capture screen's status line.
class SyncStatus {
  /// Creates a [SyncStatus] from a completed sync attempt's outcome.
  const SyncStatus({
    required this.time,
    required this.ok,
    required this.detail,
  });

  /// When the attempt finished.
  final DateTime time;

  /// Whether the sync succeeded.
  final bool ok;

  /// One-line summary: merged/skipped counts on success, the error otherwise.
  final String detail;
}

/// The last sync outcome, in a notifier and in shared preferences.
///
/// Persisted because the status line has to survive a restart: a failure
/// recorded just before the app closed must still be visible next launch,
/// which is the whole point of showing it.
class SyncStatusStore {
  static const _kTime = 'sync.lastTime';
  static const _kOk = 'sync.lastOk';
  static const _kDetail = 'sync.lastDetail';

  /// The latest outcome, or null before the first sync on this install.
  final ValueNotifier<SyncStatus?> latest = ValueNotifier<SyncStatus?>(null);

  /// Reloads the persisted outcome into [latest].
  ///
  /// Does nothing when [latest] already holds something: a sync that
  /// completed while this was in flight is newer than what is on disk.
  Future<void> restore({bool Function()? stillLive}) async {
    final prefs = await SharedPreferences.getInstance();
    final time = DateTime.tryParse(prefs.getString(_kTime) ?? '');
    // Checked after the await, not before: the screen can go away while the
    // read is in flight, and writing the notifier then is a use-after-dispose.
    if (stillLive != null && !stillLive()) return;
    if (time == null || latest.value != null) return;
    latest.value = SyncStatus(
      time: time,
      ok: prefs.getBool(_kOk) ?? true,
      detail: prefs.getString(_kDetail) ?? '',
    );
  }

  /// Records an outcome in [latest] and persists it.
  ///
  /// [live] is false once the screen is gone: the notifier must not be
  /// written after dispose, but the outcome is still worth persisting.
  Future<void> record({
    required bool ok,
    required String detail,
    bool live = true,
  }) async {
    final status = SyncStatus(time: DateTime.now(), ok: ok, detail: detail);
    if (live) latest.value = status;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTime, status.time.toIso8601String());
    await prefs.setBool(_kOk, ok);
    await prefs.setString(_kDetail, detail);
  }

  /// Releases the notifier.
  void dispose() => latest.dispose();
}

/// Human-readable one-liner for a sync outcome, shared by the snackbar and
/// the status line. Skipped files are called out so a peer device silently
/// dropping out of the merge is visible.
///
/// Firebase-vs-GitHub-only is called out too, and first, because it used
/// to read identically either way: "Synced ... merged N device(s))" while
/// disconnected from Firebase looked exactly like success, which is
/// precisely how a desktop stuck syncing over the GitHub mirror alone
/// went unnoticed for days.
String describeSyncResult(SyncResult result) {
  final skipped = result.skippedFiles.length;
  final backend = result.firebaseConnected
      ? ''
      : 'GitHub-only (Firebase not connected) — ';
  return '$backend'
      'merged ${result.mergedDevices} device(s)'
      '${skipped == 0 ? '' : ', skipped $skipped unreadable file(s)'}';
}
