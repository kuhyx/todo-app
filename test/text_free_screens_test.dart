/// Textgate guard for the capture screen, the editor and the settings
/// screens: nothing app-written is painted, only typed content and numbers.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo/data/note_template.dart';
import 'package:todo/ui/cloud_images_settings.dart';
import 'package:todo/ui/note_editor_mode.dart';

import 'capture_screen_harness.dart';
import 'github_mirror_harness.dart';
import 'note_editor_harness.dart';
import 'settings_screen_harness.dart';
import 'text_free_guard.dart';

Future<void> _frames(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('the capture screen paints no words', (t) async {
    await pumpCapture(t);
    expectNoChromeWords(t);
  });

  testWidgets('a saved draft paints no words', (t) async {
    await pumpCapture(t);
    await t.enterText(find.byType(TextField), 'Buy milk');
    await _frames(t);
    expectNoChromeWords(t);
  });

  testWidgets('sync with nothing configured paints no words', (t) async {
    await pumpCapture(t);
    await t.tap(find.bySemanticsLabel('Sync'));
    await _frames(t);
    expectNoChromeWords(t);
  });

  testWidgets('a failed sync paints no words', (t) async {
    await pumpCapture(
      t,
      prefs: configuredPrefs,
      httpClient: MockClient((_) async => http.Response('boom', 500)),
    );
    await t.tap(find.bySemanticsLabel('Sync'));
    await _frames(t);
    expectNoChromeWords(t, content: const ['boom']);
  });

  testWidgets('the guided wizard and its steps paint no words', (t) async {
    await pumpCapture(t);
    await t.tap(find.bySemanticsLabel('Guided'));
    await t.pump();
    expectNoChromeWords(t);
    await t.tap(find.bySemanticsLabel('Next'));
    await t.pump();
    expectNoChromeWords(t);
    await t.tap(find.bySemanticsLabel('Start'));
    await t.pump();
    expectNoChromeWords(t);
    await t.tap(find.bySemanticsLabel('Next'));
    await _frames(t);
    expectNoChromeWords(t);
  });

  testWidgets('a guided step paints no words', (t) async {
    await pumpEditor(t, initialTemplate: NoteTemplate.llmDesignSpec);
    expectNoChromeWords(t);
  });

  testWidgets('the raw editor paints no words', (t) async {
    await pumpEditor(t, initialMode: NoteEditorMode.raw);
    expectNoChromeWords(t);
  });

  testWidgets('settings paint no words', (t) async {
    await pumpSettings(t);
    expectNoChromeWords(t);
  });

  testWidgets('sync settings paint no words', (t) async {
    await pumpSettings(t);
    await t.tap(find.bySemanticsLabel('Sync settings: Firebase'));
    await _frames(t);
    await _frames(t);
    expectNoChromeWords(t);
  });

  testWidgets('GitHub sync and its test result paint no words', (t) async {
    await pumpMirror(
      t,
      httpClient: MockClient((_) async => http.Response('{}', 404)),
    );
    expectNoChromeWords(t, content: const ['kuhyx', 'syncs']);
    await t.tap(find.bySemanticsLabel('Test connection'));
    await _frames(t);
    expectNoChromeWords(t, content: const ['kuhyx', 'syncs']);
  });

  for (final field in [true, false]) {
    testWidgets('cloud images (field: $field) paint no words', (t) async {
      await t.pumpWidget(
        MaterialApp(home: CloudImagesScreen(showPasswordField: field)),
      );
      await t.pump();
      expectNoChromeWords(t);
    });
  }
}
