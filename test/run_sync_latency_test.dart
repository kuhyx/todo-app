/// The sync spinner must clear in under a second on a phone link.
///
/// Every request to either backend waits [_rtt], a mobile round trip, so the
/// elapsed time measures how many round trips sit on the critical path. The
/// board reported a 3.9 s `sync.run` on the Pixel (todo:0c575b891b).
@TestOn('vm')
library;

import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/run_sync.dart';
import 'package:todo/sync/sync_settings.dart';

import 'fake_secure_storage.dart';

const _rtt = Duration(milliseconds: 150);

/// Firebase RTDB stand-in: a path-keyed JSON store behind a slow link.
class _SlowFirebase {
  final data = <String, Object?>{};
  final requests = <String>[];

  http.Client client() => http_testing.MockClient((request) async {
    requests.add('${request.method} ${request.url.path}');
    await Future<void>.delayed(_rtt);
    final key = request.url.path;
    if (request.method == 'PUT') {
      data[key] = jsonDecode(request.body);
      return http.Response(request.body, 200);
    }
    if (request.method == 'PATCH') return http.Response(request.body, 200);
    return http.Response(jsonEncode(data[key]), 200);
  });
}

FirebaseRestClient _firebase(_SlowFirebase fake) => FirebaseRestClient(
  databaseUrl: 'https://x-rtdb.europe-west1.firebasedatabase.app',
  auth: FirebaseTokenProvider(
    apiKey: 'AIzaKey',
    store: InMemoryCredentialStore(
      FirebaseCredentials(
        idToken: 'id',
        refreshToken: 'refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    ),
  ),
  httpClient: fake.client(),
);

void main() {
  late NoteRepository repo;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    repo = await NoteRepository.openInMemory(nodeId: 'me');
  });

  tearDown(() async => repo.close());

  test('a Firebase-only sync clears the spinner in under 1 s', () async {
    // The phone's setup: Firebase signed in, no GitHub token.
    final fake = _SlowFirebase();
    final github = <String>[];
    final githubClient = http_testing.MockClient((request) async {
      github.add('${request.method} ${request.url.path}');
      await Future<void>.delayed(_rtt);
      return http.Response('', 404);
    });
    final state = InMemorySyncStateStore();
    const none = SyncSettings(owner: '', repo: '', token: '');
    Future<SyncRunResult> once() => runSync(
      repo,
      none,
      appSettings: const AppSettings(advancedMode: true),
      httpClient: githubClient,
      firebaseFactory: () async => _firebase(fake),
      stateStore: state,
    );

    await once(); // first run publishes the header and our log
    fake.requests.clear();
    github.clear();
    final clock = Stopwatch()..start();
    final result = await once();
    clock.stop();

    expect(result.syncResult.firebaseConnected, isTrue);
    expect(github, isEmpty, reason: 'no GitHub token: nothing to mirror');
    expect(
      clock.elapsed,
      lessThan(const Duration(seconds: 1)),
      reason: 'firebase: ${fake.requests}',
    );
  });
}
