/// Desktop (web build): every image operation goes through the local
/// wrapper's `/images/*` routes; the page never sees the dufs password.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/images/image_ref.dart';
import 'package:todo/sync/desktop_wrapper.dart';

/// Opens the store against the wrapper that served this page.
Future<ImageStore> openImageStore() async =>
    WebImageStore(origin: servingWrapperOrigin());

/// [ImageStore] backed by the desktop wrapper at [origin].
class WebImageStore extends ImageStore {
  /// Creates a store talking to [origin]; [httpClient] is injectable.
  WebImageStore({required this.origin, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  /// The wrapper's origin, e.g. `http://localhost:8730`.
  final String origin;

  final http.Client _http;

  // Bumped whenever the wrapper may hold new bytes, so an image that failed
  // to load (not downloaded yet) is requested again under a fresh URL.
  int _revision = 0;

  Uri _images(String rest) => Uri.parse('$origin/images/$rest');

  @override
  Future<ImageRef?> attach(String noteId, Uint8List bytes) async {
    final ref = ImageRef.create(noteId);
    final http.Response response;
    try {
      response = await _http.post(_images(ref.relativePath), body: bytes);
    } on Exception {
      throw const ImageStoreException(
        'The desktop helper is not running; the image was not saved',
      );
    }
    if (response.statusCode == 415) return null;
    if (response.statusCode != 204) {
      throw ImageStoreException(
        'The desktop helper refused the image (${response.statusCode})',
      );
    }
    _revision++;
    notifyListeners();
    unawaited(_reconcile(const {}));
    return ref;
  }

  @override
  Future<void> reconcile(Iterable<String> noteTexts) =>
      _reconcile(imageRefsAcross(noteTexts));

  Future<void> _reconcile(Set<ImageRef> refs) async {
    try {
      final response = await _http.post(
        _images('reconcile'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'refs': [for (final ref in refs) ref.relativePath],
        }),
      );
      if (response.statusCode != 200) return;
      final report = jsonDecode(response.body) as Map<String, dynamic>;
      if ((report['downloaded'] as int? ?? 0) > 0) {
        _revision++;
        notifyListeners();
      }
    } on Exception {
      // Best-effort: the next sync, resume or attach reconciles again.
    }
  }

  @override
  ImageSource sourceFor(ImageRef ref) =>
      NetworkImageSource('$origin/images/${ref.relativePath}?r=$_revision');

  @override
  bool isPending(ImageRef ref) => false;

  @override
  Future<ImageStoreStatus> status() async {
    try {
      final response = await _http.get(_images('status'));
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ImageStoreStatus(
        configured: body['configured'] as bool? ?? false,
        pending: body['pending'] as int? ?? 0,
      );
    } on Exception {
      return const ImageStoreStatus(configured: false, pending: 0);
    }
  }
}
