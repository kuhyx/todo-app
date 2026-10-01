import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:todo/images/attachment_ingest.dart';
import 'package:todo/images/image_cache_store.dart';
import 'package:todo/images/image_processing.dart';

void main() {
  late Directory root;
  late ImageCacheStore store;
  late List<int> prepared;

  final png = img.encodePng(img.Image(width: 4, height: 3));
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 1]);

  AttachmentIngest ingest({Uint8List? Function(Uint8List)? prepare}) =>
      AttachmentIngest(
        store,
        prepare: (bytes) async {
          prepared.add(bytes.length);
          return (prepare ?? (_) => jpeg)(bytes);
        },
      );

  setUp(() {
    root = Directory.systemTemp.createTempSync('ingest');
    store = ImageCacheStore(Directory(p.join(root.path, 'store')));
    prepared = [];
  });
  tearDown(() => root.deleteSync(recursive: true));

  void expectNoTemps() => expect(
    store.root.listSync(recursive: true).where((e) => e.path.endsWith('.tmp')),
    isEmpty,
  );

  test('a non-image is stored byte for byte as a queued file', () async {
    final pdf = '%PDF-1.7 hello'.codeUnits;
    final a = await ingest().fromStream('n1', 'Raport.pdf', Stream.value(pdf));
    expect(a.isImage, isFalse);
    expect(a.name, 'Raport.pdf');
    expect(a.ref.extension, 'pdf');
    expect(store.fileFor(a.ref).readAsBytesSync(), pdf);
    expect(store.isPending(a.ref), isTrue);
    expect(prepared, isEmpty, reason: 'never decoded');
    expectNoTemps();
  });

  test('an image is re-encoded and stored as a jpg', () async {
    final a = await ingest().fromStream('n1', 'shot.png', Stream.value(png));
    expect(a.isImage, isTrue);
    expect(a.ref.extension, 'jpg');
    expect(store.fileFor(a.ref).readAsBytesSync(), jpeg);
    expect(store.isPending(a.ref), isTrue);
    expect(prepared, [png.length]);
    expectNoTemps();
  });

  test('the real preparer is the default', () async {
    final a = await AttachmentIngest(
      store,
    ).fromStream('n1', 'shot.png', Stream.value(png));
    expect(img.decodeJpg(store.fileFor(a.ref).readAsBytesSync()), isNotNull);
  });

  test('an image that will not decode is kept as a file', () async {
    final a = await ingest(
      prepare: (_) => null,
    ).fromStream('n1', 'broken.png', Stream.value(png));
    expect(a.isImage, isFalse);
    expect(a.ref.extension, 'png');
    expect(store.fileFor(a.ref).readAsBytesSync(), png);
  });

  test('an image too big to decode is kept as a file, unread', () async {
    final chunk = Uint8List(1024 * 1024);
    Stream<List<int>> huge() async* {
      yield png.sublist(0, kImageSniffBytes);
      for (var i = 0; i < kMaxImageDecodeBytes ~/ chunk.length; i++) {
        yield chunk;
      }
    }

    final a = await ingest().fromStream('n1', 'huge.png', huge());
    expect(a.isImage, isFalse);
    expect(prepared, isEmpty);
    expect(
      store.fileFor(a.ref).lengthSync(),
      kMaxImageDecodeBytes + kImageSniffBytes,
    );
  });

  test('a failed read leaves nothing behind', () async {
    Stream<List<int>> broken() async* {
      yield [1, 2];
      throw const FileSystemException('gone');
    }

    await expectLater(
      ingest().fromStream('n1', 'a.bin', broken()),
      throwsA(isA<FileSystemException>()),
    );
    expectNoTemps();
    expect(store.pending(), isEmpty);
  });

  test('fromFile copies a file it does not own', () async {
    final source = File(p.join(root.path, 'mine.txt'))..writeAsStringSync('x');
    final a = await ingest().fromFile('n1', 'mine.txt', source, move: false);
    expect(store.fileFor(a.ref).readAsStringSync(), 'x');
    expect(source.existsSync(), isTrue);
  });

  test('fromFile moves a picker copy instead of duplicating it', () async {
    final source = File(p.join(root.path, 'copy.txt'))..writeAsStringSync('x');
    final a = await ingest().fromFile('n1', 'copy.txt', source, move: true);
    expect(store.fileFor(a.ref).readAsStringSync(), 'x');
    expect(source.existsSync(), isFalse);
    expectNoTemps();
  });

  test('a failure after the move cleans up the moved file', () async {
    final source = File(p.join(root.path, 'copy.png'))..writeAsBytesSync(png);
    await expectLater(
      AttachmentIngest(
        store,
        prepare: (_) async => throw const FileSystemException('disk full'),
      ).fromFile('n1', 'copy.png', source, move: true),
      throwsA(isA<FileSystemException>()),
    );
    expectNoTemps();
  });

  test('fromFile falls back to copy-and-delete across filesystems', () async {
    final shm = Directory('/dev/shm').createTempSync('ingest');
    addTearDown(() => shm.deleteSync(recursive: true));
    final source = File(p.join(shm.path, 'far.txt'))..writeAsStringSync('y');
    final a = await ingest().fromFile('n1', 'far.txt', source, move: true);
    expect(store.fileFor(a.ref).readAsStringSync(), 'y');
    expect(source.existsSync(), isFalse);
  }, skip: Directory('/dev/shm').existsSync() ? false : 'needs /dev/shm');
}
