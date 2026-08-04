/// Tests for the one place that decides *how* a sync runs.
///
/// The branch that matters is which backend ends up authoritative: a rollback
/// depends on getting exactly that right.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/run_sync.dart';
import 'package:todo/sync/sync_settings.dart';

const _settings = SyncSettings(owner: 'kuhyx', repo: 'syncs', token: 'tok');

void main() {
  late NoteRepository repo;

  setUp(() async {
    repo = await NoteRepository.openInMemory(nodeId: 'me');
  });

  tearDown(() async => repo.close());

  test('syncs over GitHub alone when Firebase is not set up', () async {
    // The pre-migration path, and the rollback: no Firebase, no mirror.
    final paths = <String>[];
    final result = await runSync(
      repo,
      _settings,
      httpClient: http_testing.MockClient((request) async {
        paths.add('${request.method} ${request.url.host}');
        return http.Response(jsonEncode({'content': '', 'sha': 'x'}), 200);
      }),
      firebaseFactory: () async => null,
      stateStore: InMemorySyncStateStore(),
    );

    expect(result.pushed, isTrue);
    expect(paths.every((p) => p.contains('api.github.com')), isTrue);
  });

  test('makes Firebase primary and still mirrors to GitHub', () async {
    // The cutover guarantee: both backends receive the write.
    final githubPaths = <String>[];
    final firebasePaths = <String>[];
    final firebase = FirebaseRestClient(
      databaseUrl: 'https://x-rtdb.europe-west1.firebasedatabase.app',
      auth: FirebaseTokenProvider(
        apiKey: 'AIzaKey',
        store: InMemoryCredentialStore(
          FirebaseCredentials(
            idToken: 'id',
            refreshToken: 'refresh',
            // Real clock: the provider compares against DateTime.now(), so a
            // fixture-dated session would look expired and force a refresh.
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        ),
      ),
      httpClient: http_testing.MockClient((request) async {
        firebasePaths.add('${request.method} ${request.url.path}');
        if (request.method == 'PUT') return http.Response(request.body, 200);
        return http.Response('null', 200);
      }),
    );

    final result = await runSync(
      repo,
      _settings,
      httpClient: http_testing.MockClient((request) async {
        githubPaths.add(request.method);
        return http.Response(jsonEncode({'content': '', 'sha': 'x'}), 200);
      }),
      firebaseFactory: () async => firebase,
      stateStore: InMemorySyncStateStore(),
    );

    expect(result.pushed, isTrue);
    expect(
      firebasePaths.any((p) => p.startsWith('PUT')),
      isTrue,
      reason: 'Firebase is primary and must receive the write',
    );
    expect(
      githubPaths,
      contains('PUT'),
      reason: 'GitHub must still be mirrored during the cutover',
    );
  });
}
