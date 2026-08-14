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
  testWidgets('Sync with a configured token runs the sync service', (
    tester,
  ) async {
    // Empty remote directory → the service has nothing to merge and pushes
    // this device's own log (PUT). The bare repo GET (not /contents/) returns
    // 200 so crdt_sync's client treats the 404 dir as "empty", not missing.
    final mock = MockClient((req) async {
      if (req.method == 'PUT') return http.Response('{}', 200);
      if (!req.url.path.contains('/contents/')) return http.Response('{}', 200);
      return http.Response('', 404);
    });
    await pumpCapture(tester, prefs: configuredPrefs, httpClient: mock);

    await tester.tap(find.byTooltip('Sync'));
    await tester.pump(); // setState(_syncing = true)
    await tester.pump(); // service runs, snackbar scheduled
    await tester.pump(); // snackbar builds

    // No firebaseFactory was injected, so this runs over GitHub alone --
    // the status line must say so rather than reading identically to a
    // Firebase-connected sync.
    expect(
      find.textContaining(
        'Synced: GitHub-only (Firebase not connected) — merged 0 device',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Sync surfaces a failure from the sync service', (tester) async {
    final mock = MockClient((_) async => throw Exception('offline'));
    await pumpCapture(tester, prefs: configuredPrefs, httpClient: mock);

    await tester.tap(find.byTooltip('Sync'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // 'Sync failed:' is the snackbar; the status line says 'Sync failed at'.
    expect(find.textContaining('Sync failed:'), findsOneWidget);
    expect(find.textContaining('Sync failed at'), findsOneWidget);
  });

  testWidgets('manual sync reports peer files it could not decode', (
    tester,
  ) async {
    // One peer file exists but holds garbage → merged 0, skipped 1.
    final mock = MockClient((req) async {
      if (req.method == 'PUT') return http.Response('{}', 200);
      if (!req.url.path.contains('/contents/')) return http.Response('{}', 200);
      if (req.url.path.endsWith('/todo-sync/notes')) {
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

    await tester.tap(find.byTooltip('Sync'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(
      find.textContaining('skipped 1 unreadable file(s)'),
      findsWidgets, // snackbar and status line both call it out
    );
  });

  testWidgets('returning from settings adopts the saved configuration', (
    tester,
  ) async {
    await pumpCapture(tester);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle(); // route transition
    expect(find.byType(SettingsScreen), findsOneWidget); // settings is up

    // GitHub sync settings (owner/repo/token) now live on the standalone
    // GitHubMirrorScreen, reached via a link from SettingsScreen. The pop
    // value itself is discarded by SettingsScreen; _openSettings always
    // reloads from storage instead (a device-flow "Connect" saves the token
    // without popping a result at all, so a stale in-memory value would be
    // wrong there too). This exercises that reload-after-return path, then
    // Back returns to capture.
    await tester.tap(find.text('Advanced sync (GitHub)'));
    await tester.pumpAndSettle(); // route transition
    expect(find.byType(GitHubMirrorScreen), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle(); // save + pop transition back to Settings
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle(); // pop transition back to capture

    expect(find.byType(SettingsScreen), findsNothing); // back on capture
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  // A MockClient that records request methods and answers the sync flow:
  // repo-exists GET (not /contents/) → 200, the (empty) log listing → 404,
  // and the device's own PUT → 200.
  MockClient recordingMock(List<String> methods) => MockClient((req) async {
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
      expect(find.text('Guided'), findsNothing);
      expect(find.text('Template'), findsNothing);
      // The capture screen's priority/status row is gone.
      expect(find.text('Priority'), findsNothing);
      expect(find.text('Status'), findsNothing);
      // Routine status chatter is gone; only a badge count remains.
      expect(find.textContaining('Autosaves as you type'), findsNothing);
      expect(find.text('1'), findsOneWidget);
      // The note still persisted normally underneath the simplified UI.
      expect(find.text('A plain idea'), findsOneWidget);
    },
  );

  testWidgets(
    'draft text survives an advancedMode toggle mid-typing',
    (tester) async {
      final appSettings = ValueNotifier(
        const AppSettings(advancedMode: true),
      );
      await pumpCapture(tester, appSettings: appSettings);

      await tester.enterText(
        find.byType(TextField).first,
        'my important idea',
      );
      await tester.pump();

      // The Row above the editor is conditionally present, which shifts the
      // editor's position in the Column whenever advancedMode changes at
      // runtime — a key one level too shallow doesn't survive that
      // reposition and Flutter remounts the editor with an empty draft.
      appSettings.value = const AppSettings(advancedMode: false);
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField).first);
      expect(field.controller?.text, contains('my important idea'));
    },
  );
}
