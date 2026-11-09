import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/images/attachment_ref.dart';
import 'package:todo/images/image_cache_store.dart';

import 'fake_dufs.dart';

/// A file that `existsSync()` still sees but that is gone by the time its
/// length is read: the window a teardown or a note deletion can hit while an
/// upload pass is between the two calls.
class _VanishingFile implements File {
  _VanishingFile(this.path);

  @override
  final String path;

  @override
  bool existsSync() => true;

  @override
  Future<int> length() async =>
      throw PathNotFoundException(path, const OSError('gone', 2));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Hands out a [_VanishingFile] for exactly one path, real files otherwise.
final class _VanishOverrides extends IOOverrides {
  _VanishOverrides(this.vanishing);

  final String vanishing;

  @override
  File createFile(String path) =>
      path == vanishing ? _VanishingFile(path) : super.createFile(path);
}

void main() {
  late Directory root;
  late ImageCacheStore store;
  late FakeDufs dufs;

  final a = AttachmentRef.tryParse('n1/a.jpg')!;
  final b = AttachmentRef.tryParse('n2/b.jpg')!;
  final bytes = Uint8List.fromList([1, 2, 3]);

  setUp(() {
    root = Directory.systemTemp.createTempSync('image_cache_vanish');
    store = ImageCacheStore(root);
    dufs = FakeDufs();
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('a file vanishing mid-pass is skipped; the rest still upload', () async {
    await store.put(a, bytes);
    await store.put(b, bytes);
    final report = await IOOverrides.runWithIOOverrides(
      () => store.reconcile({}, dufs.client()),
      _VanishOverrides(store.fileFor(a).path),
    );
    expect(report.uploaded, 1);
    expect(dufs.files.keys, ['n2/b.jpg']);
    expect(store.isPending(a), isTrue);
    expect(store.isPending(b), isFalse);
  });
}
