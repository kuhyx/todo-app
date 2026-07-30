import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/ui/confirm.dart';

/// Tests for the destructive-action confirmation.
///
/// Both delete paths (the actions sheet and the detail screen) used to delete
/// immediately with no confirmation and no undo. With a keyboard that is one
/// Tab away from a Return the user was about to press anyway, so the defaults
/// here — Cancel autofocused, Escape dismisses — are the actual safety
/// property, not decoration.
void main() {
  Future<bool?> showFor(WidgetTester tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await confirmDestructive(
                  context,
                  title: 'Delete note?',
                  message: 'This cannot be undone.',
                );
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('shows the title and message', (tester) async {
    await showFor(tester);
    expect(find.text('Delete note?'), findsOneWidget);
    expect(find.text('This cannot be undone.'), findsOneWidget);
  });

  testWidgets('Cancel is autofocused so a reflexive Return is safe', (
    tester,
  ) async {
    await showFor(tester);
    final cancel = tester.widget<TextButton>(
      find.ancestor(of: find.text('Cancel'), matching: find.byType(TextButton)),
    );
    expect(cancel.autofocus, isTrue);
  });

  testWidgets('confirming returns true', (tester) async {
    await showFor(tester);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete note?'), findsNothing);
  });

  testWidgets('cancelling returns false', (tester) async {
    await showFor(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Delete note?'), findsNothing);
  });

  testWidgets('Escape dismisses without confirming', (tester) async {
    await showFor(tester);
    expect(find.text('Delete note?'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    // A confirmation the keyboard cannot back out of is worse than none.
    expect(find.text('Delete note?'), findsNothing);
  });

  testWidgets('custom labels are honoured', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => confirmDestructive(
                context,
                title: 'Discard?',
                message: 'Unsaved work will be lost.',
                confirmLabel: 'Discard',
                cancelLabel: 'Keep editing',
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('Discard'), findsOneWidget);
    expect(find.text('Keep editing'), findsOneWidget);
  });
}
