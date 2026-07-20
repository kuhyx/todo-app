import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:idb_shim/idb.dart';
import 'package:todo/data/desktop_backup_client.dart';

/// [LogPersistence] backed by IndexedDB, with a best-effort copy pushed to the
/// desktop wrapper so the notes also exist on disk.
///
/// IndexedDB rather than `localStorage` because the latter caps at roughly
/// 5-10MB per origin and is evicted more eagerly; the note log is the primary
/// copy of the backlog and has to outlive storage pressure.
///
/// The disk copy exists because moving the desktop app into a browser would
/// otherwise leave a wiped Chrome profile as a total-loss event for notes that
/// have not synced to GitHub yet. It is deliberately fire-and-forget: the
/// wrapper is an optimisation, and the app must stay fully usable when it is
/// absent (for instance when the same build is opened in a plain browser tab).
class WebLogPersistence implements LogPersistence {
  /// Creates a persistence over [database], mirroring writes to [backup].
  WebLogPersistence({
    required Database database,
    this.backup,
    this.mirrorDebounce = const Duration(seconds: 2),
  }) : _db = database;

  final Database _db;

  /// Wrapper client that mirrors writes to disk, or null when absent.
  final DesktopBackupClient? backup;

  /// How long to coalesce disk mirroring after the last write.
  ///
  /// The store persists on *every* keystroke, so mirroring eagerly would mean
  /// an HTTP request and a whole-log disk write per character. IndexedDB is
  /// still written synchronously with each keystroke; only the durability copy
  /// is debounced.
  final Duration mirrorDebounce;

  Timer? _mirrorTimer;

  /// Object store holding a single record: the serialised log.
  static const storeName = 'log';

  /// Key of that single record.
  static const recordKey = 'notes';

  /// IndexedDB database name.
  static const databaseName = 'todo';

  /// Opens (creating if needed) the IndexedDB database backing the log.
  static Future<Database> openDatabase(IdbFactory factory) => factory.open(
    databaseName,
    version: 1,
    onUpgradeNeeded: (event) {
      final db = event.database;
      if (!db.objectStoreNames.contains(storeName)) {
        db.createObjectStore(storeName);
      }
    },
  );

  @override
  Future<String?> read() async {
    final txn = _db.transaction(storeName, idbModeReadOnly);
    final value = await txn.objectStore(storeName).getObject(recordKey);
    await txn.completed;
    if (value is String && value.isNotEmpty) return value;
    // Nothing local yet (fresh profile, or the browser evicted the database).
    // Fall back to the wrapper's on-disk copy so a cleared profile recovers
    // instead of silently starting from an empty backlog.
    return backup?.readLog();
  }

  @override
  Future<void> write(String text) async {
    final txn = _db.transaction(storeName, idbModeReadWrite);
    await txn.objectStore(storeName).put(text, recordKey);
    await txn.completed;
    _scheduleMirror(text);
  }

  void _scheduleMirror(String text) {
    final client = backup;
    if (client == null) return;
    _mirrorTimer?.cancel();
    _mirrorTimer = Timer(mirrorDebounce, () {
      unawaited(client.writeLog(text));
    });
  }

  /// Cancels any pending disk mirror. Call when tearing the store down.
  void dispose() => _mirrorTimer?.cancel();
}
