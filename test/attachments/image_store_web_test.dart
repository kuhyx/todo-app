import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/attachments/image_store_web.dart';
import 'package:todo/images/image_ref.dart';

void main() {
  final requests = <http.Request>[];
  late int notified;

  WebImageStore make(MockClientHandler handler) {
    requests.clear();
    final store = WebImageStore(
      origin: 'http://localhost:8731',
      httpClient: MockClient((r) {
        requests.add(r);
        return handler(r);
      }),
    );
    notified = 0;
    store.addListener(() => notified++);
    return store;
  }

  http.Response report({int downloaded = 0}) =>
      http.Response(jsonEncode({'downloaded': downloaded}), 200);

  test('openImageStore targets the serving wrapper', () async {
    final store = await openImageStore() as WebImageStore;
    expect(store.origin, 'http://localhost:8730');
  });

  test('attach POSTs the raw bytes and kicks an upload', () async {
    final store = make(
      (r) async =>
          r.url.path.endsWith('reconcile') ? report() : http.Response('', 204),
    );
    final ref = (await store.attach('n1', Uint8List.fromList([1, 2])))!;
    await pumpEventQueue();
    expect(requests.first.url.path, '/images/${ref.relativePath}');
    expect(requests.first.bodyBytes, [1, 2]);
    expect(requests.last.url.path, '/images/reconcile');
    expect(jsonDecode(requests.last.body), {'refs': <String>[]});
    expect(notified, 1);
    expect(store.sourceFor(ref), isA<NetworkImageSource>());
    expect(
      (store.sourceFor(ref) as NetworkImageSource).url,
      'http://localhost:8731/images/${ref.relativePath}?r=1',
    );
    expect(store.isPending(ref), isFalse);
  });

  test(
    'attach: 415 is not an image, other codes and no wrapper throw',
    () async {
      expect(
        await make(
          (_) async => http.Response('', 415),
        ).attach('n1', Uint8List(1)),
        isNull,
      );
      await expectLater(
        make((_) async => http.Response('', 500)).attach('n1', Uint8List(1)),
        throwsA(isA<ImageStoreException>()),
      );
      await expectLater(
        make(
          (_) => throw const SocketException('no wrapper'),
        ).attach('n1', Uint8List(1)),
        throwsA(
          isA<ImageStoreException>().having(
            (e) => e.toString(),
            'message',
            contains('not running'),
          ),
        ),
      );
    },
  );

  test('reconcile sends every linked ref; a download bumps the url', () async {
    final ref = ImageRef.create('n1');
    final store = make((_) async => report(downloaded: 1));
    await store.reconcile(['a ${ref.markdown}', 'none']);
    expect(jsonDecode(requests.single.body), {
      'refs': [ref.relativePath],
    });
    expect(notified, 1);
    expect((store.sourceFor(ref) as NetworkImageSource).url, endsWith('r=1'));
  });

  test('reconcile ignores failures and no-op reports', () async {
    await make((_) async => report()).reconcile([]);
    expect(notified, 0);
    await make((_) async => http.Response('', 500)).reconcile([]);
    await make((_) => throw const SocketException('x')).reconcile([]);
    expect(notified, 0);
  });

  test('status reads the wrapper, and degrades when it is gone', () async {
    final ok = await make(
      (_) async => http.Response('{"configured":true,"pending":2}', 200),
    ).status();
    expect((ok.configured, ok.pending), (true, 2));
    final empty = await make((_) async => http.Response('{}', 200)).status();
    expect((empty.configured, empty.pending), (false, 0));
    final gone = await make((_) => throw const SocketException('x')).status();
    expect(gone.configured, isFalse);
  });

  test('the default http client is created', () {
    expect(WebImageStore(origin: 'http://x'), isA<ImageStore>());
  });
}
