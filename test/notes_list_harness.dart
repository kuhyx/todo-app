/// The shared pumpList harness and its fixed-clock note fixture.
///
/// Shared by the files `notes_list_screen_test.dart` was split into for the
/// 250-line cap. Deliberately NOT named `*_test.dart`: the runner would
/// collect it and fail on the missing `main()`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note.dart';
import 'package:todo/ui/notes_list_screen.dart';

import 'fake_note_repository.dart';

Note note(
  String id,
  String text, {
  Priority priority = Priority.medium,
  Status status = Status.todo,
}) {
  final now = DateTime(2026, 6, 15, 9);
  return Note(
    id: id,
    text: text,
    priority: priority,
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

Future<FakeNoteRepository> pumpList(
  WidgetTester tester, {
  List<Note> seed = const [],
  bool advancedMode = true,
}) async {
  final repo = FakeNoteRepository(seed);
  addTearDown(repo.close);
  final settings = ValueNotifier(AppSettings(advancedMode: advancedMode));
  addTearDown(settings.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: NotesListScreen(repository: repo, appSettings: settings),
    ),
  );
  await tester.pump(); // flush the initial stream emit
  return repo;
}

/// Taps the filter sheet's Apply button. It is the last item of a scrollable
/// sheet, so on a short viewport it legitimately sits below the fold:
/// scroll it into view first, as a user would.
Future<void> tapApply(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Apply'));
  await tester.pump();
  await tester.tap(find.text('Apply'));
}
