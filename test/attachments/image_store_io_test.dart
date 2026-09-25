import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/attachments/image_password_store.dart';
import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/attachments/image_store_io.dart';
import 'package:todo/images/image_cache_store.dart';

import '../fake_secure_storage.dart';
import '../images/fake_dufs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late FakeDufs dufs;
  late IoImageStore store;
  late int notified;

  IoImageStore make({Future<Uint8List?> Function(Uint8List)? prepare}) {
    final s = IoImageStore(
      ImageCacheStore(root),
      httpClient: dufs.httpClient,
      prepare: prepare ?? (b) async => b.first == 0xFF ? b : null,
    );
    notified = 0;
    s.addListener(() => notified++);
    return s;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('io_store');
    dufs = FakeDufs();
    installFakeSecureStorage(initial: {'dufsImagesPassword': 'pw'});
    store = make();
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('attach stores, notifies and uploads straight away', () async {
    final ref = (await store.attach('n1', Uint8List.fromList([0xFF, 1])))!;
    expect(ref.noteId, 'n1');
    expect(store.sourceFor(ref), isA<LocalImageSource>());
    expect(notified, greaterThanOrEqualTo(1));
    await pumpEventQueue();
    expect(dufs.files[ref.relativePath], [0xFF, 1]);
    expect(store.isPending(ref), isFalse);
  });

  test('attach returns null for a non-image and stores nothing', () async {
    expect(await store.attach('n1', Uint8List.fromList([1])), isNull);
    expect(root.listSync(), isEmpty);
  });

  test('attach fails loudly when the image cannot be written', () async {
    root.deleteSync(recursive: true);
    File(root.path).writeAsStringSync('not a dir');
    await expectLater(
      store.attach('n1', Uint8List.fromList([0xFF])),
      throwsA(isA<ImageStoreException>()),
    );
    File(root.path).deleteSync();
    root.createSync();
  });

  test('without a password attach queues offline', () async {
    installFakeSecureStorage();
    final ref = (await store.attach('n1', Uint8List.fromList([0xFF])))!;
    await pumpEventQueue();
    expect(dufs.requests, isEmpty);
    expect(store.isPending(ref), isTrue);
    expect((await store.status()).configured, isFalse);
    expect((await store.status()).pending, 1);
  });

  test('reconcile prefetches what notes link to and notifies', () async {
    dufs.files['n2/b.jpg'] = [7];
    final before = notified;
    await store.reconcile([
      'x\n![](https://kuhy-cloud.duckdns.org/todo-images/n2/b.jpg)',
    ]);
    expect(notified, before + 1);
    final status = await store.status();
    expect((status.configured, status.pending), (true, 0));
  });

  test('a reconcile with nothing to do does not notify', () async {
    await store.reconcile(['no images']);
    expect(notified, 0);
  });

  test('a missing image has a missing source', () {
    final ref = imageRefsAcross([
      '![](https://kuhy-cloud.duckdns.org/todo-images/n9/z.jpg)',
    ]).single;
    expect(store.sourceFor(ref), isA<MissingImageSource>());
  });

  test('the default prepare and client are the real ones', () {
    expect(
      IoImageStore(
        ImageCacheStore(root),
        passwords: const ImagePasswordStore(),
      ),
      isA<ImageStore>(),
    );
  });
}
