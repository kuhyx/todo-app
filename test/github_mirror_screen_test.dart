import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/sync/sync_settings.dart';
import 'package:todo/ui/github_mirror_screen.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'fake_note_repository.dart';
import 'fake_secure_storage.dart';

import 'github_mirror_harness.dart';

/// Stub launcher that records the URL instead of opening it, so `_openPage`
/// can be exercised without a real platform channel.
class _FakeUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  String? launched;

  @override
  final LinkDelegate? linkDelegate = null;

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched = url;
    return true;
  }
}

void main() {
  testWidgets('Connect GitHub without a client id shows guidance', (
    tester,
  ) async {
    await pumpMirror(tester);
    await tester.tap(find.text('Connect GitHub'));
    await tester.pump();
    expect(
      find.textContaining('Enter the OAuth App client id'),
      findsOneWidget,
    );
  });

  testWidgets('Test connection reports a reachable repo', (tester) async {
    final mock = MockClient((_) async => http.Response('{}', 200));
    await pumpMirror(tester, httpClient: mock);

    await tester.tap(find.text('Test connection'));
    await tester.pump(); // start
    await tester.pump(); // resolve future + rebuild

    expect(find.textContaining('reachable'), findsOneWidget);
  });

  testWidgets('Test connection reports an inaccessible repo', (tester) async {
    final mock = MockClient((_) async => http.Response('', 404));
    await pumpMirror(tester, httpClient: mock);

    await tester.tap(find.text('Test connection'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Could not access'), findsOneWidget);
  });

  testWidgets('Test connection surfaces a network error', (tester) async {
    final mock = MockClient((_) async => throw Exception('offline'));
    await pumpMirror(tester, httpClient: mock);

    await tester.tap(find.text('Test connection'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Error:'), findsOneWidget);
  });

  testWidgets('device flow failure to start shows a message', (tester) async {
    final mock = MockClient((_) async => http.Response('nope', 422));
    await pumpMirror(
      tester,
      initial: const SyncSettings(
        owner: 'o',
        repo: 'r',
        token: '',
        clientId: 'cid',
      ),
      httpClient: mock,
    );

    await tester.tap(find.text('Connect GitHub'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Could not start device flow'), findsOneWidget);
  });

  testWidgets('device flow happy path saves the token', (tester) async {
    final mock = MockClient((req) async {
      if (req.url.path.contains('device/code')) {
        return http.Response(
          jsonEncode({
            'device_code': 'dev123',
            'user_code': 'WXYZ-1234',
            'verification_uri': 'https://github.com/login/device',
            'interval': 0,
            'expires_in': 900,
          }),
          200,
        );
      }
      // Token endpoint: authorize immediately.
      return http.Response(jsonEncode({'access_token': 'gho_test'}), 200);
    });

    await pumpMirror(
      tester,
      initial: const SyncSettings(
        owner: 'o',
        repo: 'r',
        token: '',
        clientId: 'cid',
      ),
      httpClient: mock,
    );

    await tester.tap(find.text('Connect GitHub'));
    await tester.pump(); // requestDeviceCode
    await tester.pump(); // dialog builds, shows the user code
    expect(find.text('WXYZ-1234'), findsOneWidget);

    // Let the dialog poll (interval 0) and resolve the token, then the
    // post-connect sync runs against the mock (list → empty, then PUT).
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(find.textContaining('Connected and synced'), findsOneWidget);
  });
}
