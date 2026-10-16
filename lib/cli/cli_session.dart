/// One headless CLI run: a local note log, its node id, and a Firebase client.
///
/// Built only from Flutter-free pieces of the app (the [NoteRepository], the
/// [SyncService] every device runs, and [kProject]) so `dart run` works with
/// no Flutter engine — the same constraint `tool/sync_smoke.dart` lives under.
/// The writes are therefore ordinary CRDT changes from one more device, never
/// records hand-written into RTDB.
library;

import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:crdt_sync/crdt_sync_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:todo/cli/file_credential_store.dart';
import 'package:todo/cli/pull_only_store.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/firebase_project.dart';
import 'package:todo/sync/sync_service.dart';
import 'package:uuid/uuid.dart';

/// Default data dir: `$XDG_DATA_HOME/todo-cli`, else `~/.local/share/todo-cli`.
String defaultDataDir(Map<String, String> env) {
  final xdg = env['XDG_DATA_HOME'] ?? '';
  final base = xdg.isNotEmpty
      ? xdg
      : p.join(env['HOME'] ?? '', '.local', 'share');
  return p.join(base, 'todo-cli');
}

/// The open state of one CLI invocation. Call [close] when done.
class CliSession {
  /// Wraps already-open parts; [open] is the normal way in. Public so a test
  /// can subclass the session and script [sync]'s outcome.
  CliSession(this.dataDir, this.repository, this._firebase);

  /// File holding this install's persisted CRDT node id.
  static const nodeIdFileName = 'node_id';

  /// File holding the per-peer revision cache (see [SyncService.stateStore]).
  static const syncStateFileName = 'sync_state.json';

  /// The CLI's private copy of the Firebase session.
  static const credentialsFileName = 'firebase_auth.json';

  /// Where the local log, node id and session copy live.
  final String dataDir;

  /// The note store, exactly the class the app uses.
  final NoteRepository repository;

  final FirebaseRestClient _firebase;

  /// Opens (creating on first use) the session rooted at [dataDir].
  ///
  /// [seedCredentials] is todo's desktop session, read once and never written.
  /// [httpClient] replaces the real network client (tests only).
  static Future<CliSession> open(
    String dataDir, {
    required String seedCredentials,
    http.Client? httpClient,
  }) async {
    final dir = Directory(dataDir);
    await dir.create(recursive: true);
    // Holds a database-write credential: owner-only, like ~/.config/todo.
    await Process.run('chmod', ['700', dir.path]);
    final repository = await NoteRepository.openWith(
      persistence: FileLogPersistence(
        File(p.join(dataDir, NoteRepository.logFileName)),
      ),
      nodeId: await _nodeId(dataDir),
    );
    final auth = FirebaseTokenProvider(
      apiKey: kProject.apiKey,
      httpClient: httpClient,
      store: FileCredentialStore(
        file: File(p.join(dataDir, credentialsFileName)),
        seedFile: File(seedCredentials),
      ),
    );
    if (!await auth.hasSession()) {
      await repository.close();
      throw FirebaseAuthError(
        'no Firebase session: $seedCredentials is missing; re-seed it with '
        '`python3 ~/src/utils/crdt-sync/tool/seed_session.py --app todo`',
      );
    }
    final firebase = FirebaseRestClient(
      databaseUrl: kProject.databaseUrl,
      auth: auth,
      httpClient: httpClient,
    );
    return CliSession(dataDir, repository, firebase);
  }

  /// Pull every peer's log and merge it; with [push], also publish this
  /// node's merged log and its revision, exactly as a device's sync tick does.
  ///
  /// Without [push] nothing is written anywhere remote, and the revision cache
  /// is bypassed so a read always sees every peer's current log.
  Future<SyncResult> sync({required bool push}) {
    if (!push) {
      return const SyncService().sync(repository, PullOnlyStore(_firebase));
    }
    return SyncService(
      stateStore: PersistedSyncStateStore(
        FileLogPersistence(File(p.join(dataDir, syncStateFileName))),
      ),
    ).sync(repository, _firebase);
  }

  /// Releases the log and the HTTP client.
  Future<void> close() async {
    _firebase.close();
    await repository.close();
  }

  /// Reads this install's node id, minting and persisting a uuid on first run.
  ///
  /// Never a fixed name: two installs sharing an id would overwrite each
  /// other's file under `todo-sync/notes/` and lose writes.
  static Future<String> _nodeId(String dataDir) async {
    final file = File(p.join(dataDir, nodeIdFileName));
    if (file.existsSync()) {
      final stored = (await file.readAsString()).trim();
      if (stored.isNotEmpty) return stored;
    }
    final minted = const Uuid().v4();
    await file.writeAsString('$minted\n');
    return minted;
  }
}
