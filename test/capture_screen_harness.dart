/// The shared harness for the capture-screen test files.
///
/// `capture_screen_test.dart` was split by concern for the 250-line cap.
/// [pumpCapture] closes over the `WidgetTester`'s view and addTearDown, so it
/// takes the tester as a parameter rather than being a closure inside main().
///
/// Deliberately NOT named `*_test.dart`: the runner would collect it and fail
/// on the missing `main()`.
library;

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

// A real CRDT DB schedules sqflite timers that never drain under the
// widget tester's fake clock, so these tests inject a timer-free fake.
// (NOTE: avoid pumpAndSettle — the autofocused field's cursor blink never
// settles; pump explicit frames instead.)
Future<FakeNoteRepository> pumpCapture(
  WidgetTester tester, {
  Map<String, Object> prefs = const {},
  http.Client? httpClient,
  List<Note> seed = const [],
  FakeNoteRepository? repository,
  LocalBackup? localBackup,
  Future<FirebaseRestClient?> Function()? firebaseFactory,
  // Defaults to true: these tests exercise today's full UI (priority/status
  // dropdowns, sync status text, Guided). Tests for the new default-off
  // behavior pass advancedMode: false explicitly.
  ValueNotifier<AppSettings>? appSettings,
  AnalyticsService? analytics,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  installFakeSecureStorage();
  // Tall surface so a pushed settings screen builds its whole ListView.
  tester.view.physicalSize = const Size(1200, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repo = repository ?? FakeNoteRepository(seed);
  addTearDown(repo.close);
  // Default to an in-memory, no-op backup so tests never touch real disk
  // (the production backup writes ~/todo/BACKLOG.md on the Linux test host).
  final backup =
      localBackup ??
      LocalBackup(
        fetch: repo.listNotes,
        reader: () async => null,
        writer: (_) async {},
        debounce: Duration.zero,
      );
  await tester.pumpWidget(
    MaterialApp(
      home: CaptureScreen(
        repository: repo,
        appSettings:
            appSettings ?? ValueNotifier(const AppSettings(advancedMode: true)),
        analytics: analytics,
        httpClient: httpClient,
        // Both injected so the widget never reaches for the platform: the
        // real factories want the OS keystore and an application-support
        // directory, neither of which exists under `flutter test`.
        firebaseFactory: firebaseFactory ?? () async => null,
        stateStore: InMemorySyncStateStore(),
        localBackup: backup,
      ),
    ),
  );
  await tester.pump(); // flush initial stream + settings load
  return repo;
}

// Seeds a fully configured GitHub sync so the configured `_sync` path runs.
const configuredPrefs = {
  'sync.owner': 'o',
  'sync.repo': 'r',
  'sync.token': 'tok',
};

// A MockClient that records request methods and answers the sync flow:
// repo-exists GET (not /contents/) → 200, the (empty) log listing → 404,
// and the device's own PUT → 200.
MockClient recordingMock(List<String> methods) => MockClient((req) async {
  methods.add(req.method);
  if (req.method == 'PUT') return http.Response('{}', 200);
  if (!req.url.path.contains('/contents/')) return http.Response('{}', 200);
  return http.Response('', 404);
});
