import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:todo/attachments/image_store_scope.dart';
import 'package:todo/images/image_ref.dart';
import 'package:todo/ui/images/image_embed.dart';
import 'package:todo/ui/images/image_strip.dart';
import 'package:todo/ui/images/image_viewer_screen.dart';

import '../fake_image_store.dart';

void main() {
  final ref = ImageRef.create('n1');
  late FakeImageStore store;
  late Directory dir;

  setUp(() {
    store = FakeImageStore();
    dir = Directory.systemTemp.createTempSync('embed');
    final file = File('${dir.path}/a.jpg')
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 4, height: 4)));
    store.localPath = file.path;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    ImageStoreScope(
      store: store,
      child: MaterialApp(
        home: Scaffold(body: SizedBox(width: 200, height: 200, child: child)),
      ),
    ),
  );

  testWidgets('a local image renders and opens full screen', (tester) async {
    await pump(tester, ImageEmbed(ref: ref));
    expect(find.byType(Image), findsOneWidget);
    expect(find.byTooltip(kImageWaitingToUpload), findsNothing);
    await tester.tap(find.byType(ImageEmbed));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerScreen), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('a queued image carries the upload badge', (tester) async {
    store.pending.add(ref);
    await pump(tester, ImageEmbed(ref: ref));
    expect(find.byTooltip(kImageWaitingToUpload), findsOneWidget);
  });

  testWidgets('a missing image is a placeholder and not tappable', (
    tester,
  ) async {
    store.missing.add(ref);
    await pump(tester, ImageEmbed(ref: ref));
    expect(find.text(kImageNotDownloaded), findsOneWidget);
    await tester.tap(find.byType(ImageEmbed));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerScreen), findsNothing);
  });

  testWidgets('a broken file or url falls back to the placeholder', (
    tester,
  ) async {
    store.localPath = '${dir.path}/gone.jpg';
    await pump(tester, ImageEmbed(ref: ref));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.text(kImageNotDownloaded), findsOneWidget);
    store.network = true;
    store.changed();
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(find.text(kImageNotDownloaded), findsOneWidget);
  });

  testWidgets('the strip shows one thumbnail per linked image', (tester) async {
    final other = ImageRef.create('n2');
    await pump(
      tester,
      ImageStrip(text: 'x\n${ref.markdown}\n${other.markdown}'),
    );
    expect(find.byType(ImageEmbed), findsNWidgets(2));
  });

  testWidgets('the strip is empty without images', (tester) async {
    await pump(tester, const ImageStrip(text: 'no images'));
    expect(find.byType(ImageEmbed), findsNothing);
  });
}
