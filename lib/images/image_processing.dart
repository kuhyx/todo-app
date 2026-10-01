/// Shrinks a picked or pasted image to what a note needs, before it is stored
/// or uploaded.
///
/// Phone photos are 3–8 MB with GPS coordinates in their EXIF. Every image is
/// re-encoded here: the recorded rotation is applied to the pixels first (so
/// dropping EXIF does not leave a portrait photo lying on its side), the long
/// side is capped at [kMaxImageSide], and the result is a JPEG with no
/// metadata at all.
///
/// Pure Dart (`package:image`), so the Android app and the desktop wrapper
/// run the same code; the web page never decodes images, it hands the raw
/// bytes to the wrapper.
library;

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Longest side, in pixels, of a stored image.
const kMaxImageSide = 2560;

/// JPEG quality of a stored image.
const kJpegQuality = 85;

/// Largest attachment still tried as an image (a raw 50 MP phone photo is
/// ~25 MB). Anything bigger is kept as a file: decoding it would need several
/// times its size in memory.
const int kMaxImageDecodeBytes = 64 * 1024 * 1024;

/// How many leading bytes [looksLikeImage] needs.
const kImageSniffBytes = 12;

/// Whether [head] starts like a photo or screenshot format: JPEG, PNG, GIF,
/// WebP, BMP or TIFF.
///
/// Only these are re-encoded. `package:image` also decodes PSD, TGA, EXR and
/// ICO, but flattening those to a JPEG would destroy what they were attached
/// for, so they stay files.
bool looksLikeImage(List<int> head) {
  bool starts(List<int> magic, [int at = 0]) {
    if (head.length < at + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (head[at + i] != magic[i]) return false;
    }
    return true;
  }

  const riff = [0x52, 0x49, 0x46, 0x46];
  const webp = [0x57, 0x45, 0x42, 0x50];
  return starts(const [0xFF, 0xD8, 0xFF]) ||
      starts(const [0x89, 0x50, 0x4E, 0x47]) ||
      starts(const [0x47, 0x49, 0x46, 0x38]) ||
      (starts(riff) && starts(webp, 8)) ||
      starts(const [0x42, 0x4D]) ||
      starts(const [0x49, 0x49, 0x2A, 0x00]) ||
      starts(const [0x4D, 0x4D, 0x00, 0x2A]);
}

/// Re-encodes [bytes] as a metadata-free JPEG no larger than [kMaxImageSide]
/// on its long side, or returns null when [bytes] is not a decodable image.
Uint8List? prepareImage(Uint8List bytes) {
  final decoded = _decode(bytes);
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  final longSide = math.max(image.width, image.height);
  if (longSide > kMaxImageSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: kMaxImageSide)
        : img.copyResize(image, height: kMaxImageSide);
  }
  if (image.hasAlpha) image = _flattenOntoWhite(image);
  image.exif = img.ExifData();
  return img.encodeJpg(image, quality: kJpegQuality);
}

/// [prepareImage] off the calling isolate: decoding a 12 MP photo takes long
/// enough to drop frames if it runs on the UI isolate.
Future<Uint8List?> prepareImageInBackground(Uint8List bytes) =>
    Isolate.run(() => prepareImage(bytes));

/// `decodeImage` returns null for most non-images but *throws* (a
/// RangeError from its PSD sniffer, seen on a 3-byte input) for others; both
/// mean "not an image" here.
img.Image? _decode(Uint8List bytes) {
  try {
    return img.decodeImage(bytes);
  } on Object {
    return null;
  }
}

/// JPEG has no alpha: without this a transparent screenshot's clear pixels
/// come out as whatever colour their RGB happened to hold, usually black.
img.Image _flattenOntoWhite(img.Image image) {
  final background = img.Image(width: image.width, height: image.height)
    ..clear(img.ColorRgb8(255, 255, 255));
  return img.compositeImage(background, image);
}
