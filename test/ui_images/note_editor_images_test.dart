import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/data/note_template_parser.dart';
import 'package:todo/ui/image_attach.dart';
import 'package:todo/ui/note_editor.dart';

void main() {
  late ImageAttachController attach;
  late List<String> emitted;

  Future<void> pump(
    WidgetTester tester, {
    String text = '',
    NoteTemplate? template,
    NoteEditorMode mode = NoteEditorMode.raw,
    ValueChanged<NoteEditorMode>? onModeChanged,
    Key? key,
  }) async {
    attach = ImageAttachController();
    emitted = [];
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteEditor(
            key: key,
            initialText: text,
            initialTemplate: template,
            initialMode: mode,
            priority: Priority.medium,
            onPriorityChanged: (_) {},
            onChromeVisibleChanged: (_) {},
            onChanged: emitted.add,
            attachController: attach,
            onModeChanged: onModeChanged,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  TextEditingController field(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!;

  testWidgets('raw: inserts on its own line at the cursor', (tester) async {
    await pump(tester, text: 'line1\nline2', template: NoteTemplate.blank);
    field(tester).selection = const TextSelection.collapsed(offset: 5);
    attach.insert(['IMG1', 'IMG2']);
    await tester.pump();
    expect(field(tester).text, 'line1\nIMG1\nIMG2\nline2');
    expect(field(tester).selection.baseOffset, 'line1\nIMG1\nIMG2'.length);
    expect(emitted.last, 'line1\nIMG1\nIMG2\nline2');
  });

  testWidgets('raw: a selection is replaced; no cursor appends', (
    tester,
  ) async {
    await pump(tester, text: 'abc', template: NoteTemplate.blank);
    field(tester).selection = const TextSelection(
      baseOffset: 1,
      extentOffset: 2,
    );
    attach.insert(['I']);
    await tester.pump();
    expect(field(tester).text, 'a\nI\nc');
    field(tester).selection = const TextSelection.collapsed(offset: -1);
    attach.insert(['J']);
    await tester.pump();
    expect(field(tester).text, 'a\nI\nc\nJ\n');
  });

  testWidgets('raw: an empty note gets just the link', (tester) async {
    await pump(tester, template: NoteTemplate.blank);
    attach.insert(['I']);
    await tester.pump();
    expect(field(tester).text, 'I\n');
  });

  testWidgets('guided: goes into the current step', (tester) async {
    await pump(
      tester,
      template: NoteTemplate.llmDesignSpec,
      mode: NoteEditorMode.guided,
    );
    expect(find.text('Exit guided'), findsNothing);
    attach.insert(['IMG']);
    await tester.pump();
    expect(field(tester).text, 'IMG\n');
    expect(emitted.last, contains('IMG'));
  });

  testWidgets('view over a raw note appends to the end', (tester) async {
    final modes = <NoteEditorMode>[];
    await pump(
      tester,
      text: 'freeform text',
      template: NoteTemplate.blank,
      onModeChanged: modes.add,
    );
    await tester.tap(find.text('View'));
    await tester.pump();
    expect(modes, [NoteEditorMode.preview]);
    attach.insert(['IMG']);
    await tester.pump();
    expect(emitted.last, 'freeform text\nIMG\n');
  });

  testWidgets('view over guided sections appends to the last section', (
    tester,
  ) async {
    const spec = NoteTemplate.llmDesignSpec;
    final text = assemble(spec, {
      for (final s in spec.sections) s.key: s.isTitle ? 'Title' : 'v ${s.key}',
    });
    await pump(
      tester,
      text: text,
      template: spec,
      mode: NoteEditorMode.preview,
    );
    attach.insert(['IMG']);
    await tester.pump();
    final last = spec.sections.last;
    final tail = emitted.last.substring(
      emitted.last.indexOf('## ${last.label}'),
    );
    expect(tail, contains('v ${last.key}\nIMG'));
  });

  testWidgets('a new controller on the same editor is rebound', (tester) async {
    await pump(tester, text: 'a', template: NoteTemplate.blank);
    final first = attach;
    await pump(tester, text: 'a', template: NoteTemplate.blank);
    expect(first.insert(['x']), isFalse);
    expect(attach.insert(['y']), isTrue);
    // Same controller again: nothing to rebind.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NoteEditor(
            priority: Priority.medium,
            onPriorityChanged: (_) {},
            onChromeVisibleChanged: (_) {},
            onChanged: (_) {},
            attachController: attach,
          ),
        ),
      ),
    );
    expect(attach.insert(['z']), isTrue);
  });

  testWidgets('disposing the editor unbinds it', (tester) async {
    await pump(tester, template: NoteTemplate.blank);
    await tester.pumpWidget(const SizedBox());
    expect(attach.insert(['x']), isFalse);
  });
}
