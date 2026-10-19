import 'package:crdt_sync/crdt_sync.dart';
import 'package:http/http.dart' as http;
import 'package:todo/cli/cli_session.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/sync_service.dart';

/// A session over an in-memory log whose [sync] reports a scripted `pushed`
/// flag per call, optionally holding a note that already exists.
class ScriptedSession extends CliSession {
  ScriptedSession._(
    NoteRepository repo,
    FirebaseRestClient firebase,
    this._pushed,
  ) : super('unused', repo, firebase);

  static Future<ScriptedSession> create(
    http.Client client,
    List<bool> pushed, {
    String? noteId,
  }) async {
    final repo = await NoteRepository.openInMemory();
    if (noteId != null) {
      final now = DateTime.utc(2026);
      await repo.upsert(
        Note(
          id: noteId,
          text: 'Stuck',
          priority: Priority.medium,
          status: Status.todo,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    final firebase = FirebaseRestClient(
      databaseUrl: 'https://example.test',
      auth: FirebaseTokenProvider(
        apiKey: 'k',
        store: InMemoryCredentialStore(
          FirebaseCredentials(
            idToken: 'id',
            refreshToken: 'rt',
            expiresAt: DateTime.utc(2099),
          ),
        ),
      ),
      httpClient: client,
    );
    return ScriptedSession._(repo, firebase, pushed);
  }

  final List<bool> _pushed;

  @override
  Future<SyncResult> sync({required bool push}) async =>
      SyncResult(mergedDevices: 0, pushed: _pushed.removeAt(0));
}
