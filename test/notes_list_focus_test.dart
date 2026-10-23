import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:todo/ui/note_detail_screen.dart';

import 'notes_list_harness.dart';

/// Whether any text field holds focus, i.e. Android would show the keyboard.
bool textFieldFocused() =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<EditableText>() !=
    null;

/// Opens the first note, types into its editor, then backs out the way the
/// Android back swipe does (a system pop, not the app-bar arrow).
Future<void> editNoteAndSwipeBack(WidgetTester tester) async {
  await tester.tap(find.text('Buy milk'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(
    find
        .descendant(
          of: find.byType(NoteDetailScreen),
          matching: find.byType(EditableText),
        )
        .first,
  );
  await tester.pump();
  expect(textFieldFocused(), isTrue);
  await tester.binding.handlePopRoute();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('backing out of a note leaves no text field focused', (
    tester,
  ) async {
    await pumpList(tester, seed: [note('a', 'Buy milk')]);
    await editNoteAndSwipeBack(tester);
    expect(find.text('Search notes…'), findsOneWidget);
    expect(textFieldFocused(), isFalse);
  });

  testWidgets('backing out does not re-focus a search box used earlier', (
    tester,
  ) async {
    await pumpList(tester, seed: [note('a', 'Buy milk')]);
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await editNoteAndSwipeBack(tester);
    expect(find.text('Search notes…'), findsOneWidget);
    expect(textFieldFocused(), isFalse);
  });
}
