import 'dart:io';

import 'package:crdt_sync/crdt_sync_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:todo/data/legacy_sqlite_migration.dart';
import 'package:todo/data/note_repository.dart';
import 'package:uuid/uuid.dart';

/// Opens the note store on a `dart:io` platform (Android).
///
/// Also performs the one-time, idempotent import of a pre-crdt_sync sqlite
/// database, guarded by a persisted flag. The legacy DB file is left untouched
/// as a safety net.
// coverage:ignore-start
// Resolves the real per-platform application-support directory, so it cannot
// run under test; [openRepositoryIn] holds all the logic and is covered.
Future<NoteRepository> openRepository() async {
  final dir = await getApplicationSupportDirectory();
  return openRepositoryIn(dir.path);
}
// coverage:ignore-end

/// Opens the note store rooted at [dirPath].
///
/// Split out from [openRepository] so tests can drive the legacy-migration
/// paths against a temporary directory without going through `path_provider`.
Future<NoteRepository> openRepositoryIn(String dirPath) async {
  // Keep the FFI initialisation for any non-Android io host that still reads a
  // legacy DB (and for the test host, which is Linux).
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
  }

  final dbPath = p.join(dirPath, 'todo.db');
  final persistence = FileLogPersistence(
    File(p.join(dirPath, NoteRepository.logFileName)),
  );

  final prefs = await SharedPreferences.getInstance();
  final migrated = prefs.getBool(NoteRepository.kMigrated) ?? false;
  var nodeId = prefs.getString(NoteRepository.kNodeId) ?? '';

  if (!migrated && LegacySqliteMigration.exists(dbPath)) {
    final legacy = await LegacySqliteMigration.read(dbPath, nodeId);
    nodeId = legacy.nodeId;
    final repository = await NoteRepository.openWith(
      persistence: persistence,
      nodeId: nodeId,
    );
    await repository.seedFrom(legacy.log);
    await prefs.setString(NoteRepository.kNodeId, nodeId);
    await prefs.setBool(NoteRepository.kMigrated, true);
    return repository;
  }

  if (nodeId.isEmpty) {
    nodeId = const Uuid().v4();
    await prefs.setString(NoteRepository.kNodeId, nodeId);
  }
  return NoteRepository.openWith(persistence: persistence, nodeId: nodeId);
}
