import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:todo/sync/firebase_backend.dart';
import 'package:todo/sync/google_sign_in_backend.dart';

import 'fake_secure_storage.dart';

/// Answers a `signInWithIdp` call the way Firebase does.
http_testing.MockClient _signsInAs(String email, {String uid = kSyncUid}) =>
    http_testing.MockClient(
      (request) async => http.Response(
        jsonEncode({
          'idToken': 'id',
          'refreshToken': 'refresh',
          'expiresIn': '3600',
          'email': email,
          'localId': uid,
        }),
        200,
      ),
    );

void main() {
  // installFakeSecureStorage touches the test binary messenger, which only
  // exists once the binding is initialised.
  TestWidgetsFlutterBinding.ensureInitialized();

  // openFirebaseWithGoogle reaches the keystore through a platform channel;
  // the fake stands in so the account write is really exercised rather than
  // stubbed out at the call site.
  setUp(installFakeSecureStorage);

  group('openFirebaseWithGoogle', () {
    test('returns null when the picker is dismissed', () async {
      // Cancelling is ordinary: no session, no account, no error.
      final saved = <FirebaseAccount>[];
      final client = await openFirebaseWithGoogle(
        tokenFetcher: () async => null,
        accountSaver: (account) async => saved.add(account),
      );

      expect(client, isNull);
      expect(saved, isEmpty);
    });

    test('stores the account under the email Firebase reports', () async {
      // The regression this test exists for. A fresh install has no email
      // anywhere on the device, so it must come from the sign-in response. An
      // earlier cut read it from the settings screen's text field -- empty on
      // exactly this path -- and persisted FirebaseAccount(email: ''); the
      // next launch then took the password branch with '' and failed.
      final saved = <FirebaseAccount>[];
      final client = await openFirebaseWithGoogle(
        tokenFetcher: () async => 'a-token',
        accountSaver: (account) async => saved.add(account),
        httpClient: _signsInAs('signed-in@example.com'),
      );

      expect(client, isNotNull);
      expect(saved, hasLength(1));
      expect(saved.single.email, 'signed-in@example.com');
      // No password to store: this device authenticates with the refresh
      // token, and openFirebase() must not later try to sign in with ''.
      expect(saved.single.password, isEmpty);
      client!.close();
    });

    test('stores nothing when Google resolves to the wrong uid', () async {
      // Authentication succeeds and the uid is wrong, which the security
      // rules would deny on every read and write. Failing here -- with
      // nothing persisted -- leaves the device retryable rather than stuck.
      final saved = <FirebaseAccount>[];
      await expectLater(
        openFirebaseWithGoogle(
          tokenFetcher: () async => 'a-token',
          accountSaver: (account) async => saved.add(account),
          httpClient: _signsInAs('someone@example.com', uid: 'a-different-uid'),
        ),
        throwsA(isA<FirebaseAuthError>()),
      );
      expect(saved, isEmpty);
    });
  });

  group('isFirebaseConfigured', () {
    // Regression (2026-08-11): the marker was checked first, so a device whose
    // refresh token had been revoked kept reporting "Connected" while every
    // sync failed with TOKEN_EXPIRED.
    test('is false when only a stale account marker survives', () async {
      await saveAccount(
        const FirebaseAccount(email: 'someone@example.com', password: 'pw'),
      );
      await credentialStore().clear();

      expect(await isFirebaseConfigured(), isFalse);
      expect(
        await storedAccount(),
        isNull,
        reason: 'the stale marker must not be left behind',
      );
    });

    test('is true when a session exists but the marker does not', () async {
      // The opposite failure: reporting the marker alone is what made a phone
      // that was in fact syncing look disconnected.
      await credentialStore().save(
        FirebaseCredentials(
          idToken: 'id',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );

      expect(await isFirebaseConfigured(), isTrue);
    });
  });

  group('loadAccount', () {
    // The account's password grant is retired fleet-wide (see
    // link_google.py/seed_session.py in ~/utils/crdt-sync), so the wrapper's
    // seeded-credentials route is the only fallback that can actually
    // authenticate a fresh desktop install. These exercise loadAccount()'s
    // adoption of that route directly, since Uri.base in a test is
    // file:///, not a wrapper origin -- the same reason accountFromWrapper
    // itself needs an injected client to be testable at all.
    test('adopts seeded credentials from the wrapper', () async {
      final client = http_testing.MockClient((request) async {
        expect(request.url.path, '/sync-credentials');
        return http.Response(
          jsonEncode({
            'id_token': 'id',
            'refresh_token': 'refresh',
            'expires_at': '2026-01-01T00:00:00.000Z',
            'email': 'seeded@example.com',
          }),
          200,
        );
      });

      final account = await loadAccount(httpClient: client);

      expect(account?.email, 'seeded@example.com');
      expect(account?.password, isEmpty);
      expect(await credentialStore().load(), isNotNull);
      expect(await isFirebaseConfigured(), isTrue);
    });

    test(
      'falls back to the account route when no credentials are served',
      () async {
        final client = http_testing.MockClient((request) async {
          if (request.url.path == '/sync-credentials') {
            return http.Response('', 404);
          }
          return http.Response(
            jsonEncode({
              'email': 'password-account@example.com',
              'password': 'pw',
            }),
            200,
          );
        });

        final account = await loadAccount(httpClient: client);

        expect(account?.email, 'password-account@example.com');
        expect(account?.password, 'pw');
      },
    );

    test('returns null when the wrapper serves neither route', () async {
      final client = http_testing.MockClient(
        (request) async => http.Response('', 404),
      );

      expect(await loadAccount(httpClient: client), isNull);
    });

    test('ignores a malformed credentials body', () async {
      final client = http_testing.MockClient((request) async {
        if (request.url.path == '/sync-credentials') {
          return http.Response(jsonEncode({'id_token': 'id'}), 200);
        }
        return http.Response('', 404);
      });

      expect(await loadAccount(httpClient: client), isNull);
    });
  });
}
