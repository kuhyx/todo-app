import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/ui/markdown_view.dart';
import 'package:todo/ui/note_editor.dart';

import 'note_editor_harness.dart';

void main() {
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
