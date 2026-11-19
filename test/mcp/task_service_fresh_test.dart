// A read call (list/search/get) used to sync with Firebase every time, so the
// board's one fetch of 15 calls took 12 s and a note added in the app showed
// up 10-40 s later. Reads now reuse a sync that finished within
// `readFreshness`; every write still pulls and pushes.

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:todo/cli/cli_session.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/mcp/task_service.dart';
import 'package:todo/sync/sync_service.dart';

/// Counts [sync] calls; each one answers at once.
class _Counting extends CliSession {
  _Counting(NoteRepository repo, FirebaseRestClient firebase)
    : super('unused', repo, firebase);

  int syncs = 0;

  @override
  Future<SyncResult> sync({required bool push}) {
    syncs++;
    return Future.value(const SyncResult(mergedDevices: 0, pushed: false));
  }
}

Future<_Counting> _session() async {
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
    httpClient: http.Client(),
  );
  return _Counting(await NoteRepository.openInMemory(), firebase);
}

void main() {
  const window = Duration(milliseconds: 300);
  late _Counting session;
  late TaskService tasks;
  setUp(() async {
    session = await _session();
    tasks = TaskService(session, readFreshness: window);
  });

  test('[T-fresh] reads inside the window share one sync', () async {
    await tasks.list({});
    await tasks.list({'no_repo': true});
    await tasks.search({'query': 'x'});
    expect(session.syncs, 1);
  });

  test('[T-fresh] a read after the window syncs again', () async {
    await tasks.list({});
    await Future<void>.delayed(window + const Duration(milliseconds: 100));
    await tasks.list({});
    expect(session.syncs, 2);
  });

  test(
    '[T-fresh] a write always syncs, and counts as fresh for reads',
    () async {
      await tasks.list({});
      await tasks.add({'repo': 'kuhyx/x', 'title': 'a task'});
      final afterAdd = session.syncs;
      expect(afterAdd, greaterThan(1));
      await tasks.list({});
      expect(session.syncs, afterAdd);
    },
  );

  test('[T-fresh] a zero window keeps the old sync-every-read', () async {
    final strict = TaskService(session, readFreshness: Duration.zero);
    await strict.list({});
    await strict.list({});
    expect(session.syncs, 2);
  });
}
