import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/attachments/image_store_scope.dart';
import 'package:todo/ui/image_attach.dart';

import '../fake_image_store.dart';

void main() {
  late FakeImageStore store;
  late ImageAttachController target;
  late List<List<String>> inserted;

  setUp(() {
    store = FakeImageStore();
    target = ImageAttachController();
    inserted = [];
    target.bind(inserted.add);
  });

  Future<BuildContext> pumpScope(WidgetTester tester) async {
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

  testWidgets('files and images attach in order, each as its own line', (
    tester,
  ) async {
    final context = await pumpScope(tester);
    await attachFiles(
      context,
      noteId: () => 'n1',
      target: target,
      files: [XFile('/p/a.pdf'), XFile('/p/shot.png')],
    );
    final lines = inserted.single;
    expect(lines.first, startsWith('[a.pdf]('));
    expect(lines.last, startsWith('![]('));
  });

  testWidgets('a store failure is shown and keeps what came before', (
    tester,
  ) async {
    final context = await pumpScope(tester);
    var calls = 0;
    await attachFiles(
      context,
      noteId: () {
        if (++calls == 2) store.failure = const ImageStoreException('full');
        return 'n1';
      },
      target: target,
      files: [XFile('/p/a.pdf'), XFile('/p/b.pdf'), XFile('/p/c.pdf')],
    );
    await tester.pump();
    expect(inserted.single, hasLength(1));
    expect(find.text('full'), findsOneWidget);
  });

  testWidgets('nothing is shown once the screen closed mid-attach', (
    tester,
  ) async {
    final context = await pumpScope(tester);
    final gate = Completer<void>();
    store
      ..gate = gate.future
      ..failure = const ImageStoreException('full');
    final done = attachFiles(
      context,
      noteId: () => 'n1',
      target: target,
      files: [XFile('/p/a.pdf')],
    );
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await done;
    await tester.pump();
    expect(find.text('full'), findsNothing);
  });
}
