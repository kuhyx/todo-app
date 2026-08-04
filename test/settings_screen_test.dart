import 'dart:io';
import 'dart:convert';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/sync/backlog_export_io.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_repository.dart';
import 'package:todo/sync/notes_markdown.dart';
import 'package:todo/sync/sync_settings.dart';
import 'package:todo/ui/settings_screen.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

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
  }) async {
    SharedPreferences.setMockInitialValues({});
    installFakeSecureStorage();
    // Tall surface so the whole settings ListView builds (its Backup section
    // is below the default 800×600 fold and would otherwise be lazy-skipped).
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
          httpClient: httpClient,
          // Both injected so the widget never reaches for the platform: the
          // real factories want the OS keystore and an application-support
          // directory, neither of which exists under `flutter test`.
          firebaseFactory: () async => null,
          stateStore: InMemorySyncStateStore(),
        ),
      ),
    );
    await tester.pump();
    return repo;
  }

  testWidgets('renders sync fields and the backup actions', (tester) async {
    await pumpSettings(tester);
    expect(find.text('Connect GitHub'), findsOneWidget);
    expect(find.text('Export notes'), findsOneWidget);
    expect(find.text('Import notes'), findsOneWidget);
  });

  testWidgets('Connect GitHub without a client id shows guidance', (
    tester,
  ) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Connect GitHub'));
    await tester.pump();
    expect(
      find.textContaining('Enter the OAuth App client id'),
      findsOneWidget,
    );
  });

  testWidgets('Test connection reports a reachable repo', (tester) async {
    final mock = MockClient((_) async => http.Response('{}', 200));
    await pumpSettings(tester, httpClient: mock);

    await tester.tap(find.text('Advanced')); // Test connection lives here now
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test connection'));
    await tester.pump(); // start
    await tester.pump(); // resolve future + rebuild

    expect(find.textContaining('reachable'), findsOneWidget);
  });

  testWidgets('Test connection reports an inaccessible repo', (tester) async {
    final mock = MockClient((_) async => http.Response('', 404));
    await pumpSettings(tester, httpClient: mock);

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test connection'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Could not access'), findsOneWidget);
  });

  testWidgets('Test connection surfaces a network error', (tester) async {
    final mock = MockClient((_) async => throw Exception('offline'));
    await pumpSettings(tester, httpClient: mock);

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test connection'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Error:'), findsOneWidget);
  });

  testWidgets('device flow failure to start shows a message', (tester) async {
    final mock = MockClient((_) async => http.Response('nope', 422));
    await pumpSettings(
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

    await pumpSettings(
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

    await pumpSettings(
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

  test('the default export home is the real HOME', () {
    // Guards the production default, which every other test overrides so the
    // suite cannot write to the user's ~/todo.
    expect(resolveExportHome(), Platform.environment['HOME']);
  });

  testWidgets('Export notes writes the backlog file (desktop)', (tester) async {
    // Redirect HOME: this test does real file I/O, and without the override it
    // overwrites the user's canonical ~/todo/BACKLOG.md with the fake note
    // below on every test run.
    // Sync creation: awaiting real file I/O under the widget tester's fake
    // clock never completes.
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

    // _export does real file I/O on desktop, so drive it under runAsync.
    await tester.runAsync(() async {
      await tester.tap(find.text('Export notes'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(find.textContaining('Exported'), findsOneWidget);
  });

  testWidgets('Export surfaces a failure when the repository read fails', (
    tester,
  ) async {
    await pumpSettings(tester, repository: _ExplodingRepo());

    await tester.runAsync(() async {
      await tester.tap(find.text('Export notes'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    expect(find.textContaining('Export failed'), findsOneWidget);
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

    // Push Settings over a base route so _save's Navigator.pop has somewhere
    // to return to (popping the root route is a no-op and hides the result).
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<SyncSettings>(
                    builder: (_) => SettingsScreen(
                      initial: const SyncSettings(
                        owner: 'o',
                        repo: 'r',
                        token: 'tok',
                      ),
                      repository: repo,
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
    expect(find.text('Connect GitHub'), findsOneWidget); // settings is up

    await tester.tap(find.text('Save'));
    await tester.pump(); // run _save (persist + pop)
    await tester.pump(const Duration(milliseconds: 400)); // pop transition

    expect(find.text('open'), findsOneWidget); // back on the base route
    final saved = await SyncSettings.load();
    expect(saved.owner, 'o');
    expect(saved.token, 'tok');
  });

  testWidgets('Import notes reads the picked file and merges', (tester) async {
    // Round-trip a known note through the export format so the picked file is
    // valid input the importer can parse and merge.
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

    await tester.tap(find.text('Import notes'));
    await tester.pump(); // openFile resolves (in-memory)
    await tester.pump(); // read + parse + merge + setState

    expect(find.textContaining('Imported'), findsOneWidget);
    expect((await repo.listNotes()).single.text, 'an imported idea');
  });

  testWidgets('Import shows nothing when the picker is cancelled', (
    tester,
  ) async {
    FileSelectorPlatform.instance = _FakeFileSelector(null); // user cancels
    final repo = await pumpSettings(tester);

    await tester.tap(find.text('Import notes'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Imported'), findsNothing);
    expect(await repo.listNotes(), isEmpty);
  });

  testWidgets('Import surfaces a failure from the picker', (tester) async {
    FileSelectorPlatform.instance = _ThrowingFileSelector();
    final repo = await pumpSettings(tester);

    await tester.tap(find.text('Import notes'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Import failed'), findsOneWidget);
    expect(await repo.listNotes(), isEmpty);
  });

  testWidgets('device dialog: failed poll shows the error and Open launches', (
    tester,
  ) async {
    final launcher = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = launcher;

    // _openPage copies the code to the clipboard first; there's no clipboard
    // plugin in the test host, so stub the channel to succeed.
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

    await pumpSettings(
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
    // launchUrl; pumpAndSettle drains them (no spinner is animating now that
    // the error is shown, so it settles).
    await tester.tap(find.byIcon(Icons.open_in_new));
    await tester.pumpAndSettle();
    expect(launcher.launched, 'https://github.com/login/device');

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle(); // finish the dialog pop animation
    expect(find.text('WXYZ-1234'), findsNothing); // dialog dismissed
  });
}
