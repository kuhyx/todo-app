import 'package:flutter_test/flutter_test.dart';
import 'package:todo/images/image_ref.dart';

void main() {
  const rel = 'note-1/0815ff8a-203e-4f54-9cc5-8a58b27982ec.jpg';
  final ref = ImageRef.tryParse(rel)!;

  test('a ref exposes its parts, url and markdown', () {
    expect(ref.noteId, 'note-1');
    expect(ref.file, '0815ff8a-203e-4f54-9cc5-8a58b27982ec.jpg');
    expect(ref.relativePath, rel);
    expect(ref.url, '$kDufsBaseUrl/$kImagesDir/$rel');
    expect(ref.markdown, '![](${ref.url})');
  });

  test('create files a fresh uuid jpg under the note', () {
    final a = ImageRef.create('n1');
    final b = ImageRef.create('n1');
    expect(a.noteId, 'n1');
    expect(a.file, endsWith('.jpg'));
    expect(a, isNot(b));
  });

  test('create refuses an unsafe note id', () {
    expect(() => ImageRef.create('../x'), throwsArgumentError);
  });

  test('tryParse rejects traversal, nesting and other extensions', () {
    for (final bad in [
      '../x/y.jpg',
      'a/../b.jpg',
      'a/b/c.jpg',
      'a/b.png',
      'a/.jpg',
      '/a/b.jpg',
      'a b/c.jpg',
    ]) {
      expect(ImageRef.tryParse(bad), isNull, reason: bad);
    }
  });

  test('refs compare by path, so sets dedupe', () {
    expect({ref, ImageRef.tryParse(rel)!}, hasLength(1));
  });

  test('imageRefsIn finds every dufs image link, in order, once', () {
    final other = ImageRef.create('n2');
    final text =
        'hi ${ref.markdown} and\n${other.markdown}\n${ref.markdown}\n'
        '![x](https://example.com/a.jpg) ![]($kDufsBaseUrl/Keepass/a.jpg)';
    expect(imageRefsIn(text).toList(), [ref, other]);
    expect(imageRefsIn('no images'), isEmpty);
  });

  test('imageRefOfLine only matches a line that is just one image', () {
    expect(imageRefOfLine('  ${ref.markdown}  '), ref);
    expect(imageRefOfLine('see ${ref.markdown}'), isNull);
    expect(imageRefOfLine('![alt text](${ref.url})'), ref);
    expect(imageRefOfLine('plain'), isNull);
  });

  test('backlog paths round-trip exactly', () {
    final text = 'a\n${ref.markdown}\n![](https://example.com/x.jpg)';
    final disk = toBacklogImagePaths(text);
    expect(disk, contains('![]($kBacklogImagesRoot/$rel)'));
    expect(disk, isNot(contains(kDufsBaseUrl)));
    expect(fromBacklogImagePaths(disk), text);
  });

  test('a bare path outside an image link is left alone', () {
    const text = 'see $kBacklogImagesRoot/$rel';
    expect(fromBacklogImagePaths(text), text);
  });
}
