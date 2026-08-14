import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/analytics/analytics_service.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/sync/local_backup.dart';
import 'package:todo/sync/notes_markdown.dart';
import 'package:todo/ui/capture_screen.dart';
import 'package:todo/ui/github_mirror_screen.dart';
import 'package:todo/ui/settings_screen.dart';

import 'fake_note_repository.dart';
import 'fake_secure_storage.dart';

import 'capture_screen_harness.dart';

void main() {
  testWidgets(
    'auto-sync adopts a newer advancedMode value from Firebase',
    (tester) async {
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
        httpClient: MockClient((request) async {
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
      final appSettings = ValueNotifier(
        AppSettings(
          advancedMode: false,
          // Older than remoteTime, and non-null, so the reconciliation
          // guard's `currentAt != null && !reconciledAt.isAfter(currentAt)`
          // check actually evaluates both operands.
          advancedModeUpdatedAt: remoteTime.subtract(
            const Duration(days: 1),
          ),
        ),
      );

      await pumpCapture(
        tester,
        prefs: configuredPrefs,
        firebaseFactory: () async => firebase,
        appSettings: appSettings,
      );
      await tester.pump(); // settings load → auto-sync (pull) …
      await tester.pump(); // … then push, then reconcile

      expect(appSettings.value.advancedMode, isTrue);
    },
  );

  testWidgets('logs app_open when analytics is injected', (tester) async {
    const analytics = AnalyticsService(nodeId: 'device-a');
    await pumpCapture(tester, analytics: analytics);
    await tester.pump(); // flush the unawaited logEvent's prefs write

    final prefs = await SharedPreferences.getInstance();
    final buffer = prefs.getString('analytics.buffer');
    expect(buffer, isNotNull);
    expect(buffer, contains('app_open'));
  });

  testWidgets('auto-syncs on launch when configured', (tester) async {
    final methods = <String>[];
    await pumpCapture(
      tester,
      prefs: configuredPrefs,
      httpClient: recordingMock(methods),
    );
    await tester.pump(); // settings load → auto-sync (pull) …
    await tester.pump(); // … then push

    expect(methods, contains('PUT')); // this device pushed its changeset
  });

  testWidgets('does not auto-sync when unconfigured', (tester) async {
    final methods = <String>[];
    await pumpCapture(tester, httpClient: recordingMock(methods)); // no token
    await tester.pump();
    await tester.pump();

    expect(methods, isEmpty);
  });

  testWidgets('auto-syncs again when the app is backgrounded', (tester) async {
    final methods = <String>[];
    await pumpCapture(
      tester,
      prefs: configuredPrefs,
      httpClient: recordingMock(methods),
    );
    await tester.pump();
    await tester.pump();
    methods.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump();

    // A sync ran. Not `contains('PUT')`: the launch sync above already pushed
    // this log, so revision tracking correctly suppresses the second, unchanged
    // push -- that suppression is the point of the revision cache.
    expect(methods, isNotEmpty);
  });

  testWidgets('auto-sync failure shows no snackbar but flags the status line', (
    tester,
  ) async {
    final mock = MockClient((_) async => throw Exception('offline'));
    await pumpCapture(tester, prefs: configuredPrefs, httpClient: mock);
    await tester.pump();
    await tester.pump();

    // Capture must never be interrupted by a snackbar…
    expect(find.byType(SnackBar), findsNothing);
    // …but the failure is no longer swallowed: the status line shows it.
    expect(find.textContaining('Sync failed at'), findsOneWidget);
    expect(find.textContaining('offline'), findsOneWidget);
  });
}
