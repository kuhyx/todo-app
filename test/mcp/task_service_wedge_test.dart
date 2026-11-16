// A sync that never answers (dead connection after boot or a network blip)
// must not wedge the one-at-a-time queue: every later call, including the
// board's 4 s poll, used to wait behind it forever, abandoned connections
// piled up until the process ran out of file descriptors, and the tokens
// file became unreadable, so a valid token read as HTTP 403.
import 'dart:async';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:todo/cli/cli_session.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/mcp/task_service.dart';
import 'package:todo/sync/sync_service.dart';

/// Hangs the first [sync] forever; later ones return at once.
class _HangsOnce extends CliSession {
  _HangsOnce(NoteRepository repo, FirebaseRestClient firebase)
    : super('unused', repo, firebase);

  var _calls = 0;

  @override
  Future<SyncResult> sync({required bool push}) => _calls++ == 0
      ? Completer<SyncResult>().future
      : Future.value(const SyncResult(mergedDevices: 0, pushed: false));
}

Future<_HangsOnce> _session() async {
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
  return _HangsOnce(await NoteRepository.openInMemory(), firebase);
}

void main() {
  test(
    '[T-wedge] a hung sync times out and the next call still runs',
    () async {
      final tasks = TaskService(
        await _session(),
        callTimeout: const Duration(milliseconds: 200),
      );
      await expectLater(tasks.list({}), throwsA(isA<TimeoutException>()));
      expect(await tasks.list({}), isNotNull);
    },
  );
}
