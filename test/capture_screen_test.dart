import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/data/note.dart';
import 'package:todo/ui/capture_screen.dart';
import 'package:todo/ui/settings_screen.dart';

import 'fake_note_repository.dart';

void main() {
  // A real CRDT DB schedules sqflite timers that never drain under the
  // widget tester's fake clock, so these tests inject a timer-free fake.
  // (NOTE: avoid pumpAndSettle — the autofocused field's cursor blink never
  // settles; pump explicit frames instead.)
  Future<FakeNoteRepository> pumpCapture(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
    http.Client? httpClient,
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    // Tall surface so a pushed settings screen builds its whole ListView.
    tester.view.physicalSize = const Size(1200, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = FakeNoteRepository();
    addTearDown(repo.close);
    await tester.pumpWidget(
      MaterialApp(
        home: CaptureScreen(repository: repo, httpClient: httpClient),
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

  testWidgets('opens the guided editor with section guidance', (tester) async {
    await pumpCapture(tester);

    // The guided stepper shows the design-spec sections and the title step's
    // guidance, with no note persisted yet.
    expect(find.text('Guided'), findsOneWidget);
    expect(find.textContaining('imperative'), findsOneWidget); // title helper
    expect(find.text('what'), findsOneWidget); // a section step header
    expect(find.text('done'), findsOneWidget);
    expect(find.text('0 saved'), findsOneWidget);
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
    // The editor reset to a fresh guided template (title guidance shown again).
    expect(find.textContaining('imperative'), findsOneWidget);
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
    // Empty remote directory (404) → the service has nothing to merge and
    // pushes this device's own changeset (PUT).
    final mock = MockClient((req) async {
      if (req.method == 'PUT') return http.Response('{}', 200);
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

    expect(find.textContaining('Sync failed'), findsOneWidget);
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
  // 404 for the (empty) changeset listing, 200 for the device's own PUT.
  MockClient recordingMock(List<String> methods) => MockClient((req) async {
    methods.add(req.method);
    if (req.method == 'PUT') return http.Response('{}', 200);
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

    expect(methods, contains('PUT'));
  });

  testWidgets('auto-sync failure is silent (no snackbar)', (tester) async {
    final mock = MockClient((_) async => throw Exception('offline'));
    await pumpCapture(tester, prefs: configuredPrefs, httpClient: mock);
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Sync failed'), findsNothing);
    expect(find.textContaining('Synced'), findsNothing);
  });
}
