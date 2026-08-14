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
