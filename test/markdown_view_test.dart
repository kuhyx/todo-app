import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/ui/markdown_view.dart';

void main() {
  Future<void> pumpView(WidgetTester tester, String text) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MarkdownView(text: text)),
      ),
    );
    await tester.pump();
  }

  /// Finds the rendered Text widget whose data equals [data] and returns it.
  Text textWidget(WidgetTester tester, String data) =>
      tester.widget<Text>(find.text(data));

  testWidgets('renders an h1 title bold and large', (tester) async {
    await pumpView(tester, '# Big title');
    final t = textWidget(tester, 'Big title');
    expect(t.style?.fontWeight, FontWeight.bold);
  });

  testWidgets('renders an h2 section heading without its marker', (
    tester,
  ) async {
    await pumpView(tester, '## what');
    expect(find.text('what'), findsOneWidget);
    expect(textWidget(tester, 'what').style?.fontWeight, FontWeight.bold);
  });

  testWidgets('renders a whole-line italic guidance line', (tester) async {
    await pumpView(tester, '_guidance text_');
    final t = textWidget(tester, 'guidance text');
    expect(t.style?.fontStyle, FontStyle.italic);
  });

  testWidgets('renders dash and star bullets with a bullet glyph', (
    tester,
  ) async {
    await pumpView(tester, '- first\n* second');
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    expect(find.textContaining('•'), findsNWidgets(2));
  });

  testWidgets('renders a plain paragraph and blank-line spacers', (
    tester,
  ) async {
    await pumpView(tester, 'a paragraph\n\nanother');
    expect(find.text('a paragraph'), findsOneWidget);
    expect(find.text('another'), findsOneWidget);
    // The blank line between paragraphs becomes a spacer box.
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('a full assembled note renders all element types', (
    tester,
  ) async {
    await pumpView(
      tester,
      '# Title\n\n## what\n_why we need it_\n\n- one\n- two\nplain tail',
    );
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('what'), findsOneWidget);
    expect(find.text('why we need it'), findsOneWidget);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('plain tail'), findsOneWidget);
  });
}
