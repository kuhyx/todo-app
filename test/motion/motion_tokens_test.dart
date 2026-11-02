import 'dart:async';
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/ui/app_route.dart';

import '../note_editor_harness.dart';
import 'motion_harness.dart';

double _barValue(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
    .value!;

Future<void> _pushPage(WidgetTester tester) async {
  late BuildContext ctx;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) {
          ctx = c;
          return const Scaffold(body: Text('home'));
        },
      ),
    ),
  );
  unawaited(
    Navigator.of(
      ctx,
    ).push<void>(appRoute(ctx, (_) => const Scaffold(body: Text('page')))),
  );
  await tester.pump();
}

void main() {
  test('every page route goes through appRoute', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('ui/app_route.dart')) continue;
      if (f.readAsStringSync().contains('MaterialPageRoute(')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });

  testWidgets('a pushed page eases in over AppDuration.slow', (tester) async {
    await _pushPage(tester);
    await tester.pump(AppDuration.slow ~/ 4);
    expect(find.text('page'), findsOneWidget);
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.text('page'),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, inExclusiveRange(0, 1));

    await tester.pump(AppDuration.slow);
    expect(find.text('home'), findsNothing); // fully covered, route settled
  });

  testWidgets('remove-animations: the page is there at once', (tester) async {
    disableAnimations(tester);
    await _pushPage(tester);
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.text('home'), findsNothing);
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets('wizard progress bar animates between steps', (tester) async {
    await pumpEditor(tester, initialTemplate: spec);
    final total = spec.sections.length;
    expect(_barValue(tester), closeTo(1 / total, 1e-9));

    await tester.tap(find.text('Next'));
    await tester.pump();
    await tester.pump(AppDuration.base ~/ 2);
    expect(_barValue(tester), inExclusiveRange(1 / total, 2 / total));

    await tester.pump(AppDuration.base);
    expect(_barValue(tester), closeTo(2 / total, 1e-9));
  });

  testWidgets('remove-animations: the progress bar jumps', (tester) async {
    disableAnimations(tester);
    await pumpEditor(tester, initialTemplate: spec);
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(_barValue(tester), closeTo(2 / spec.sections.length, 1e-9));
  });
}
