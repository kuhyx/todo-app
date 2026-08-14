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

import 'settings_screen_harness.dart';

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

void main() {
  testWidgets(
    'Enable advanced toggles and persists locally with no client',
    (tester) async {
      final appSettings = ValueNotifier(
        const AppSettings(advancedMode: false),
      );
      await pumpSettings(
        tester,
        appSettings: appSettings,
        firebaseFactory: () async => null,
      );

      await tester.tap(find.text('Enable advanced'));
      await tester.pump();

      expect(appSettings.value.advancedMode, isTrue);
      final reloaded = await AppSettings.load();
      expect(reloaded.advancedMode, isTrue);
    },
  );

  testWidgets('Enable advanced mirrors the toggle to Firebase', (
    tester,
  ) async {
    String? putPath;
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
        if (request.method == 'PATCH') putPath = request.url.path;
        return http.Response(request.body, 200);
      }),
    );
    final appSettings = ValueNotifier(const AppSettings(advancedMode: false));
    await pumpSettings(
      tester,
      appSettings: appSettings,
      firebaseFactory: () async => firebase,
    );

    await tester.tap(find.text('Enable advanced'));
    await tester.pump();

    expect(appSettings.value.advancedMode, isTrue);
    expect(putPath, '/settings/advancedMode.json');
  });

  testWidgets(
    'Enable advanced still persists locally when opening Firebase throws',
    (tester) async {
      final appSettings = ValueNotifier(
        const AppSettings(advancedMode: false),
      );
      await pumpSettings(
        tester,
        appSettings: appSettings,
        firebaseFactory: () async => throw FirebaseAuthError('wrong account'),
      );

      await tester.tap(find.text('Enable advanced'));
      await tester.pump();

      // A signed-in-as-wrong-account device must not lose the local toggle.
      expect(appSettings.value.advancedMode, isTrue);
    },
  );

  testWidgets('Enable advanced logs a settings_toggle event', (
    tester,
  ) async {
    const analytics = AnalyticsService(nodeId: 'device-a');
    final appSettings = ValueNotifier(const AppSettings(advancedMode: false));
    await pumpSettings(
      tester,
      appSettings: appSettings,
      analytics: analytics,
      firebaseFactory: () async => null,
    );

    await tester.tap(find.text('Enable advanced'));
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('analytics.buffer'), contains('settings_toggle'));
  });

  testWidgets('renders the two sync links and no inline sync fields', (
    tester,
  ) async {
    await pumpSettings(tester);
    // The slim screen only links out; neither sync surface's own widgets
    // should be inlined here anymore.
    expect(find.text('Sync settings'), findsOneWidget);
    expect(find.text('Advanced sync (GitHub)'), findsOneWidget);
    expect(find.text('Connect GitHub'), findsNothing);
    expect(find.text('Sign in with Google'), findsNothing);
  });

  testWidgets('Tapping "Sync settings" navigates to SyncSettingsScreen', (
    tester,
  ) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Sync settings'));
    await tester.pumpAndSettle();

    expect(find.byType(SyncSettingsScreen), findsOneWidget);
  });

  testWidgets(
    'Tapping "Advanced sync (GitHub)" navigates to GitHubMirrorScreen with '
    'the right params',
    (tester) async {
      const initial = SyncSettings(owner: 'o', repo: 'r', token: 'tok');
      final repo = await pumpSettings(tester, initial: initial);

      await tester.tap(find.text('Advanced sync (GitHub)'));
      await tester.pumpAndSettle();

      expect(find.byType(GitHubMirrorScreen), findsOneWidget);
      final screen = tester.widget<GitHubMirrorScreen>(
        find.byType(GitHubMirrorScreen),
      );
      // Prove the hand-off actually carries the right values, not just that
      // the right widget type appears — a dropped constructor arg is the
      // failure mode a screen split like this one actually produces.
      expect(screen.initial, initial);
      expect(screen.repository, repo);
    },
  );

  test('the default export home is the real HOME', () {
    // Guards the production default, which every other test overrides so the
    // suite cannot write to the user's ~/todo.
    expect(resolveExportHome(), Platform.environment['HOME']);
  });
}
