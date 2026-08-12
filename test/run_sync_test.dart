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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/analytics/analytics_event.dart';
import 'package:todo/analytics/analytics_service.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/run_sync.dart';
import 'package:todo/sync/sync_settings.dart';

const _settings = SyncSettings(owner: 'kuhyx', repo: 'syncs', token: 'tok');

void main() {
  late NoteRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
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

    expect(result.syncResult.pushed, isTrue);
    expect(paths.every((p) => p.contains('api.github.com')), isTrue);
    // The status line's whole reason for existing: this must read as
    // GitHub-only, not as an unqualified success indistinguishable from a
    // Firebase-connected sync.
    expect(result.syncResult.firebaseConnected, isFalse);
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

    expect(result.syncResult.pushed, isTrue);
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
    expect(result.syncResult.firebaseConnected, isTrue);
  });

  test('leaves appSettings null when the caller passes none', () async {
    final result = await runSync(
      repo,
      _settings,
      httpClient: http_testing.MockClient((request) async {
        return http.Response(jsonEncode({'content': '', 'sha': 'x'}), 200);
      }),
      firebaseFactory: () async => null,
      stateStore: InMemorySyncStateStore(),
    );

    expect(result.appSettings, isNull);
  });

  test(
    'reconciles appSettings and flushes analytics on the same client',
    () async {
      final requestPaths = <String>[];
      final remoteTime = DateTime(2026, 6);
      final firebase = FirebaseRestClient(
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
        httpClient: http_testing.MockClient((request) async {
          requestPaths.add('${request.method} ${request.url.path}');
          if (request.url.path == '/settings/advancedMode.json') {
            return http.Response(
              '{"value": "true", '
              '"updatedAtMillis": "${remoteTime.millisecondsSinceEpoch}"}',
              200,
            );
          }
          if (request.method == 'PUT') return http.Response(request.body, 200);
          return http.Response('null', 200);
        }),
      );
      const analytics = AnalyticsService(nodeId: 'me');
      await analytics.logEvent(
        AnalyticsEvent(name: 'app_open', timestamp: DateTime.now()),
      );

      final result = await runSync(
        repo,
        _settings,
        appSettings: const AppSettings(advancedMode: false),
        analytics: analytics,
        httpClient: http_testing.MockClient((request) async {
          return http.Response(jsonEncode({'content': '', 'sha': 'x'}), 200);
        }),
        firebaseFactory: () async => firebase,
        stateStore: InMemorySyncStateStore(),
      );

      expect(result.appSettings?.advancedMode, isTrue);
      expect(
        requestPaths,
        contains('GET /settings/advancedMode.json'),
        reason: 'appSettings reconciliation used the same Firebase client',
      );
      expect(
        requestPaths.any((p) => p.startsWith('PUT /analytics/me/')),
        isTrue,
        reason: 'analytics flush used the same Firebase client',
      );
    },
  );
}
