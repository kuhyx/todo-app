import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/sync/account_token.dart';
import 'package:todo/sync/google_sign_in_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  MethodCall? seen;

  void fakeChannel(Future<Object?> Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(kAccountTokenChannel, (call) {
      seen = call;
      return handler(call);
    });
  }

  tearDown(() {
    seen = null;
    messenger.setMockMethodCallHandler(kAccountTokenChannel, null);
  });

  group('accountManagerIdToken', () {
    test('asks the platform for a token for the web client', () async {
      fakeChannel((_) async => 'jwt');
      final token = await accountManagerIdToken(serverClientId: 'web-id');
      expect(token, 'jwt');
      expect(seen?.method, 'idToken');
      expect(seen?.arguments, {'serverClientId': 'web-id'});
    });

    test('a cancelled chooser is null, not an error', () async {
      fakeChannel((_) async => null);
      expect(await accountManagerIdToken(serverClientId: 'x'), isNull);
    });

    test('a platform failure is null, not a throw', () async {
      fakeChannel((_) async => throw PlatformException(code: 'auth_failed'));
      expect(await accountManagerIdToken(serverClientId: 'x'), isNull);
    });
  });

  group('googleIdToken', () {
    test('goes through the AccountManager channel by default', () async {
      fakeChannel((_) async => 'jwt-2');
      expect(await googleIdToken(), 'jwt-2');
      expect(seen?.arguments, {'serverClientId': kServerClientId});
    });
  });

  test('no proprietary sign-in dependency is declared', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('google_sign_in')));
  });
}
