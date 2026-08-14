import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/ui/markdown_view.dart';
import 'package:todo/ui/note_editor.dart';

import 'note_editor_harness.dart';

void main() {
  testWidgets('guided: typing the title emits an assembled # heading', (
    tester,
  ) async {
    final emitted = await pumpEditor(tester, initialTemplate: spec);

    expect(find.byTooltip('Exit guided'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Dark mode');
    await tester.pump();

    expect(emitted.last, startsWith('# Dark mode'));
  });

  testWidgets('step page Next/Back navigate and progress counter updates', (
    tester,
  ) async {
    await pumpEditor(tester, initialTemplate: spec);

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('1 / ${spec.sections.length}'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.text('2 / ${spec.sections.length}'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pump();
    expect(find.text('1 / ${spec.sections.length}'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('guided: the stepper walks the seven audited sections', (
    tester,
  ) async {
    // The user-visible contract of the 2026-07 template cut. Walks every step
    // and asserts the label and its guidance are the ones on screen, so a
    // section resurrected in note_template.dart cannot land unnoticed.
    await pumpEditor(tester, initialTemplate: spec);

    for (var i = 0; i < spec.sections.length; i++) {
      final section = spec.sections[i];
      expect(find.text('${i + 1} / ${spec.sections.length}'), findsOneWidget);
      expect(
        find.text(section.isTitle ? 'title' : section.label),
        findsWidgets,
        reason: 'step ${i + 1} should show "${section.label}"',
      );
      expect(find.text(section.helper), findsOneWidget);
      if (i < spec.sections.length - 1) {
        await tester.tap(find.text('Next'));
        await tester.pump();
      }
    }

    // The last step is `read first`; there is no Next past it.
    expect(spec.sections.last.label, 'read first');
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('pasting a bare link drops the draft to the blank template', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      initialTemplate: spec,
      initialMode: NoteEditorMode.raw,
    );
    expect(find.text('LLM design spec'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).first,
      'https://example.com/x',
    );
    await tester.pump();

    // Freeform now, so there is no seven-step stepper to walk for a link.
    expect(find.text('Blank'), findsOneWidget);
    expect(find.text('Guided'), findsNothing);

    // Adding prose puts the spec template back — lossless in both directions.
    await tester.enterText(
      find.byType(TextField).first,
      'https://example.com/x — port this to Dart',
    );
    await tester.pump();
    expect(find.text('LLM design spec'), findsOneWidget);
    expect(find.text('Guided'), findsOneWidget);
  });

  testWidgets('an explicit template choice survives further typing', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      initialTemplate: spec,
      initialMode: NoteEditorMode.raw,
    );

    await tester.tap(find.text('LLM design spec'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blank').last);
    await tester.pumpAndSettle();
    expect(find.text('Blank'), findsOneWidget);

    // Prose would normally re-select the spec template; an explicit pick wins.
    await tester.enterText(find.byType(TextField).first, 'build a thing');
    await tester.pump();
    expect(find.text('Blank'), findsOneWidget);
  });

  testWidgets('switching to View renders the note as Markdown', (tester) async {
    await pumpEditor(
      tester,
      initialTemplate: spec,
      initialMode: NoteEditorMode.raw,
    );
    await tester.enterText(find.byType(TextField).first, '# Render me');
    await tester.pump();

    await tester.tap(find.text('View'));
    await tester.pump();

    expect(find.byType(MarkdownView), findsOneWidget);
    expect(find.text('Render me'), findsOneWidget); // rendered heading text
  });
}
