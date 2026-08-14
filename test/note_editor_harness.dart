/// The shared pumpEditor harness and template constants.
///
/// Shared by the files `note_editor_test.dart` was split into for the
/// 250-line cap. Deliberately NOT named `*_test.dart`: the runner would
/// collect it and fail on the missing `main()`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/data/note.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/ui/markdown_view.dart';
import 'package:todo/ui/note_editor.dart';

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
