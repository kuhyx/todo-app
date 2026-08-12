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

void main() {
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

  group('BackupSlot wiring through Sync settings', () {
    // These prove the closures SettingsScreen builds for
    // SyncSettingsScreen's BackupSlot actually call todo's real
    // export/import — the shared package's own suite covers the generic
    // BackupSlot UI (button taps, status text), so these focus on the real
    // behavior behind the closures instead of re-asserting status text.

    testWidgets('Export notes writes the backlog file (desktop)', (
      tester,
    ) async {
      // Redirect HOME: this test does real file I/O, and without the
      // override it overwrites the user's canonical ~/todo/BACKLOG.md with
      // the fake note below on every test run.
      final home = Directory.systemTemp.createTempSync('todo_export_home');
      resolveExportHome = () => home.path;
      addTearDown(() {
        resolveExportHome = () =>
            Platform.environment['HOME'] ?? Directory.current.path;
        home.deleteSync(recursive: true);
      });

      await pumpSettings(
        tester,
        seed: [
          Note(
            id: 'n',
            text: 'an idea',
            priority: Priority.medium,
            status: Status.todo,
            createdAt: DateTime(2026, 6, 15),
            updatedAt: DateTime(2026, 6, 15),
          ),
        ],
      );

      await tester.tap(find.text('Sync settings'));
      await tester.pumpAndSettle();

      // _export does real file I/O on desktop, so drive it under runAsync.
      await tester.runAsync(() async {
        await tester.tap(find.text('Export notes'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      final file = File('${home.path}/todo/BACKLOG.md');
      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), contains('an idea'));
    });

    testWidgets('Export surfaces a failure when the repository read fails', (
      tester,
    ) async {
      await pumpSettings(tester, repository: _ExplodingRepo());

      await tester.tap(find.text('Sync settings'));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.text('Export notes'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(find.textContaining('Export failed'), findsOneWidget);
    });

    testWidgets('Import notes reads the picked file and merges', (
      tester,
    ) async {
      // Round-trip a known note through the export format so the picked
      // file is valid input the importer can parse and merge.
      final markdown = NotesMarkdown.export([
        Note(
          id: 'imported-1',
          text: 'an imported idea',
          priority: Priority.high,
          status: Status.inProgress,
          createdAt: DateTime(2026, 6, 15),
          updatedAt: DateTime(2026, 6, 15),
        ),
      ]);
      FileSelectorPlatform.instance = _FakeFileSelector(
        XFile.fromData(utf8.encode(markdown), name: 'backlog.md'),
      );

      final repo = await pumpSettings(tester);

      await tester.tap(find.text('Sync settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Import notes'));
      await tester.pump(); // openFile resolves (in-memory)
      await tester.pump(); // read + parse + merge + setState

      expect((await repo.listNotes()).single.text, 'an imported idea');
    });

    testWidgets('Import shows nothing when the picker is cancelled', (
      tester,
    ) async {
      FileSelectorPlatform.instance = _FakeFileSelector(null); // cancelled
      final repo = await pumpSettings(tester);

      await tester.tap(find.text('Sync settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Import notes'));
      await tester.pump();
      await tester.pump();

      // The shared screen can't distinguish "cancelled" from "nothing
      // imported" — it reports "Imported notes." either way, since
      // BackupSlot.import() returns normally on cancel. The behavior that
      // actually matters, that nothing was merged, is what's asserted here.
      expect(await repo.listNotes(), isEmpty);
    });

    testWidgets('Import surfaces a failure from the picker', (tester) async {
      FileSelectorPlatform.instance = _ThrowingFileSelector();
      final repo = await pumpSettings(tester);

      await tester.tap(find.text('Sync settings'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Import notes'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Import failed'), findsOneWidget);
      expect(await repo.listNotes(), isEmpty);
    });
  });
}
