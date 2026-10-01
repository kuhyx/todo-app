import 'package:flutter_test/flutter_test.dart';
import 'package:todo/images/attachment_ref.dart';

void main() {
  const rel = 'note-1/0815ff8a-203e-4f54-9cc5-8a58b27982ec.jpg';
  final ref = AttachmentRef.tryParse(rel)!;

  test('a ref exposes its parts, url and markdown', () {
    expect(ref.noteId, 'note-1');
    expect(ref.file, '0815ff8a-203e-4f54-9cc5-8a58b27982ec.jpg');
    expect(ref.extension, 'jpg');
    expect(ref.relativePath, rel);
    expect(ref.url, '$kDufsBaseUrl/$kImagesDir/$rel');
    expect(ref.imageMarkdown, '![](${ref.url})');
    expect(ref.fileMarkdown('a.pdf'), '[a.pdf](${ref.url})');
  });

  test('create files a fresh uuid jpg under the note', () {
    final a = AttachmentRef.create('n1');
    final b = AttachmentRef.create('n1');
    expect(a.noteId, 'n1');
    expect(a.file, endsWith('.jpg'));
    expect(a, isNot(b));
  });

  test('forFile keeps a plain extension, else falls back to bin', () {
    expect(AttachmentRef.forFile('n1', 'Report.PDF').extension, 'pdf');
    expect(AttachmentRef.forFile('n1', 'a.tar.gz').extension, 'gz');
    for (final name in ['README', '.bashrc', 'x.', 'a.verylongextension']) {
      expect(AttachmentRef.forFile('n1', name).extension, 'bin', reason: name);
    }
    expect(
      AttachmentRef.forFile('n1', 'a.pdf'),
      isNot(AttachmentRef.forFile('n1', 'a.pdf')),
    );
  });

  test('create and forFile refuse an unsafe note id', () {
    expect(() => AttachmentRef.create('../x'), throwsArgumentError);
    expect(() => AttachmentRef.forFile('a/b', 'x.pdf'), throwsArgumentError);
    expect(isSafeNoteId('note-1_A'), isTrue);
    expect(isSafeNoteId('../x'), isFalse);
    expect(isSafeNoteId(''), isFalse);
  });

  test('tryParse takes any short extension but rejects unsafe paths', () {
    expect(AttachmentRef.tryParse('a/b.png'), isNotNull);
    expect(AttachmentRef.tryParse('a/b.mp4'), isNotNull);
    for (final bad in [
      '../x/y.jpg',
      'a/../b.jpg',
      'a/b/c.jpg',
      'a/.jpg',
      '/a/b.jpg',
      'a b/c.jpg',
      'a/b.jpg.pending',
      'a/b.pdf.tmp',
      'a/b.PDF',
      'a/b',
    ]) {
      expect(AttachmentRef.tryParse(bad), isNull, reason: bad);
    }
  });

  test('refs compare by path, so sets dedupe', () {
    expect({ref, AttachmentRef.tryParse(rel)!}, hasLength(1));
  });

  test('linkLabel keeps a name readable but unable to break the link', () {
    expect(linkLabel('Raport [final].pdf'), 'Raport (final).pdf');
    expect(linkLabel('two\r\nlines.txt'), 'two lines.txt');
    expect(linkLabel('  '), 'file');
  });

  group('Attachment', () {
    final file = AttachmentRef.tryParse('n1/b.pdf')!;

    test('markdown is an image line or a named file link', () {
      expect(
        Attachment(ref: ref, name: 'x.png', isImage: true).markdown,
        ref.imageMarkdown,
      );
      expect(
        Attachment(ref: file, name: 'a].pdf', isImage: false).markdown,
        '[a).pdf](${file.url})',
      );
    });

    test('round-trips through JSON', () {
      final attachment = Attachment(ref: file, name: 'a.pdf', isImage: false);
      final back = Attachment.fromJson(attachment.toJson());
      expect(back.ref, file);
      expect(back.name, 'a.pdf');
      expect(back.isImage, isFalse);
    });

    test('fromJson rejects anything else', () {
      for (final bad in <Object?>[
        null,
        'x',
        {'ref': '../x.pdf', 'name': 'a', 'image': false},
        {'ref': 'n1/b.pdf', 'name': 'a'},
      ]) {
        expect(() => Attachment.fromJson(bad), throwsFormatException);
      }
    });
  });
}
