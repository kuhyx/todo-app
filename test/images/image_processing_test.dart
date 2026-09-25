import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:todo/images/image_processing.dart';

/// A JPEG built in-test (the binary gate forbids committed fixtures), with
/// GPS coordinates and an EXIF rotation, like a phone photo.
Uint8List phonePhoto({int width = 4000, int height = 3000}) {
  final photo = img.Image(width: width, height: height)
    ..clear(img.ColorRgb8(200, 30, 30));
  photo.exif.imageIfd.orientation = 6;
  photo.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(52, 1);
  return img.encodeJpg(photo);
}

void main() {
  test('the fixture really carries GPS and a rotation', () {
    final exif = img.decodeJpgExif(phonePhoto(width: 40, height: 30))!;
    expect(exif.gpsIfd.isEmpty, isFalse);
    expect(exif.imageIfd.orientation, 6);
  });

  test('shrinks, applies the rotation and drops all EXIF', () async {
    final out = (await prepareImageInBackground(phonePhoto()))!;
    final back = img.decodeJpg(out)!;
    // Landscape pixels + "rotate 90" => upright portrait, long side capped.
    expect(back.width, 1920);
    expect(back.height, kMaxImageSide);
    expect(img.decodeJpgExif(out)?.isEmpty ?? true, isTrue);
  });

  test('caps a landscape image on its width', () {
    final wide = img.encodeJpg(img.Image(width: 3000, height: 1000));
    final back = img.decodeJpg(prepareImage(wide)!)!;
    expect(back.width, kMaxImageSide);
  });

  test('leaves a small image at its size', () {
    final small = img.encodePng(img.Image(width: 300, height: 200));
    final back = img.decodeJpg(prepareImage(small)!)!;
    expect((back.width, back.height), (300, 200));
  });

  test('flattens transparency onto white', () {
    final clear = img.Image(width: 8, height: 8, numChannels: 4);
    final back = img.decodeJpg(prepareImage(img.encodePng(clear))!)!;
    final pixel = back.getPixel(4, 4);
    expect([pixel.r, pixel.g, pixel.b], everyElement(greaterThan(250)));
  });

  test('non-images come back null, including ones the decoder throws on', () {
    expect(prepareImage(Uint8List.fromList([1, 2, 3])), isNull);
    expect(prepareImage(Uint8List.fromList('hello world'.codeUnits)), isNull);
    expect(prepareImage(Uint8List(0)), isNull);
  });
}
