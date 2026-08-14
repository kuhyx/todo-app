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
    'auto-sync success shows no status text — sync is automatic and silent',
    (tester) async {
      final methods = <String>[];
      await pumpCapture(
        tester,
        prefs: configuredPrefs,
        httpClient: recordingMock(methods),
      );
      await tester.pump();
      await tester.pump();

      // Only a failure is worth surfacing; a routine success is silent.
      expect(find.textContaining('Synced at'), findsNothing);
      expect(find.textContaining('merged 0 device(s)'), findsNothing);
    },
  );

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
