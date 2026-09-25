import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:todo/images/image_cache_store.dart';
import 'package:todo/images/image_ref.dart';

import 'fake_dufs.dart';

void main() {
  late Directory root;
  late ImageCacheStore store;
  late FakeDufs dufs;
  var now = DateTime(2026, 9, 25, 12);

  final a = ImageRef.tryParse('n1/a.jpg')!;
  final b = ImageRef.tryParse('n2/b.jpg')!;
  final bytes = Uint8List.fromList([1, 2, 3]);

  setUp(() {
    root = Directory.systemTemp.createTempSync('image_cache');
    now = DateTime.now();
    store = ImageCacheStore(root, now: () => now);
    dufs = FakeDufs();
  });
  tearDown(() => root.deleteSync(recursive: true));

  void age(ImageRef ref, Duration by) =>
      store.fileFor(ref).setLastModifiedSync(now.subtract(by));

  test('put stores the file and queues it', () async {
    await store.put(a, bytes);
    expect(store.fileFor(a).readAsBytesSync(), bytes);
    expect(store.isPending(a), isTrue);
    expect(store.pending(), [a]);
    expect(File('${store.fileFor(a).path}.tmp').existsSync(), isFalse);
  });

  test('an empty or missing root has nothing pending', () {
    root.deleteSync(recursive: true);
    expect(store.pending(), isEmpty);
    root.createSync();
  });

  test('reconcile uploads the queue and clears the marker', () async {
    await store.put(a, bytes);
    final report = await store.reconcile({a}, dufs.client());
    expect(dufs.files['n1/a.jpg'], bytes);
    expect(store.isPending(a), isFalse);
    expect(report.toJson(), {
      'uploaded': 1,
      'downloaded': 0,
      'evicted': 0,
      'pending': 0,
      'missing': 0,
    });
  });

  test('a failed upload keeps the marker for next time', () async {
    await store.put(a, bytes);
    dufs.online = false;
    final report = await store.reconcile({a}, dufs.client());
    expect(store.isPending(a), isTrue);
    expect(report.pending, 1);
    dufs.online = true;
    expect((await store.reconcile({a}, dufs.client())).uploaded, 1);
  });

  test('a marker whose file never landed is skipped, not uploaded', () async {
    await store.put(a, bytes);
    store.fileFor(a).deleteSync();
    final report = await store.reconcile({}, dufs.client());
    expect(report.uploaded, 0);
    expect(dufs.files, isEmpty);
  });

  test('without a client only eviction runs', () async {
    await store.put(a, bytes);
    final report = await store.reconcile({b}, null);
    expect(dufs.requests, isEmpty);
    expect(report.pending, 1);
    expect(report.missing, 1);
  });

  test('reconcile downloads linked images this device lacks', () async {
    dufs.files['n2/b.jpg'] = [9];
    final report = await store.reconcile({b}, dufs.client());
    expect(store.fileFor(b).readAsBytesSync(), [9]);
    expect(report.downloaded, 1);
    expect(report.missing, 0);
  });

  test('an image missing on dufs stays missing', () async {
    final report = await store.reconcile({b}, dufs.client());
    expect(report.downloaded, 0);
    expect(report.missing, 1);
  });

  test('evicts old unlinked cached images only', () async {
    dufs.files
      ..['n1/a.jpg'] = [1]
      ..['n2/b.jpg'] = [2];
    await store.reconcile({a, b}, dufs.client());
    age(a, const Duration(hours: 1));
    age(b, const Duration(hours: 1));
    final report = await store.reconcile({b}, dufs.client());
    expect(report.evicted, 1);
    expect(store.fileFor(a).existsSync(), isFalse);
    expect(store.fileFor(b).existsSync(), isTrue);
    expect(dufs.files.keys, contains('n1/a.jpg'), reason: 'never on dufs');
  });

  test('eviction spares queued and unparseable files', () async {
    await store.put(a, bytes);
    age(a, const Duration(hours: 1));
    File(p.join(root.path, 'n1', 'odd name.jpg'))
      ..writeAsBytesSync([1])
      ..setLastModifiedSync(now.subtract(const Duration(hours: 1)));
    dufs.online = false; // a stays queued
    final report = await store.reconcile({b}, dufs.client());
    expect(report.evicted, 0);
    expect(store.fileFor(a).existsSync(), isTrue);
    dufs.online = true; // uploaded now, so old + unlinked => evicted
    expect((await store.reconcile({b}, dufs.client())).evicted, 1);
    expect(store.fileFor(a).existsSync(), isFalse);
    expect(File(p.join(root.path, 'n1', 'odd name.jpg')).existsSync(), isTrue);
  });

  test('a young unlinked image survives the grace period', () async {
    dufs.files['n1/a.jpg'] = [1];
    await store.reconcile({a}, dufs.client());
    final report = await store.reconcile({b}, dufs.client());
    expect(report.evicted, 0);
    expect(store.fileFor(a).existsSync(), isTrue);
  });

  test('an empty ref set never evicts', () async {
    dufs.files['n1/a.jpg'] = [1];
    await store.reconcile({a}, dufs.client());
    age(a, const Duration(days: 1));
    expect((await store.reconcile({}, dufs.client())).evicted, 0);
    expect(store.fileFor(a).existsSync(), isTrue);
  });

  test('calls before a pass starts merge into it', () async {
    dufs.files
      ..['n1/a.jpg'] = [1]
      ..['n2/b.jpg'] = [2];
    final first = store.reconcile({a}, null);
    final second = store.reconcile({}, dufs.client()); // upload-only
    final third = store.reconcile({b}, null);
    expect(identical(first, second) && identical(second, third), isTrue);
    final report = await first;
    // One pass: refs unioned, and the only client given was kept.
    expect(report.downloaded, 2);
  });

  test('a call during a running pass gets one follow-up pass', () async {
    dufs.files['n2/b.jpg'] = [2];
    final running = store.reconcile({}, dufs.client());
    await Future<void>.delayed(Duration.zero); // let it start
    final next = store.reconcile({b}, dufs.client());
    expect(identical(running, next), isFalse);
    await running;
    expect((await next).downloaded, 1);
  });

  test('a failing pass does not wedge the queue', () async {
    final boom = ImageCacheStore(
      Directory(p.join(root.path, 'file-not-dir')),
      now: () => now,
    );
    File(boom.root.path).writeAsStringSync('x');
    dufs.files['n1/a.jpg'] = [1]; // downloading it must create a dir: fails
    await expectLater(
      boom.reconcile({a}, dufs.client()),
      throwsA(isA<FileSystemException>()),
    );
    File(boom.root.path).deleteSync();
    final report = await boom.reconcile({}, null);
    expect(report.pending, 0);
  });
}
