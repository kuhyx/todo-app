import 'package:flutter_test/flutter_test.dart';
import 'package:todo/images/attachment_links.dart';
import 'package:todo/images/attachment_ref.dart';

void main() {
  final image = AttachmentRef.tryParse('n1/a.jpg')!;
  final pdf = AttachmentRef.tryParse('n1/b.pdf')!;
  final other = AttachmentRef.create('n2');

  test('attachmentsIn finds images and files, in order, each once', () {
    final text =
        'hi ${image.imageMarkdown} and\n${pdf.fileMarkdown('b.pdf')}\n'
        '${other.imageMarkdown}\n${image.imageMarkdown}\n'
        '![x](https://example.com/a.jpg) [y]($kDufsBaseUrl/Keepass/a.pdf)';
    final found = attachmentsIn(text);
    expect([for (final a in found) a.ref], [image, pdf, other]);
    expect([for (final a in found) a.isImage], [true, false, true]);
    expect(found[1].name, 'b.pdf');
    expect(attachmentsIn('no attachments'), isEmpty);
  });

  test('an image link is never also read as a file link', () {
    final found = attachmentsIn(image.imageMarkdown);
    expect(found, hasLength(1));
    expect(found.single.isImage, isTrue);
  });

  test('attachmentRefsIn covers both kinds', () {
    expect(
      attachmentRefsIn('${image.imageMarkdown}\n${pdf.fileMarkdown('b')}'),
      {image, pdf},
    );
  });

  test('attachmentOfLine only matches a line that is just one link', () {
    expect(attachmentOfLine('  ${image.imageMarkdown}  ')!.ref, image);
    expect(attachmentOfLine('![alt text](${image.url})')!.name, 'alt text');
    final file = attachmentOfLine(pdf.fileMarkdown('Raport.pdf'))!;
    expect(file.ref, pdf);
    expect(file.isImage, isFalse);
    expect(file.name, 'Raport.pdf');
    expect(attachmentOfLine('see ${image.imageMarkdown}'), isNull);
    expect(attachmentOfLine('plain'), isNull);
  });

  test('backlog paths round-trip exactly, images and files alike', () {
    final text =
        'a\n${image.imageMarkdown}\n${pdf.fileMarkdown('b.pdf')}\n'
        '![](https://example.com/x.jpg)';
    final disk = toBacklogAttachmentPaths(text);
    expect(disk, contains('![]($kBacklogImagesRoot/n1/a.jpg)'));
    expect(disk, contains('[b.pdf]($kBacklogImagesRoot/n1/b.pdf)'));
    expect(disk, isNot(contains('$kDufsBaseUrl/$kImagesDir')));
    expect(fromBacklogAttachmentPaths(disk), text);
  });

  test('a bare path outside a link is left alone', () {
    const text = 'see $kBacklogImagesRoot/n1/b.pdf';
    expect(fromBacklogAttachmentPaths(text), text);
  });
}
