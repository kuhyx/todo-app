/// The pumpSettings harness and its file-selector fakes.
///
/// Shared by the files `settings_screen_test.dart` was split into for the
/// 250-line cap. Deliberately NOT named `*_test.dart`: the runner would
/// collect it and fail on the missing `main()`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sync_settings_ui/sync_settings_ui.dart';
import 'package:todo/analytics/analytics_service.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/backlog_export_io.dart';
import 'package:todo/sync/notes_markdown.dart';
import 'package:todo/sync/sync_settings.dart';
import 'package:todo/ui/github_mirror_screen.dart';
import 'package:todo/ui/settings_screen.dart';

import 'fake_note_repository.dart';
import 'fake_secure_storage.dart';

/// Stub file picker that returns a fixed in-memory file (no disk I/O, so the
/// `_import` flow stays timer-free and deterministic under the widget tester).
class _FakeFileSelector extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  _FakeFileSelector(this.file);
  final XFile? file;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => file;
}

/// Repository whose reads fail, to exercise the export error path.
class _ExplodingRepo extends FakeNoteRepository {
  @override
  Future<List<Note>> listNotes({
    NoteSort sort = NoteSort.modifiedDesc,
    NoteFilter filter = const NoteFilter(),
  }) async => throw Exception('db down');
}

/// File picker stub that throws, to exercise the import error path.
class _ThrowingFileSelector extends FileSelectorPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => throw Exception('picker blew up');
}

Future<FakeNoteRepository> pumpSettings(
  WidgetTester tester, {
  SyncSettings initial = const SyncSettings(
    owner: 'kuhyx',
    repo: 'syncs',
    token: 't',
  ),
  http.Client? httpClient,
  List<Note> seed = const [],
  FakeNoteRepository? repository,
  Future<FirebaseRestClient?> Function()? firebaseFactory,
  ValueNotifier<AppSettings>? appSettings,
  AnalyticsService? analytics,
}) async {
  SharedPreferences.setMockInitialValues({});
  installFakeSecureStorage();
  // Tall surface so the whole settings ListView builds and the pushed
  // Sync settings screen's Backup section (below the default 800×600
  // fold) isn't lazy-skipped.
  tester.view.physicalSize = const Size(1200, 2800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final repo = repository ?? FakeNoteRepository(seed);
  addTearDown(repo.close);
  await tester.pumpWidget(
    MaterialApp(
      home: SettingsScreen(
        initial: initial,
        repository: repo,
        appSettings:
            appSettings ??
            ValueNotifier(const AppSettings(advancedMode: false)),
        analytics: analytics,
        httpClient: httpClient,
        // Injected so the widget never reaches for the platform: the real
        // factory wants the OS keystore, which doesn't exist under
        // `flutter test`.
        firebaseFactory: firebaseFactory ?? () async => null,
        accountLoader: () async => null,
        sessionProbe: () async => false,
        stateStore: InMemorySyncStateStore(),
      ),
    ),
  );
  await tester.pump();
  return repo;
}
