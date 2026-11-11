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

Future<Route<void>> _pushPage(WidgetTester tester) async {
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
  final route = appRoute<void>(ctx, (_) => const Scaffold(body: Text('page')));
  unawaited(Navigator.of(ctx).push<void>(route));
  await tester.pump();
  return route;
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

  testWidgets('a pushed page is instant: no fade or slide', (tester) async {
    final route = await _pushPage(tester) as PageRoute<void>;
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    // Fully visible and covering the old page after a single pump.
    expect(find.text('home'), findsNothing);
    expect(find.text('page'), findsOneWidget);
    final page = find.ancestor(
      of: find.text('page'),
      matching: find.byType(FadeTransition),
    );
    for (final f in tester.widgetList<FadeTransition>(page)) {
      expect(f.opacity.value, 1);
    }
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

    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.pump();
    await tester.pump(AppDuration.base ~/ 2);
    expect(_barValue(tester), inExclusiveRange(1 / total, 2 / total));

    await tester.pump(AppDuration.base);
    expect(_barValue(tester), closeTo(2 / total, 1e-9));
  });

  testWidgets('remove-animations: the progress bar jumps', (tester) async {
    disableAnimations(tester);
    await pumpEditor(tester, initialTemplate: spec);
    await tester.tap(find.bySemanticsLabel('Next'));
    await tester.pump();
    expect(_barValue(tester), closeTo(2 / spec.sections.length, 1e-9));
  });
}
