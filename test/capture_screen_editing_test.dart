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
  testWidgets('defaults to Raw, with Guided available via the entry wizard', (
    tester,
  ) async {
    await pumpCapture(tester);

    // Defaults to Raw: a single text field, no note persisted yet.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Guided'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);

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

    await tester.tap(find.byTooltip('New note'));
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
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('the new-note action resets the template', (tester) async {
    final repo = await pumpCapture(tester);

    await tester.enterText(find.byType(TextField).first, 'A real idea');
    await tester.pump();
    await tester.tap(find.byTooltip('New note'));
    await tester.pump();

    expect(await repo.listNotes(), hasLength(1));
    // The editor reset to a fresh, empty Raw draft.
    expect(find.byType(TextField), findsOneWidget);
    final raw = tester.widget<TextField>(find.byType(TextField));
    expect(raw.controller!.text, isEmpty);
  });

  testWidgets('tapping Sync while unconfigured prompts to connect a backend', (
    tester,
  ) async {
    await pumpCapture(tester); // empty prefs → no token → not configured

    await tester.tap(find.byTooltip('Sync'));
    await tester.pump(); // settings load + snackbar
    await tester.pump();

    // The behaviour that matters is the routing, not the wording: an
    // unconfigured device is sent to settings to connect a backend. Asserting
    // on the snackbar text tied this to one phrasing, and the snackbar is
    // gone by the time settings has pushed anyway.
    expect(find.textContaining('Connect Firebase'), findsWidgets);
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
}
