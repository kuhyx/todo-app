/// Shared helpers for the motion / haptic tests.
///
/// Deliberately NOT named `*_test.dart`: the runner would collect it and fail
/// on the missing `main()`.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records the arguments of every `HapticFeedback.*` call for the test's
/// lifetime. Matches the platform channel Flutter's [HapticFeedback] uses.
List<String> recordHaptics(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        calls.add(call.arguments as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

/// Turns the OS "remove animations" setting on for this test.
void disableAnimations(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}
