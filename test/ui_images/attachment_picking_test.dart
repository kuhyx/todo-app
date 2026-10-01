import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/ui/attachment_picking.dart';

void main() {
  testWidgets('the button passes picked files on, ignores a cancel', (
    tester,
  ) async {
    final got = <List<XFile>>[];
    var result = <XFile>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttachButton(onFiles: got.add, picking: (_) async => result),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Attach'));
    await tester.pump();
    expect(got, isEmpty);
    result = [XFile('/picked/a.pdf')];
    await tester.tap(find.byTooltip('Attach'));
    await tester.pump();
    expect(got.single.single.name, 'a.pdf');
  });

  Future<List<XFile>?> openSheet(
    WidgetTester tester,
    List<AttachmentPickSource> asked,
  ) async {
    List<XFile>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await pickAttachments(
                context,
                fromPhone: (source) async {
                  asked.add(source);
                  return [XFile('/picked/${source.name}')];
                },
              ),
              child: const Text('pick'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    return result;
  }

  Future<void> choose(WidgetTester tester, String entry) async {
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(entry));
    await tester.pumpAndSettle();
  }

  testWidgets('the phone sheet offers Camera, Gallery and File', (
    tester,
  ) async {
    final asked = <AttachmentPickSource>[];
    await openSheet(tester, asked);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    await choose(tester, 'Camera');
    await choose(tester, 'File');
    expect(asked, [
      AttachmentPickSource.gallery,
      AttachmentPickSource.camera,
      AttachmentPickSource.file,
    ]);
  });

  testWidgets('dismissing the sheet picks nothing', (tester) async {
    final asked = <AttachmentPickSource>[];
    await openSheet(tester, asked);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(asked, isEmpty);
  });
}
