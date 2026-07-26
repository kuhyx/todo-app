import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
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
    Priority priority = Priority.defaultValue,
    ValueChanged<Priority>? onPriorityChanged,
    ValueChanged<bool>? onChromeVisibleChanged,
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
            priority: priority,
            onPriorityChanged: onPriorityChanged ?? (_) {},
            onChromeVisibleChanged: onChromeVisibleChanged ?? (_) {},
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

  testWidgets(
    'tapping Guided on an empty draft opens the priority+template wizard',
    (tester) async {
      await pumpEditor(
        tester,
        initialTemplate: spec,
        initialMode: NoteEditorMode.raw,
      );

      await tester.tap(find.text('Guided'));
      await tester.pump();

      expect(find.text('Step 1 of 2'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<Priority>), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets(
    'the wizard Next/Back moves between priority and template steps',
    (tester) async {
      await pumpEditor(
        tester,
        initialTemplate: spec,
        initialMode: NoteEditorMode.raw,
      );
      await tester.tap(find.text('Guided'));
      await tester.pump();

      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.text('Step 2 of 2'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);

      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(find.text('Step 1 of 2'), findsOneWidget);
    },
  );

  testWidgets('the wizard template step only offers structured templates', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      initialTemplate: spec,
      initialMode: NoteEditorMode.raw,
    );
    await tester.tap(find.text('Guided'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();

    await tester.tap(find.text('LLM design spec').first); // open the menu
    await tester.pumpAndSettle();
    expect(find.text('Blank'), findsNothing);

    // Select the (only) offered template, exercising the dropdown's onChanged.
    await tester.tap(find.text('LLM design spec').last);
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 2'), findsOneWidget);
  });

  testWidgets(
    'wizard Start commits the chosen priority and enters the bare stepper',
    (tester) async {
      Priority? committed;
      await pumpEditor(
        tester,
        initialTemplate: spec,
        initialMode: NoteEditorMode.raw,
        onPriorityChanged: (p) => committed = p,
      );
      await tester.tap(find.text('Guided'));
      await tester.pump();

      await tester.tap(find.byType(DropdownButtonFormField<Priority>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('High').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next'));
      await tester.pump();
      await tester.tap(find.text('Start'));
      await tester.pump();

      expect(committed, Priority.high);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byTooltip('Exit guided'), findsOneWidget);
    },
  );

  testWidgets('wizard Cancel returns to Raw with the chrome restored', (
    tester,
  ) async {
    final chromeVisible = <bool>[];
    await pumpEditor(
      tester,
      initialTemplate: spec,
      initialMode: NoteEditorMode.raw,
      onChromeVisibleChanged: chromeVisible.add,
    );
    await tester.tap(find.text('Guided'));
    await tester.pump();
    expect(chromeVisible.last, false);

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();

    expect(chromeVisible.last, true);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('Raw'), findsOneWidget); // chrome's mode selector is back
  });

  testWidgets('exiting bare Guided via the back arrow restores the chrome', (
    tester,
  ) async {
    final chromeVisible = <bool>[];
    final conforming = assemble(spec, {'title': 'X', 'what': 'a body'});
    await pumpEditor(
      tester,
      initialTemplate: spec,
      initialText: conforming,
      onChromeVisibleChanged: chromeVisible.add,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.byTooltip('Exit guided'));
    await tester.pump();

    expect(chromeVisible, contains(true));
    expect(find.text('Raw'), findsOneWidget);
  });

  testWidgets('last step shows Done instead of Next', (tester) async {
    await pumpEditor(tester, initialTemplate: spec);

    // Navigate to the final step.
    for (var i = 0; i < spec.sections.length - 1; i++) {
      await tester.tap(find.text('Next'));
      await tester.pump();
    }

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    expect(
      find.text('${spec.sections.length} / ${spec.sections.length}'),
      findsOneWidget,
    );
  });

  testWidgets('Done on last step exits Guided and materialises text into Raw', (
    tester,
  ) async {
    await pumpEditor(tester, initialTemplate: spec);
    await tester.enterText(find.byType(TextField).first, 'My title');
    await tester.pump();

    for (var i = 0; i < spec.sections.length - 1; i++) {
      await tester.tap(find.text('Next'));
      await tester.pump();
    }
    await tester.tap(find.text('Done'));
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    final raw = tester.widget<TextField>(find.byType(TextField));
    expect(raw.controller!.text, startsWith('# My title'));
  });
}
