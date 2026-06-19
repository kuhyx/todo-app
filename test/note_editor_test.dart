import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/ui/markdown_view.dart';
import 'package:todo/ui/note_editor.dart';

void main() {
  const spec = NoteTemplate.llmDesignSpec;
  const blank = NoteTemplate.blank;

  // Pumps an editor and exposes the latest text emitted via onChanged.
  Future<List<String>> pumpEditor(
    WidgetTester tester, {
    String initialText = '',
    NoteTemplate? initialTemplate,
    NoteEditorMode initialMode = NoteEditorMode.guided,
  }) async {
    final emitted = <String>[];
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteEditor(
            initialText: initialText,
            initialTemplate: initialTemplate,
            initialMode: initialMode,
            onChanged: emitted.add,
          ),
        ),
      ),
    );
    await tester.pump();
    return emitted;
  }

  testWidgets('guided: typing the title emits an assembled # heading', (
    tester,
  ) async {
    final emitted = await pumpEditor(tester, initialTemplate: spec);

    expect(find.text('Guided'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Dark mode');
    await tester.pump();

    expect(emitted.last, startsWith('# Dark mode'));
  });

  testWidgets('stepper Next/Back and tapping a step header navigate', (
    tester,
  ) async {
    await pumpEditor(tester, initialTemplate: spec);

    // A vertical Stepper keeps every step's controls in the tree (collapsed),
    // so the buttons resolve to many identical widgets — they all drive the
    // same shared continue/cancel callbacks, so tap the first.
    expect(find.byType(Stepper), findsOneWidget);
    // Only the current step's controls are hit-testable (others are collapsed
    // to zero height), so .hitTestable() resolves the single visible button.
    // Settle the expand/collapse animation so the next step's controls lay out.
    await tester.tap(find.text('Next').hitTestable()); // advance past the title
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back').hitTestable()); // and back
    await tester.pumpAndSettle();
    // Jump directly to a step by tapping its header. _goToStep delays past
    // the Stepper's own collapse/expand animation before scrolling, so drain
    // that timer rather than a bare pump — see CLAUDE.md's Timer pitfall.
    await tester.tap(find.text('done'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(Stepper), findsOneWidget);
  });

  testWidgets('switching to View renders the note as Markdown', (tester) async {
    await pumpEditor(tester, initialTemplate: spec);
    await tester.enterText(find.byType(TextField).first, 'Render me');
    await tester.pump();

    await tester.tap(find.text('View'));
    await tester.pump();

    expect(find.byType(MarkdownView), findsOneWidget);
    expect(find.text('Render me'), findsOneWidget); // rendered heading text
  });

  testWidgets('guided → Raw materialises the assembled text and edits emit', (
    tester,
  ) async {
    final emitted = await pumpEditor(tester, initialTemplate: spec);
    await tester.enterText(find.byType(TextField).first, 'T');
    await tester.pump();

    await tester.tap(find.text('Raw'));
    await tester.pump();

    final raw = tester.widget<TextField>(find.byType(TextField));
    expect(raw.controller!.text, startsWith('# T'));

    await tester.enterText(find.byType(TextField), '# T\n\n## what\nedited');
    await tester.pump();
    expect(emitted.last, contains('edited'));
  });

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
    expect(find.byType(Stepper), findsNothing); // still raw
  });

  testWidgets('guided → Raw → Guided round-trips when text still conforms', (
    tester,
  ) async {
    // Open guided from a conforming note (pre-fills the section controllers
    // without typing into collapsed steps), so the assembled body conforms.
    final conforming = assemble(spec, {'title': 'Keep', 'what': 'a body'});
    await pumpEditor(tester, initialTemplate: spec, initialText: conforming);
    expect(find.byType(Stepper), findsOneWidget);

    // guided → raw makes the (still conforming) body the source…
    await tester.tap(find.text('Raw'));
    await tester.pump();
    expect(find.byType(Stepper), findsNothing);

    // …then raw → guided re-parses the conforming body back into sections.
    await tester.tap(find.text('Guided'));
    await tester.pump();
    expect(find.byType(Stepper), findsOneWidget);
  });

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
    await pumpEditor(tester, initialTemplate: spec);
    expect(find.byType(Stepper), findsOneWidget);

    await tester.tap(find.text('LLM design spec').first); // open the menu
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blank').last);
    await tester.pumpAndSettle();

    // Freeform now: the stepper is gone and Guided is no longer offered.
    expect(find.byType(Stepper), findsNothing);
    expect(find.text('Guided'), findsNothing);
  });

  testWidgets('detects a conforming note (no template given) as guided', (
    tester,
  ) async {
    final conforming = assemble(spec, {'title': 'Detected', 'what': 'x'});
    await pumpEditor(tester, initialText: conforming);

    expect(find.byType(Stepper), findsOneWidget); // guided by default
    expect(find.text('Guided'), findsOneWidget);
  });

  testWidgets('detects a legacy note (no template given) as freeform raw', (
    tester,
  ) async {
    await pumpEditor(tester, initialText: 'old\n\nwhat — legacy');

    // Non-conforming → blank/raw, no guided stepper offered.
    expect(find.byType(Stepper), findsNothing);
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
    expect(find.byType(Stepper), findsNothing);
    final raw = tester.widget<TextField>(find.byType(TextField));
    expect(raw.controller!.text, 'cannot be guided');
  });
}
