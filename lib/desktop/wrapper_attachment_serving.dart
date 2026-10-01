/// Serving one cached attachment from the desktop wrapper, for an `<img>` in
/// the page or a file opened in a new tab.
///
/// The wrapper's origin also holds the GitHub token (localStorage) and the
/// notes (IndexedDB), so an attached `.html` or `.svg` rendered here would
/// run script with access to both. Only types that cannot script are shown
/// inline — raster images, PDF, plain text, audio and video — always with
/// `nosniff` so the browser cannot second-guess the type; everything else is
/// sent as a download.
///
/// Single byte ranges are honoured so a video can seek.
library;

import 'dart:io';

import 'package:todo/images/attachment_ref.dart';

/// The content type for an attachment with [extension], and whether it may
/// be shown inline (see the library comment).
({ContentType type, bool inline}) attachmentContentType(String extension) {
  final type = switch (extension) {
    'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
    'png' || 'gif' || 'webp' || 'bmp' => ContentType('image', extension),
    'pdf' => ContentType('application', 'pdf'),
    'txt' ||
    'md' ||
    'log' ||
    'csv' => ContentType('text', 'plain', charset: 'utf-8'),
    'mp4' || 'm4v' => ContentType('video', 'mp4'),
    'webm' => ContentType('video', 'webm'),
    'ogv' => ContentType('video', 'ogg'),
    'mov' => ContentType('video', 'quicktime'),
    'mp3' => ContentType('audio', 'mpeg'),
    'm4a' => ContentType('audio', 'mp4'),
    'ogg' || 'oga' || 'opus' => ContentType('audio', 'ogg'),
    'wav' => ContentType('audio', 'wav'),
    'flac' => ContentType('audio', 'flac'),
    _ => null,
  };
  return type == null
      ? (type: ContentType.binary, inline: false)
      : (type: type, inline: true);
}

/// `Content-Disposition` for [fileName]: RFC 6266 with an RFC 5987
/// `filename*`, so any name (spaces, Polish letters, quotes) survives.
String contentDisposition(String fileName, {required bool inline}) {
  final encoded = Uri.encodeComponent(fileName).replaceAllMapped(
    RegExp("[!'()*]"),
    (m) => '%${m[0]!.codeUnitAt(0).toRadixString(16).toUpperCase()}',
  );
  return "${inline ? 'inline' : 'attachment'}; filename*=UTF-8''$encoded";
}

/// Answers a GET or HEAD for [ref] from [file], named [fileName] when the
/// page passed one (else the stored name). 404 when it is not cached.
Future<void> serveAttachment(
  HttpRequest request,
  AttachmentRef ref,
  File file, {
  String? fileName,
}) async {
  final response = request.response;
  if (!file.existsSync()) {
    response.statusCode = HttpStatus.notFound;
    return;
  }
  final length = await file.length();
  final kind = attachmentContentType(ref.extension);
  response.headers
    ..contentType = kind.type
    ..set('x-content-type-options', 'nosniff')
    ..set(HttpHeaders.acceptRangesHeader, 'bytes')
    ..set(
      'content-disposition',
      contentDisposition(fileName ?? ref.file, inline: kind.inline),
    )
    // The name is a fresh uuid per attachment, so the bytes never change.
    ..set(HttpHeaders.cacheControlHeader, 'private, max-age=31536000');
  var start = 0;
  var end = length - 1;
  final range = request.headers.value(HttpHeaders.rangeHeader);
  if (range != null) {
    final parsed = parseByteRange(range, length);
    if (parsed == null) {
      response
        ..statusCode = HttpStatus.requestedRangeNotSatisfiable
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
      return;
    }
    (start, end) = parsed;
    response
      ..statusCode = HttpStatus.partialContent
      ..headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-$end/$length',
      );
  }
  response.contentLength = length == 0 ? 0 : end - start + 1;
  if (request.method == 'HEAD' || length == 0) return;
  // A client leaving mid-body (a video seek abandons its old range) does not
  // throw here: dart:io absorbs it and the stream just stops being read.
  await response.addStream(file.openRead(start, end + 1));
}

/// The inclusive byte range a single-range `Range` header asks for within
/// [length] bytes, or null when it is malformed, multi-range or outside the
/// file.
(int, int)? parseByteRange(String header, int length) {
  final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
  if (match == null) return null;
  final first = int.tryParse(match[1]!);
  final last = int.tryParse(match[2]!);
  final int start;
  final int end;
  if (first == null) {
    // `bytes=-N`: the final N bytes.
    if (last == null || last == 0) return null;
    start = last >= length ? 0 : length - last;
    end = length - 1;
  } else {
    start = first;
    end = last == null || last >= length ? length - 1 : last;
  }
  if (start >= length || start > end) return null;
  return (start, end);
}
