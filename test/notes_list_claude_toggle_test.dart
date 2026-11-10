// Claude-made notes: hidden by default, an eye toggle shows them, the choice
// is remembered per device, and human notes always sort first.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo/data/app_settings.dart';
import 'package:todo/data/note.dart';
import 'package:todo/ui/notes_list_screen.dart';

import 'fake_note_repository.dart';
import 'notes_list_harness.dart';

final _seed = [
  note(
    'c',
    'Claude chore',
    priority: Priority.high,
  ).copyWith(createdBy: 'claude'),
  note('h', 'Human idea', priority: Priority.low).copyWith(createdBy: 'kuhy'),
  note('l', 'Legacy idea'),
];

Future<ValueNotifier<AppSettings>> _pump(
  WidgetTester tester, {
  AppSettings settings = const AppSettings(advancedMode: true),
}) async {
  final repo = FakeNoteRepository(_seed, true);
  addTearDown(repo.close);
  final notifier = ValueNotifier(settings);
  addTearDown(notifier.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: NotesListScreen(repository: repo, appSettings: notifier),
    ),
  );
  await tester.pump();
  return notifier;
}

Future<void> _tap(WidgetTester tester, IconData icon) async {
  await tester.tap(find.byIcon(icon));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Claude-made notes are hidden until the eye is tapped', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Claude chore'), findsNothing);
    expect(find.text('Human idea'), findsOneWidget);
    expect(find.text('Legacy idea'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);

    await _tap(tester, Icons.visibility_off);
    expect(find.text('Claude chore'), findsOneWidget);
    expect(find.byIcon(Icons.visibility), findsOneWidget);

    await _tap(tester, Icons.visibility);
    expect(find.text('Claude chore'), findsNothing);
  });

  testWidgets('shown, Claude notes sort below every human note', (
    tester,
  ) async {
    await _pump(
      tester,
      settings: const AppSettings(advancedMode: true, showClaudeNotes: true),
    );
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    // The default 800x600 view lists one note per row, in display order; the
    // high-priority Claude note still comes last.
    expect(y('Claude chore'), greaterThan(y('Human idea')));
    expect(y('Claude chore'), greaterThan(y('Legacy idea')));
  });

  testWidgets('the choice is persisted per device and reloaded', (
    tester,
  ) async {
    final notifier = await _pump(tester);
    await _tap(tester, Icons.visibility_off);
    expect(notifier.value.showClaudeNotes, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('app.showClaudeNotes'), isTrue);
    expect((await AppSettings.load()).showClaudeNotes, isTrue);
  });

  test('advancedMode and the toggle do not overwrite each other', () async {
    final shown = await const AppSettings(
      advancedMode: false,
    ).withShowClaudeNotes(value: true);
    expect(shown.advancedMode, isFalse);
    final both = await shown.withAdvancedMode(value: true);
    expect(both.showClaudeNotes, isTrue);
    expect(both.advancedMode, isTrue);
  });
}
