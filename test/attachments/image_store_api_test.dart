import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/attachments/image_store_scope.dart';
import 'package:todo/images/image_ref.dart';

void main() {
  final ref = ImageRef.create('n1');

  test('NoImageStore refuses to attach and has nothing', () async {
    final store = NoImageStore();
    await expectLater(
      store.attach('n1', Uint8List(1)),
      throwsA(isA<ImageStoreException>()),
    );
    await store.reconcile(['x']);
    expect(store.sourceFor(ref), isA<MissingImageSource>());
    expect(store.isPending(ref), isFalse);
    final status = await store.status();
    expect((status.configured, status.pending), (false, 0));
  });

  test('ImageStoreException shows its message', () {
    expect(const ImageStoreException('boom').toString(), 'boom');
  });

  test('imageRefsAcross unions every note', () {
    final other = ImageRef.create('n2');
    expect(
      imageRefsAcross([ref.markdown, '${other.markdown}\n${ref.markdown}']),
      {ref, other},
    );
  });

  testWidgets('the scope provides its store, else a NoImageStore', (
    tester,
  ) async {
    final store = NoImageStore();
    late ImageStore found;
    late ImageStore read;
    late ImageStore fallback;
    await tester.pumpWidget(
      Column(
        children: [
          ImageStoreScope(
            store: store,
            child: Builder(
              builder: (context) {
                found = ImageStoreScope.of(context);
                read = ImageStoreScope.read(context);
                return const SizedBox();
              },
            ),
          ),
          Builder(
            builder: (context) {
              fallback = ImageStoreScope.of(context);
              return const SizedBox();
            },
          ),
        ],
      ),
    );
    expect(found, same(store));
    expect(read, same(store));
    expect(fallback, isA<NoImageStore>());
  });
}
