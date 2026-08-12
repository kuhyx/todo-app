/// Tests for the `advancedMode` preference: local persistence and
/// reconciliation against the Firebase mirror.
@TestOn('vm')
library;

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/data/app_settings.dart';

FirebaseRestClient _fakeClient(
  Future<http.Response> Function(http.Request request) handler,
) => FirebaseRestClient(
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
  httpClient: http_testing.MockClient(handler),
);

/// A client with no stored session: any call throws [FirebaseAuthError],
/// the sibling of [FirebaseSyncError] under the shared [RemoteSyncError]
/// supertype — used to confirm the wide-plus-network catches also cover an
/// expired/wrong-account session, not just a transient network failure.
FirebaseRestClient _authFailingClient() => FirebaseRestClient(
  databaseUrl: 'https://x-rtdb.europe-west1.firebasedatabase.app',
  auth: FirebaseTokenProvider(
    apiKey: 'AIzaKey',
    store: InMemoryCredentialStore(),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('load', () {
    test('defaults advancedMode to false with no updatedAt', () async {
      final settings = await AppSettings.load();
      expect(settings.advancedMode, isFalse);
      expect(settings.advancedModeUpdatedAt, isNull);
    });

    test('reads back a previously persisted value', () async {
      final now = DateTime(2026, 1, 1, 12);
      SharedPreferences.setMockInitialValues({
        'app.advancedMode': true,
        'app.advancedMode.updatedAt': now.millisecondsSinceEpoch,
      });
      final settings = await AppSettings.load();
      expect(settings.advancedMode, isTrue);
      expect(settings.advancedModeUpdatedAt, now);
    });
  });

  group('withAdvancedMode', () {
    test('persists locally with no client', () async {
      const initial = AppSettings(advancedMode: false);
      final updated = await initial.withAdvancedMode(value: true);

      expect(updated.advancedMode, isTrue);
      expect(updated.advancedModeUpdatedAt, isNotNull);

      final reloaded = await AppSettings.load();
      expect(reloaded.advancedMode, isTrue);
    });

    test('mirrors to a live client via patchValues', () async {
      final requests = <String>[];
      final client = _fakeClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        return http.Response(request.body, 200);
      });
      const initial = AppSettings(advancedMode: false);

      final updated = await initial.withAdvancedMode(
        value: true,
        client: client,
      );

      expect(updated.advancedMode, isTrue);
      expect(requests, contains('PATCH /settings/advancedMode.json'));
    });

    test('swallows a push failure and keeps the local write', () async {
      final client = _fakeClient(
        (_) async => http.Response('error', 500),
      );
      const initial = AppSettings(advancedMode: false);

      final updated = await initial.withAdvancedMode(
        value: true,
        client: client,
      );

      // The local write still landed even though the mirror push failed.
      expect(updated.advancedMode, isTrue);
      final reloaded = await AppSettings.load();
      expect(reloaded.advancedMode, isTrue);
    });

    test(
      'swallows a FirebaseAuthError (expired session) and keeps the local '
      'write',
      () async {
        const initial = AppSettings(advancedMode: false);

        final updated = await initial.withAdvancedMode(
          value: true,
          client: _authFailingClient(),
        );

        expect(updated.advancedMode, isTrue);
        final reloaded = await AppSettings.load();
        expect(reloaded.advancedMode, isTrue);
      },
    );
  });

  group('reconcileWithRemote', () {
    test('returns unchanged when client is null', () async {
      const initial = AppSettings(advancedMode: false);
      final result = await initial.reconcileWithRemote(null);
      expect(identical(result, initial), isTrue);
    });

    test('returns unchanged when nothing is stored remotely', () async {
      final client = _fakeClient((_) async => http.Response('null', 200));
      const initial = AppSettings(advancedMode: false);

      final result = await initial.reconcileWithRemote(client);

      expect(result.advancedMode, isFalse);
      expect(result.advancedModeUpdatedAt, isNull);
    });

    test(
      'adopts the remote value when local has never round-tripped',
      () async {
        final remoteTime = DateTime(2026);
        final client = _fakeClient(
          (_) async => http.Response(
            '{"value": "true", '
            '"updatedAtMillis": "${remoteTime.millisecondsSinceEpoch}"}',
            200,
          ),
        );
        const initial = AppSettings(advancedMode: false);

        final result = await initial.reconcileWithRemote(client);

        expect(result.advancedMode, isTrue);
        expect(result.advancedModeUpdatedAt, remoteTime);
        final reloaded = await AppSettings.load();
        expect(reloaded.advancedMode, isTrue);
      },
    );

    test('ignores a remote value that is not newer than local', () async {
      final localTime = DateTime(2026, 2);
      final remoteTime = DateTime(2026); // older
      final client = _fakeClient(
        (_) async => http.Response(
          '{"value": "true", '
          '"updatedAtMillis": "${remoteTime.millisecondsSinceEpoch}"}',
          200,
        ),
      );
      final initial = AppSettings(
        advancedMode: false,
        advancedModeUpdatedAt: localTime,
      );

      final result = await initial.reconcileWithRemote(client);

      expect(result.advancedMode, isFalse);
      expect(result.advancedModeUpdatedAt, localTime);
    });

    test('adopts a remote value newer than local', () async {
      final localTime = DateTime(2026);
      final remoteTime = DateTime(2026, 2); // newer
      final client = _fakeClient(
        (_) async => http.Response(
          '{"value": "true", '
          '"updatedAtMillis": "${remoteTime.millisecondsSinceEpoch}"}',
          200,
        ),
      );
      final initial = AppSettings(
        advancedMode: false,
        advancedModeUpdatedAt: localTime,
      );

      final result = await initial.reconcileWithRemote(client);

      expect(result.advancedMode, isTrue);
      expect(result.advancedModeUpdatedAt, remoteTime);
    });

    test('swallows a fetch failure and returns unchanged', () async {
      final client = _fakeClient((_) async => http.Response('error', 500));
      const initial = AppSettings(advancedMode: false);

      final result = await initial.reconcileWithRemote(client);

      expect(result.advancedMode, isFalse);
    });

    test(
      'swallows a FirebaseAuthError (expired session) and returns unchanged',
      () async {
        const initial = AppSettings(advancedMode: false);

        final result = await initial.reconcileWithRemote(
          _authFailingClient(),
        );

        expect(identical(result, initial), isTrue);
      },
    );
  });
}
