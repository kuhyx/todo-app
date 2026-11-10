// A note typed into the app is stamped created_by kuhy.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'capture_screen_harness.dart';

void main() {
  testWidgets('a captured note is stamped kuhy and keeps it on edit', (
    tester,
  ) async {
    final repo = await pumpCapture(tester);
    await tester.enterText(find.byType(TextField).first, 'First line');
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'First line, more');
    await tester.pump();

    final saved = (await repo.listNotes()).single;
    expect(saved.text, 'First line, more');
    expect(saved.createdBy, 'kuhy');
  });
}
