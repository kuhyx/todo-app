import 'dart:convert';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/sync/local_backup.dart';
import 'package:todo/sync/notes_markdown.dart';
import 'package:todo/ui/capture_screen.dart';
import 'package:todo/ui/settings_screen.dart';

import 'fake_note_repository.dart';
import 'fake_secure_storage.dart';

void main() {
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

  testWidgets('defaults to Raw, with Guided available via the entry wizard', (
    tester,
  ) async {
    await pumpCapture(tester);

    // Defaults to Raw: a single text field, no note persisted yet.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Guided'), findsOneWidget);
    expect(find.text('0 saved'), findsOneWidget);

    // Tapping Guided on the empty draft opens the priority+template wizard
    // rather than jumping straight into the stepper.
    await tester.tap(find.text('Guided'));
    await tester.pump();
    expect(find.text('Step 1 of 2'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.tap(find.text('Start'));
    await tester.pump();

    // Now on step 1 of the full-screen step page.
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      find.text('1 / ${NoteTemplate.llmDesignSpec.sections.length}'),
      findsOneWidget,
    );
    expect(find.textContaining('imperative'), findsOneWidget); // title helper
  });

  testWidgets('saving the untouched template creates no note', (tester) async {
    final repo = await pumpCapture(tester);

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(await repo.listNotes(), isEmpty);
  });

  testWidgets('typing into the template persists a note with defaults', (
    tester,
  ) async {
    final repo = await pumpCapture(tester);

    // The first field in the guided stepper is the title section.
    await tester.enterText(find.byType(TextField).first, 'My idea');
    await tester.pump();

    final notes = await repo.listNotes();
    expect(notes, hasLength(1));
    expect(notes.single.text, contains('My idea'));
    expect(notes.single.priority, Priority.medium);
    expect(notes.single.status, Status.todo);
    expect(find.text('1 saved'), findsOneWidget);
  });

  testWidgets('save after editing shows a snackbar and resets the template', (
    tester,
  ) async {
    final repo = await pumpCapture(tester);

    await tester.enterText(find.byType(TextField).first, 'A real idea');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump(); // build the snackbar

    expect(find.text('Idea saved locally'), findsOneWidget);
    await tester.pump();

    expect(await repo.listNotes(), hasLength(1));
    // The editor reset to a fresh, empty Raw draft.
    expect(find.byType(TextField), findsOneWidget);
    final raw = tester.widget<TextField>(find.byType(TextField));
    expect(raw.controller!.text, isEmpty);
  });

  testWidgets('tapping Sync while unconfigured prompts for a token', (
    tester,
  ) async {
    await pumpCapture(tester); // empty prefs → no token → not configured

    await tester.tap(find.byTooltip('Sync'));
    await tester.pump(); // settings load + snackbar
    await tester.pump();

    expect(find.textContaining('Add a GitHub token'), findsOneWidget);
  });

  testWidgets('the notes-list button navigates to the list screen', (
    tester,
  ) async {
    await pumpCapture(tester);

    await tester.tap(find.byTooltip('Notes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // route transition

    expect(find.text('Notes'), findsOneWidget); // list screen app bar title
  });

  testWidgets('changing the priority dropdown updates the saved note', (
    tester,
  ) async {
    final repo = await pumpCapture(tester);

    await tester.enterText(find.byType(TextField).first, 'Prioritised idea');
    await tester.pump();

    await tester.tap(
      find.byWidgetPredicate((w) => w is DropdownButton<Priority>),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // menu open
    await tester.tap(find.text('High').last);
    await tester.pump();

    expect((await repo.listNotes()).single.priority, Priority.high);
  });

  testWidgets('changing the status dropdown updates the saved note', (
    tester,
  ) async {
    final repo = await pumpCapture(tester);

    await tester.enterText(find.byType(TextField).first, 'Status idea');
    await tester.pump();

    await tester.tap(
      find.byWidgetPredicate((w) => w is DropdownButton<Status>),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // menu open
    await tester.tap(find.text('In progress').last);
    await tester.pump();

    expect((await repo.listNotes()).single.status, Status.inProgress);
  });

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

    expect(find.textContaining('Synced: merged 0 device'), findsOneWidget);
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

    await tester.tap(find.byTooltip('Sync settings'));
    await tester.pumpAndSettle(); // route transition
    expect(find.text('Connect GitHub'), findsOneWidget); // settings is up

    // Saving pops a SyncSettings back to the capture screen (covers the
    // result-adoption branch in _openSettings). Scope to the settings route —
    // the capture screen's own "Save" is still mounted behind it.
    await tester.tap(
      find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.text('Save'),
      ),
    );
    await tester.pumpAndSettle(); // save + pop transition

    expect(find.text('Connect GitHub'), findsNothing); // back on capture
    expect(find.byTooltip('Sync settings'), findsOneWidget);
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

  testWidgets('auto-sync success shows when and what was merged', (
    tester,
  ) async {
    final methods = <String>[];
    await pumpCapture(
      tester,
      prefs: configuredPrefs,
      httpClient: recordingMock(methods),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Synced at'), findsOneWidget);
    expect(find.textContaining('merged 0 device(s)'), findsOneWidget);
  });

  testWidgets('restores the last sync outcome on launch', (tester) async {
    // Unconfigured (no token) so no launch auto-sync overwrites the restored
    // status. A failure recorded on a previous run must still be visible.
    await pumpCapture(
      tester,
      prefs: {
        'sync.lastTime': DateTime(2026, 7, 16, 12).toIso8601String(),
        'sync.lastOk': false,
        'sync.lastDetail': 'Exception: rate limited',
      },
    );
    await tester.pump();

    expect(find.textContaining('Sync failed at 12:00:00'), findsOneWidget);
    expect(find.textContaining('rate limited'), findsOneWidget);
  });

  testWidgets('losing focus triggers a debounced auto-sync', (tester) async {
    final methods = <String>[];
    await pumpCapture(
      tester,
      prefs: configuredPrefs,
      httpClient: recordingMock(methods),
    );
    await tester.pump();
    await tester.pump();
    methods.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    // A second signal (hidden also counts as focus loss) resets the debounce
    // instead of double-firing.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump(
      CaptureScreen.autoSyncDebounce - const Duration(seconds: 1),
    );
    expect(methods, isEmpty); // still inside the debounce window

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();

    // A sync ran. Not `contains('PUT')`: the first sync above already pushed
    // this log, so revision tracking correctly suppresses the second, unchanged
    // push -- that suppression is the point of the revision cache.
    expect(methods, isNotEmpty);
  });

  testWidgets('recovers notes from the local backup into an empty DB', (
    tester,
  ) async {
    final markdown = NotesMarkdown.export([
      Note(
        id: 'r1',
        text: '# Recovered idea',
        priority: Priority.medium,
        status: Status.todo,
        createdAt: DateTime(2026, 6, 15),
        updatedAt: DateTime(2026, 6, 15),
      ),
    ]);
    final backup = LocalBackup(
      fetch: () async => const <Note>[],
      reader: () async => markdown,
      writer: (_) async {},
      debounce: Duration.zero,
    );

    final repo = await pumpCapture(tester, localBackup: backup);
    await tester.pump(); // recover → import

    final notes = await repo.listNotes();
    expect(notes, hasLength(1));
    expect(notes.single.text, contains('Recovered idea'));
  });

  testWidgets('does not recover when the DB already has notes', (tester) async {
    final backup = LocalBackup(
      fetch: () async => const <Note>[],
      reader: () async => NotesMarkdown.export([
        Note(
          id: 'r1',
          text: '# From backup',
          priority: Priority.medium,
          status: Status.todo,
          createdAt: DateTime(2026, 6, 15),
          updatedAt: DateTime(2026, 6, 15),
        ),
      ]),
      writer: (_) async {},
      debounce: Duration.zero,
    );
    final seeded = Note(
      id: 'local',
      text: '# Existing',
      priority: Priority.medium,
      status: Status.todo,
      createdAt: DateTime(2026, 6, 15),
      updatedAt: DateTime(2026, 6, 15),
    );

    final repo = await pumpCapture(tester, seed: [seeded], localBackup: backup);
    await tester.pump();

    // The backup is ignored because the DB was not empty.
    final notes = await repo.listNotes();
    expect(notes, hasLength(1));
    expect(notes.single.id, 'local');
  });

  testWidgets('writes the local backup as notes change', (tester) async {
    final writes = <String>[];
    final repo = FakeNoteRepository();
    // fetch pulls from the repo on write, mirroring production wiring.
    final backup = LocalBackup(
      fetch: repo.listNotes,
      reader: () async => null,
      writer: (md) async => writes.add(md),
      debounce: Duration.zero,
    );

    await pumpCapture(tester, repository: repo, localBackup: backup);
    await tester.enterText(find.byType(TextField).first, 'Backed up idea');
    await tester
        .pump(); // let the change tick → schedule → async fetch/write run

    expect(writes, isNotEmpty);
    expect(writes.last, contains('Backed up idea'));
  });
}
