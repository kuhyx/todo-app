import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:todo/desktop/wrapper_server.dart';
import 'package:todo/sync/e2e_passphrase_source.dart';

import 'fake_secure_storage.dart';
import 'wrapper_server_harness.dart';

void main() {
  final h = WrapperHarness()..install();

  group('wrapper e2e passphrase route', () {
    test('serves the shared password once, then 404s', () async {
      final origin = await h.enabledOrigin({'password': 'shared-pw\n'});
      final url = Uri.parse('$origin$kSyncE2ePassphrasePath');
      final first = await http.get(url);
      expect(first.statusCode, HttpStatus.ok);
      expect(first.body, 'shared-pw');
      expect((await http.get(url)).statusCode, HttpStatus.notFound);
    });

    test('is 404 without a password file', () async {
      final origin = await h.enabledOrigin({});
      final url = Uri.parse('$origin$kSyncE2ePassphrasePath');
      expect((await http.get(url)).statusCode, HttpStatus.notFound);
    });
  });

  group('readE2ePassphrase', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      installFakeSecureStorage(initial: {'crdt_sync_e2e_passphrase': ''});
    });

    test('adopts the wrapper passphrase into the keystore once', () async {
      var calls = 0;
      final client = http_testing.MockClient((request) async {
        calls++;
        return http.Response('from-wrapper', 200);
      });
      final base = Uri.parse('http://127.0.0.1:1/');
      expect(
        await readE2ePassphrase(base: base, client: client),
        'from-wrapper',
      );
      expect(
        await readE2ePassphrase(base: base, client: client),
        'from-wrapper',
      );
      expect(calls, 1);
    });

    test('no wrapper (file:// on Android) is just no passphrase', () async {
      expect(await readE2ePassphrase(base: Uri.parse('file:///')), isNull);
    });

    test('a failing wrapper is no passphrase, not a crash', () async {
      final client = http_testing.MockClient(
        (_) async => http.Response('', 404),
      );
      final base = Uri.parse('http://127.0.0.1:1/');
      expect(await readE2ePassphrase(base: base, client: client), isNull);
      final down = http_testing.MockClient(
        (_) async => throw const SocketException('x'),
      );
      expect(await readE2ePassphrase(base: base, client: down), isNull);
    });
  });
}
