import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_account_token/google_account_token.dart'
    show kGoogleAccountTokenChannel;
import 'package:todo/sync/google_sign_in_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  MethodCall? seen;

  void fakeChannel(Future<Object?> Function(MethodCall) handler) {
    messenger.setMockMethodCallHandler(kGoogleAccountTokenChannel, (call) {
      seen = call;
      return handler(call);
    });
  }

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    seen = null;
    messenger.setMockMethodCallHandler(kGoogleAccountTokenChannel, null);
  });

  group('googleIdToken', () {
    test('goes through the shared plugin channel by default', () async {
      fakeChannel((_) async => 'jwt-2');
      expect(await googleIdToken(), 'jwt-2');
      expect(seen?.method, 'idToken');
      expect(seen?.arguments, {'serverClientId': kServerClientId});
    });

    test('a cancelled chooser is null, not an error', () async {
      fakeChannel((_) async => null);
      expect(await googleIdToken(), isNull);
    });
  });

  test('sign-in comes from the shared plugin, not a local copy', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('google_account_token-v0.1.0'));
    expect(pubspec, isNot(contains('google_sign_in')));
    expect(
      File(
        'android/app/src/main/kotlin/dev/kuhy/todo/AccountTokenChannel.kt',
      ).existsSync(),
      isFalse,
    );
    expect(File('lib/sync/account_token.dart').existsSync(), isFalse);
  });
}
