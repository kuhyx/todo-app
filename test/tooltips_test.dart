import 'package:flutter_test/flutter_test.dart';
import 'package:todo/ui/capture_screen.dart';
import 'package:todo/ui/text_free_localizations.dart';

import 'capture_screen_harness.dart';

void main() {
  testWidgets('app bar icon buttons show one-word tooltips on long-press', (
    tester,
  ) async {
    await pumpCapture(tester, prefs: configuredPrefs);
    await tester.pump();

    expect(find.byTooltip('settings'), findsOneWidget);
    expect(find.byTooltip('notes'), findsOneWidget);

    await tester.longPress(find.byTooltip('settings'));
    await tester.pumpAndSettle();
    expect(find.text('settings'), findsOneWidget);
  });
}
