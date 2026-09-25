import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/attachments/image_store_scope.dart';
import 'package:todo/ui/image_attach.dart';

import '../fake_image_store.dart';

void main() {
  test('the controller inserts only while an editor is bound', () {
    final controller = ImageAttachController();
    final got = <List<String>>[];
    expect(controller.insert(['a']), isFalse);
    final unbind = controller.bind(got.add);
    expect(controller.insert([]), isFalse);
    expect(controller.insert(['a']), isTrue);
    // A later editor's bind wins; the earlier unbind no longer detaches it.
    final unbindSecond = controller.bind(got.add);
    unbind();
    expect(controller.insert(['b']), isTrue);
    unbindSecond();
    expect(controller.insert(['c']), isFalse);
    expect(got, [
      ['a'],
      ['b'],
    ]);
  });

  Future<BuildContext> pumpScope(WidgetTester tester, ImageStore store) async {
    late BuildContext context;
    await tester.pumpWidget(
      ImageStoreScope(
        store: store,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    return context;
  }

  testWidgets('attaches in order and inserts every link', (tester) async {
    final store = FakeImageStore();
    final context = await pumpScope(tester, store);
    final controller = ImageAttachController();
    final inserted = <List<String>>[];
    controller.bind(inserted.add);
    var asked = 0;
    await attachImages(
      context,
      noteId: () {
        asked++;
        return 'n1';
      },
      target: controller,
      images: [
        Uint8List.fromList([1]),
        Uint8List.fromList([2]),
      ],
    );
    expect(asked, 2);
    expect(store.attached.values.map((b) => b.first), [1, 2]);
    expect(inserted.single, [
      for (final ref in store.attached.keys) ref.markdown,
    ]);
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('reports one non-image', (tester) async {
    final store = FakeImageStore();
    final context = await pumpScope(tester, store);
    await attachImages(
      context,
      noteId: () => 'n1',
      target: ImageAttachController(),
      images: [
        Uint8List.fromList([0]),
      ],
    );
    await tester.pump();
    expect(find.text('Not an image'), findsOneWidget);
  });

  testWidgets('counts dropped non-images together', (tester) async {
    final store = FakeImageStore();
    final context = await pumpScope(tester, store);
    await attachImages(
      context,
      noteId: () => 'n1',
      target: ImageAttachController(),
      images: [
        Uint8List.fromList([0]),
      ],
      rejected: 2,
    );
    await tester.pump();
    expect(find.text('3 files were not images'), findsOneWidget);
  });

  testWidgets('a store failure is shown and stops the batch', (tester) async {
    final store = FakeImageStore()
      ..failure = const ImageStoreException('helper down');
    final context = await pumpScope(tester, store);
    await attachImages(
      context,
      noteId: () => 'n1',
      target: ImageAttachController(),
      images: [
        Uint8List.fromList([1]),
        Uint8List.fromList([2]),
      ],
    );
    await tester.pump();
    expect(find.text('helper down'), findsOneWidget);
  });

  testWidgets('nothing is shown once the screen closed mid-attach', (
    tester,
  ) async {
    final gate = Completer<void>();
    final store = FakeImageStore()..gate = gate.future;
    final context = await pumpScope(tester, store);
    final pending = attachImages(
      context,
      noteId: () => 'n1',
      target: ImageAttachController(),
      images: [
        Uint8List.fromList([0]),
      ],
    );
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await pending;
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });
}
