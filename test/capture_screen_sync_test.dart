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
import 'e2e_github_header.dart';
import 'fake_secure_storage.dart';

import 'capture_screen_harness.dart';
import 'text_free_guard.dart';

void main() {
  testWidgets('Sync with a configured token runs the sync service', (
    tester,
  ) async {
    // Empty remote directory → the service has nothing to merge and pushes
    // this device's own log (PUT). The bare repo GET (not /contents/) returns
    // 200 so crdt_sync's client treats the 404 dir as "empty", not missing.
    final mock = e2eMock((req) async {
      if (req.method == 'PUT') return http.Response('{}', 200);
      if (!req.url.path.contains('/contents/')) return http.Response('{}', 200);
      return http.Response('', 404);
    });
    await pumpCapture(tester, prefs: configuredPrefs, httpClient: mock);

    await tester.tap(find.bySemanticsLabel('Sync'));
    await tester.pump(); // setState(_syncing = true)
    await tester.pump(); // service runs, snackbar scheduled
    await tester.pump(); // snackbar builds
    await tester.pump(const Duration(milliseconds: 500)); // snack fades in

    // No firebaseFactory was injected, so this runs over GitHub alone --
    // the status line must say so rather than reading identically to a
    // Firebase-connected sync.
    expect(
      spoken('Synced: GitHub-only (Firebase not connected) — merged 0 device'),
      findsOneWidget,
    );
  });

  testWidgets('Sync surfaces a failure from the sync service', (tester) async {
    final mock = MockClient((_) async => throw Exception('offline'));
    await pumpCapture(tester, prefs: configuredPrefs, httpClient: mock);

    await tester.tap(find.bySemanticsLabel('Sync'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // snack fades in

    // 'Sync failed:' is the snackbar; the status line says 'Sync failed at'.
    expect(spoken('Sync failed:'), findsOneWidget);
    expect(spoken('Sync failed at'), findsOneWidget);
  });

  testWidgets('manual sync reports peer files it could not decode', (
    tester,
  ) async {
    // One peer file exists but holds garbage → merged 0, skipped 1.
    final mock = e2eMock((req) async {
      if (req.method == 'PUT') return http.Response('{}', 200);
      if (!req.url.path.contains('/contents/')) return http.Response('{}', 200);
      if (req.url.path.endsWith('/todo-sync/notes-e2e')) {
        return http.Response('[{"name": "bad.json"}]', 200);
      }
      if (req.url.path.endsWith('/bad.json')) {
        return http.Response(
          '{"content": "${base64Encode(utf8.encode('{not a log'))}"}',
          200,
        );
      }
      return http.Response('', 404); // own-file sha probe → create fresh
    });
    await pumpCapture(tester, prefs: configuredPrefs, httpClient: mock);

    await tester.tap(find.bySemanticsLabel('Sync'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500)); // snack fades in

    expect(
      spoken('skipped 1 unreadable file(s)'),
      findsWidgets, // snackbar and status line both call it out
    );
  });

  testWidgets('returning from settings adopts the saved configuration', (
    tester,
  ) async {
    await pumpCapture(tester);

    await tester.tap(find.bySemanticsLabel('Settings'));
    await tester.pumpAndSettle(); // route transition
    expect(find.byType(SettingsScreen), findsOneWidget); // settings is up

    // GitHub sync settings (owner/repo/token) now live on the standalone
    // GitHubMirrorScreen, reached via a link from SettingsScreen. The pop
    // value itself is discarded by SettingsScreen; _openSettings always
    // reloads from storage instead (a device-flow "Connect" saves the token
    // without popping a result at all, so a stale in-memory value would be
    // wrong there too). This exercises that reload-after-return path, then
    // Back returns to capture.
    await tester.tap(find.byIcon(Icons.cloud_sync));
    await tester.pumpAndSettle(); // route transition
    expect(find.byType(GitHubMirrorScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Save'));
    await tester.pumpAndSettle(); // save + pop transition back to Settings
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton)); // no 'Back' tooltip to find
    await tester.pumpAndSettle(); // pop transition back to capture

    expect(find.byType(SettingsScreen), findsNothing); // back on capture
    expect(find.bySemanticsLabel('Settings'), findsOneWidget);
  });

  // A MockClient that records request methods and answers the sync flow:
  // repo-exists GET (not /contents/) → 200, the (empty) log listing → 404,
  // and the device's own PUT → 200.
  MockClient recordingMock(List<String> methods) => e2eMock((req) async {
    methods.add(req.method);
    if (req.method == 'PUT') return http.Response('{}', 200);
    if (!req.url.path.contains('/contents/')) return http.Response('{}', 200);
    return http.Response('', 404);
  });

  testWidgets(
    'advancedMode off shows just the text field, no chrome or status text',
    (tester) async {
      await pumpCapture(
        tester,
        appSettings: ValueNotifier(const AppSettings(advancedMode: false)),
      );
      await tester.enterText(find.byType(TextField), 'A plain idea');
      await tester.pump();

      // The editor's own template/mode chrome is gone.
      expect(find.bySemanticsLabel('Guided'), findsNothing);
      expect(find.bySemanticsLabel('Template'), findsNothing);
      // The capture screen's priority/status row is gone.
      expect(find.bySemanticsLabel('Priority'), findsNothing);
      expect(find.bySemanticsLabel('Status'), findsNothing);
      // Routine status chatter is gone; only a badge count remains.
      expect(spoken('Autosaves as you type'), findsNothing);
      expect(find.text('1'), findsOneWidget);
      // The note still persisted normally underneath the simplified UI.
      expect(find.text('A plain idea'), findsOneWidget);
    },
  );

  testWidgets('draft text survives an advancedMode toggle mid-typing', (
    tester,
  ) async {
    final appSettings = ValueNotifier(const AppSettings(advancedMode: true));
    await pumpCapture(tester, appSettings: appSettings);

    await tester.enterText(find.byType(TextField).first, 'my important idea');
    await tester.pump();

    // NoteForm's metadata row is conditionally present, so toggling
    // advancedMode changes the editor's position beneath it — a key one
    // level too shallow doesn't survive that reposition and Flutter
    // remounts the editor with an empty draft, losing the typing.
    appSettings.value = const AppSettings(advancedMode: false);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller?.text, contains('my important idea'));
  });
}
