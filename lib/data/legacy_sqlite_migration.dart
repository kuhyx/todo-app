import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
// Only SqliteCrdt/CrdtTableExecutor are needed to read the legacy DB; hide its
// Hlc so the crdt_sync Hlc (the store's clock type) is unambiguous.
import 'package:sqlite_crdt/sqlite_crdt.dart' hide Hlc;
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';

/// Reads a pre-crdt_sync `sqlite_crdt` database into a crdt_sync [Log].
///
/// Lives in its own `dart:io` library so [NoteRepository] can stay pure Dart:
/// the desktop app is a web build, and one `dart:io` import anywhere in the
/// graph fails the whole web compile. Mobile still runs this on first launch
/// after the cutover; web never does, because there is no legacy DB in a
/// browser profile.
class LegacySqliteMigration {
  /// Whether a legacy database exists at [path] to migrate from.
  static bool exists(String path) => File(path).existsSync();

  /// Opens the legacy DB at [path] and returns its notes as a [Log], plus the
  /// legacy CRDT node id.
  ///
  /// Reusing the legacy node id keeps a device that already synced on the same
  /// `devices/<id>` identity across the cutover, so it does not appear as a new
  /// peer and re-upload everything.
  static Future<({Log log, String nodeId})> read(
    String path,
    String preferredNodeId,
  ) async {
    final legacy = await SqliteCrdt.open(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    final nodeId = preferredNodeId.isEmpty ? legacy.nodeId : preferredNodeId;
    final rows = await legacy.query(
      'SELECT id, text, priority, status, created_at, updated_at, is_deleted '
      'FROM notes',
    );
    final log = <String, Record>{};
    for (final row in rows) {
      final note = Note.fromRow(row);
      log[note.id] = NoteRepository.legacyRecordFor(
        note,
        nodeId,
        deleted: (row['is_deleted'] as int? ?? 0) != 0,
      );
    }
    await legacy.close();
    return (log: log, nodeId: nodeId);
  }

  static const int _version = 3;

  // coverage:ignore-start
  // Unreachable: migration only ever opens a legacy DB that already exists
  // (guarded by [exists]), so sqlite never runs onCreate. Kept because
  // SqliteCrdt.open requires the callback.
  static Future<void> _onCreate(CrdtTableExecutor db, int version) async {
    await db.execute('''
      CREATE TABLE notes (
        id TEXT NOT NULL,
        text TEXT NOT NULL DEFAULT '',
        priority INTEGER NOT NULL DEFAULT 2,
        status INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (id)
      )
    ''');
  }
  // coverage:ignore-end

  static Future<void> _onUpgrade(
    CrdtTableExecutor db,
    int from,
    int to,
  ) async {
    if (from < 2) {
      await db.execute(
        'ALTER TABLE notes ADD COLUMN status INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (from < 3) {
      await db.execute('UPDATE notes SET priority = 2 WHERE priority = 0');
    }
  }
}
