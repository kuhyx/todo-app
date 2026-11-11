import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/ui/confirm_delete.dart';

/// Opens the dialog and returns a getter for its eventual answer.
Future<bool? Function()> _open(WidgetTester tester) async {
  bool? answer;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => answer = await confirmDeleteNote(context),
            child: const SizedBox.square(dimension: 40),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byType(TextButton));
  await tester.pumpAndSettle();
  return () => answer;
}

void main() {
  testWidgets('the delete glyph answers yes', (tester) async {
    final answer = await _open(tester);
    expect(find.bySemanticsLabel('Delete note?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-delete')));
    await tester.pumpAndSettle();
    expect(answer(), isTrue);
  });

  testWidgets('cancel is autofocused, so Return keeps the note', (
    tester,
  ) async {
    final answer = await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(answer(), isFalse);
  });

  testWidgets('Escape answers no', (tester) async {
    final answer = await _open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(answer(), isFalse);
  });

  testWidgets('tapping the barrier answers no', (tester) async {
    final answer = await _open(tester);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(answer(), isFalse);
  });
}
