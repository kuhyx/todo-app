import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/ui/capture_confirm_mark.dart';

import '../capture_screen_harness.dart';
import 'motion_harness.dart';

const _lightImpact = 'HapticFeedbackType.lightImpact';
final _mark = find.byKey(CaptureConfirmMark.iconKey);

double _opacity(WidgetTester tester) => tester
    .widget<Opacity>(find.ancestor(of: _mark, matching: find.byType(Opacity)))
    .opacity;

Future<void> _type(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), 'buy milk');
  await tester.pump();
}

void main() {
  testWidgets('typing alone neither vibrates nor shows the checkmark', (
    tester,
  ) async {
    final haptics = recordHaptics(tester);
    await pumpCapture(tester);
    await _type(tester);
    await tester.enterText(find.byType(TextField), 'buy milk and eggs');
    await tester.pump(const Duration(milliseconds: 100));

    expect(haptics, isEmpty);
    expect(_mark, findsNothing);
  });

  testWidgets('committing a captured note vibrates once, immediately', (
    tester,
  ) async {
    final haptics = recordHaptics(tester);
    await pumpCapture(tester);
    await _type(tester);

    await tester.tap(find.bySemanticsLabel('New note'));
    await tester.pump(); // one frame: the cue must not wait for anything

    expect(haptics, [_lightImpact]);
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('the checkmark fades in, holds, fades out in ~600 ms', (
    tester,
  ) async {
    recordHaptics(tester);
    await pumpCapture(tester);
    await _type(tester);

    await tester.tap(find.bySemanticsLabel('New note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(_mark, findsOneWidget);
    expect(_opacity(tester), inExclusiveRange(0, 1)); // fading in

    await tester.pump(const Duration(milliseconds: 200)); // t = 300 ms
    expect(_opacity(tester), 1); // holding

    await tester.pump(const Duration(milliseconds: 200)); // t = 500 ms
    expect(_opacity(tester), inExclusiveRange(0, 1)); // fading out

    await tester.pump(const Duration(milliseconds: 200)); // t = 700 ms
    expect(_mark, findsNothing);
  });

  testWidgets('an empty draft is not a capture: no haptic, no checkmark', (
    tester,
  ) async {
    final haptics = recordHaptics(tester);
    await pumpCapture(tester);

    await tester.tap(find.bySemanticsLabel('New note'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(haptics, isEmpty);
    expect(_mark, findsNothing);
  });

  testWidgets('each capture confirms once; tapping the reset box does not', (
    tester,
  ) async {
    final haptics = recordHaptics(tester);
    await pumpCapture(tester);
    await _type(tester);
    await tester.tap(find.bySemanticsLabel('New note'));
    await tester.pump(); // the ticker's clock starts on its first frame
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tap(
      find.bySemanticsLabel('New note'),
    ); // nothing new to capture
    await tester.pump(const Duration(milliseconds: 100));
    expect(haptics, hasLength(1));
    expect(_mark, findsNothing);

    await _type(tester);
    await tester.tap(find.bySemanticsLabel('New note'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(haptics, hasLength(2));
    expect(_mark, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('remove-animations: still vibrates, checkmark static', (
    tester,
  ) async {
    final haptics = recordHaptics(tester);
    disableAnimations(tester);
    await pumpCapture(tester);
    await _type(tester);

    await tester.tap(find.bySemanticsLabel('New note'));
    await tester.pump();
    expect(haptics, [_lightImpact]);

    await tester.pump(const Duration(milliseconds: 1));
    expect(_opacity(tester), 1); // no fade-in
    await tester.pump(const Duration(milliseconds: 400));
    expect(_opacity(tester), 1); // no fade-out either
    await tester.pump(const Duration(milliseconds: 300));
    expect(_mark, findsNothing);
  });

  testWidgets('the checkmark reserves its width so the counter never jumps', (
    tester,
  ) async {
    recordHaptics(tester);
    await pumpCapture(tester);
    final before = tester.getTopLeft(find.text('0'));
    await _type(tester);
    await tester.tap(find.bySemanticsLabel('New note'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getTopLeft(find.text('1')), before);
    await tester.pump(const Duration(milliseconds: 400));
  });
}
