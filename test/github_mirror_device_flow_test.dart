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
  testWidgets('device flow connects but surfaces a post-connect sync failure', (
    tester,
  ) async {
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
      if (req.url.path.contains('login/oauth/access_token')) {
        return http.Response(jsonEncode({'access_token': 'gho_test'}), 200);
      }
      return http.Response('boom', 500); // the sync's repo calls fail
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
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }

    expect(find.textContaining('sync failed'), findsOneWidget);
  });

  testWidgets('Save persists the settings and closes the screen', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage();
    tester.view.physicalSize = const Size(1200, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = FakeNoteRepository();
    addTearDown(repo.close);

    // Push GitHubMirrorScreen over a base route so _save's Navigator.pop has
    // somewhere to return to (popping the root route is a no-op and hides
    // the result).
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<SyncSettings>(
                    builder: (_) => GitHubMirrorScreen(
                      initial: const SyncSettings(
                        owner: 'o',
                        repo: 'r',
                        token: 'tok',
                      ),
                      repository: repo,
                      appSettings: ValueNotifier(
                        const AppSettings(advancedMode: false),
                      ),
                      firebaseFactory: () async => null,
                      stateStore: InMemorySyncStateStore(),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // route transition
    expect(find.byType(GitHubMirrorScreen), findsOneWidget); // screen is up

    await tester.tap(find.text('Save'));
    await tester.pump(); // run _save (persist + pop)
    await tester.pump(const Duration(milliseconds: 400)); // pop transition

    expect(find.text('open'), findsOneWidget); // back on the base route
    final saved = await SyncSettings.load();
    expect(saved.owner, 'o');
    expect(saved.token, 'tok');
  });

  testWidgets('device dialog: failed poll shows the error and Open launches', (
    tester,
  ) async {
    final launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;

    // _openPage copies the code to the clipboard first; there's no
    // clipboard plugin in the test host, so stub the channel to succeed.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

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
      // Token endpoint: a terminal error ends the poll loop cleanly (no
      // lingering timer to trip the tester's pending-timer guard).
      return http.Response(
        jsonEncode({'error': 'access_denied', 'error_description': 'nope'}),
        200,
      );
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
    await tester.pump(); // dialog builds, poll starts (interval 0)
    expect(find.text('WXYZ-1234'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1)); // _delay(0) fires
    await tester.pump(); // token error throws → _error set
    expect(find.textContaining('nope'), findsOneWidget); // error rendered

    // Tap the "open on GitHub" action: copies the code and launches the URL.
    // _openPage awaits Clipboard.setData then the launcher's supportsMode +
    // launchUrl; pumpAndSettle drains them (no spinner is animating now
    // that the error is shown, so it settles).
    await tester.tap(find.byIcon(Icons.open_in_new));
    await tester.pumpAndSettle();
    expect(launcher.launched, 'https://github.com/login/device');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle(); // finish the dialog pop animation
    expect(find.text('WXYZ-1234'), findsNothing); // dialog dismissed
  });
}
