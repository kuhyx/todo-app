import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/ui/markdown_view.dart';
import 'package:todo/ui/note_editor.dart';

import 'note_editor_harness.dart';

void main() {
  testWidgets(
    'bare Guided back arrow returns to Raw, materialising the assembled text',
    (tester) async {
      final emitted = await pumpEditor(tester, initialTemplate: spec);
      await tester.enterText(find.byType(TextField).first, 'T');
      await tester.pump();

      await tester.tap(find.byTooltip('Exit guided'));
      await tester.pump();

      final raw = tester.widget<TextField>(find.byType(TextField));
      expect(raw.controller!.text, startsWith('# T'));

      await tester.enterText(find.byType(TextField), '# T\n\n## what\nedited');
      await tester.pump();
      expect(emitted.last, contains('edited'));
    },
  );

  testWidgets('Raw → Guided is blocked with a snackbar when non-conforming', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      initialTemplate: spec,
      initialText: 'totally freeform text',
      initialMode: NoteEditorMode.raw,
    );

    // Structured template + non-conforming raw text → switching is refused.
    await tester.tap(find.text('Guided'));
    await tester.pump();

    expect(find.textContaining("doesn't match the template"), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing); // still raw
  });

  testWidgets(
    'guided → Raw → Guided round-trips (skipping the wizard) when text still conforms',
    (tester) async {
      // Open guided from a conforming note (pre-fills the section controllers
      // without typing into collapsed steps), so the assembled body conforms.
      final conforming = assemble(spec, {'title': 'Keep', 'what': 'a body'});
      await pumpEditor(tester, initialTemplate: spec, initialText: conforming);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Bare guided -> raw via the back arrow makes the (still conforming)
      // body the source…
      await tester.tap(find.byTooltip('Exit guided'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);

      // …then raw -> guided re-parses the conforming body straight back into
      // the bare stepper — no wizard, since the content isn't empty.
      await tester.tap(find.text('Guided'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Step 1 of 2'), findsNothing); // wizard was skipped
    },
  );

  testWidgets('freeform template offers only View and Raw', (tester) async {
    final emitted = await pumpEditor(tester, initialTemplate: blank);

    expect(find.text('Guided'), findsNothing);
    expect(find.text('View'), findsOneWidget);
    expect(find.text('Raw'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'free text');
    await tester.pump();
    expect(emitted.last, 'free text');
  });

  testWidgets('switching template via the dropdown reloads the source', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      initialTemplate: spec,
      initialMode: NoteEditorMode.raw,
    );
    expect(find.text('Guided'), findsOneWidget); // structured: Guided offered

    await tester.tap(find.text('LLM design spec').first); // open the menu
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blank').last);
    await tester.pumpAndSettle();

    // Freeform now: Guided is no longer offered.
    expect(find.text('Guided'), findsNothing);
  });

  testWidgets('detects a conforming note (no template given) as guided', (
    tester,
  ) async {
    final conforming = assemble(spec, {'title': 'Detected', 'what': 'x'});
    await pumpEditor(tester, initialText: conforming);

    expect(
      find.byType(LinearProgressIndicator),
      findsOneWidget,
    ); // guided by default
    expect(find.byTooltip('Exit guided'), findsOneWidget);
  });

  testWidgets('detects a legacy note (no template given) as freeform raw', (
    tester,
  ) async {
    await pumpEditor(tester, initialText: 'old\n\nwhat — legacy');

    // Non-conforming → blank/raw, no guided stepper offered.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Guided'), findsNothing);
  });

  testWidgets('initialMode preview opens directly in the rendered view', (
    tester,
  ) async {
    final conforming = assemble(spec, {'title': 'Preview me'});
    await pumpEditor(
      tester,
      initialText: conforming,
      initialMode: NoteEditorMode.preview,
    );

    expect(find.byType(MarkdownView), findsOneWidget);
    expect(find.text('Preview me'), findsOneWidget);
  });

  testWidgets('Preview → Raw materialises the still-guided source', (
    tester,
  ) async {
    final conforming = assemble(spec, {'title': 'Preview src', 'what': 'x'});
    await pumpEditor(
      tester,
      initialText: conforming,
      initialMode: NoteEditorMode.preview,
    );

    await tester.tap(find.text('Raw'));
    await tester.pump();

    final raw = tester.widget<TextField>(find.byType(TextField));
    expect(raw.controller!.text, contains('Preview src'));
  });

  testWidgets('initialMode guided falls back to Raw for non-conforming text', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      initialTemplate: spec,
      initialText: 'cannot be guided',
      initialMode: NoteEditorMode.guided,
    );

    // Guided was requested but the text does not conform → opened in Raw.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    final raw = tester.widget<TextField>(find.byType(TextField));
    expect(raw.controller!.text, 'cannot be guided');
  });
}
