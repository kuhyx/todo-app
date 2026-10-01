import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:todo/desktop/wrapper_attachment_serving.dart';

void main() {
  test('script-free types are inline, everything else downloads', () {
    const inline = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'bmp': 'image/bmp',
      'pdf': 'application/pdf',
      'txt': 'text/plain',
      'md': 'text/plain',
      'log': 'text/plain',
      'csv': 'text/plain',
      'mp4': 'video/mp4',
      'm4v': 'video/mp4',
      'webm': 'video/webm',
      'ogv': 'video/ogg',
      'mov': 'video/quicktime',
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
      'ogg': 'audio/ogg',
      'oga': 'audio/ogg',
      'opus': 'audio/ogg',
      'wav': 'audio/wav',
      'flac': 'audio/flac',
    };
    inline.forEach((extension, mime) {
      final kind = attachmentContentType(extension);
      expect(kind.type.mimeType, mime, reason: extension);
      expect(kind.inline, isTrue, reason: extension);
    });
    expect(attachmentContentType('txt').type.charset, 'utf-8');
    for (final risky in ['html', 'svg', 'xhtml', 'js', 'bin', 'exe']) {
      final kind = attachmentContentType(risky);
      expect(kind.type, ContentType.binary, reason: risky);
      expect(kind.inline, isFalse, reason: risky);
    }
  });

  test('the disposition carries any name, RFC 5987 encoded', () {
    expect(
      contentDisposition('Raport (v2) zażółć*.pdf', inline: true),
      "inline; filename*=UTF-8''Raport%20%28v2%29%20za%C5%BC%C3%B3%C5%82%C4%87%2A.pdf",
    );
    expect(
      contentDisposition("it's.html", inline: false),
      "attachment; filename*=UTF-8''it%27s.html",
    );
  });

  test('parseByteRange reads one range within the file', () {
    expect(parseByteRange('bytes=0-9', 100), (0, 9));
    expect(parseByteRange('bytes=5-', 10), (5, 9));
    expect(parseByteRange('bytes=5-100', 10), (5, 9));
    expect(parseByteRange('bytes=-3', 10), (7, 9));
    expect(parseByteRange('bytes=-100', 10), (0, 9));
    expect(parseByteRange(' bytes=1-1 ', 10), (1, 1));
  });

  test('parseByteRange refuses what it cannot serve', () {
    for (final header in [
      'bytes=10-',
      'bytes=5-2',
      'bytes=-0',
      'bytes=-',
      'bytes=0-1,4-5',
      'items=0-1',
    ]) {
      expect(parseByteRange(header, 10), isNull, reason: header);
    }
  });
}
