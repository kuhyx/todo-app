import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/ui/image_picking.dart';

void main() {
  testWidgets('the button passes picked images on, ignores a cancel', (
    tester,
  ) async {
    final got = <List<Uint8List>>[];
    var result = <Uint8List>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttachImageButton(
            onImages: got.add,
            picking: (_) async => result,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Attach image'));
    await tester.pump();
    expect(got, isEmpty);
    result = [
      Uint8List.fromList([1]),
    ];
    await tester.tap(find.byTooltip('Attach image'));
    await tester.pump();
    expect(got.single.single, [1]);
  });

  Future<List<Uint8List>?> openSheet(
    WidgetTester tester,
    List<ImagePickSource> asked,
  ) async {
    List<Uint8List>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await pickImages(
                context,
                fromPhone: (source) async {
                  asked.add(source);
                  return [
                    Uint8List.fromList([source.index]),
                  ];
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

  testWidgets('the phone sheet offers Camera and Gallery', (tester) async {
    final asked = <ImagePickSource>[];
    await openSheet(tester, asked);
    expect(find.text('Camera'), findsOneWidget);
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();
    expect(asked, [ImagePickSource.gallery]);
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camera'));
    await tester.pumpAndSettle();
    expect(asked, [ImagePickSource.gallery, ImagePickSource.camera]);
  });

  testWidgets('dismissing the sheet picks nothing', (tester) async {
    final asked = <ImagePickSource>[];
    await openSheet(tester, asked);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(asked, isEmpty);
  });
}
