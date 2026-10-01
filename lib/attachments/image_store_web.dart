/// Desktop (web build): every attachment operation goes through the local
/// wrapper's `/images/*` routes; the page never sees the dufs password.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:todo/attachments/file_post.dart' as file_post;
import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/images/attachment_ref.dart';
import 'package:todo/sync/desktop_wrapper.dart';

/// Opens the store against the wrapper that served this page.
Future<ImageStore> openImageStore() async =>
    WebImageStore(origin: servingWrapperOrigin());

/// Sends a file to the wrapper and returns its answer; injectable for tests.
typedef FilePost =
    Future<({int status, String body})> Function(Uri url, XFile file);

/// [ImageStore] backed by the desktop wrapper at [origin].
class WebImageStore extends ImageStore {
  /// Creates a store talking to [origin]; [httpClient] and [postFile] are
  /// injectable.
  WebImageStore({
    required this.origin,
    http.Client? httpClient,
    FilePost? postFile,
  }) : _http = httpClient ?? http.Client(),
       _postFile = postFile ?? file_post.postFile;

  /// The wrapper's origin, e.g. `http://localhost:8730`.
  final String origin;

  final http.Client _http;
  final FilePost _postFile;

  // Sizes the wrapper reported. A ref's bytes never change (a fresh uuid per
  // attachment), so a known size never goes stale.
  final Map<AttachmentRef, int> _sizes = {};

  // Bumped whenever the wrapper may hold new bytes, so an image that failed
  // to load (not downloaded yet) is requested again under a fresh URL.
  int _revision = 0;

  Uri _images(String rest) => Uri.parse('$origin/images/$rest');

  @override
  Future<AttachmentRef?> attach(String noteId, Uint8List bytes) async {
    final ref = AttachmentRef.create(noteId);
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
  Future<Attachment> attachFile(String noteId, XFile file) async {
    final url = _images(
      'attach',
    ).replace(queryParameters: {'note': noteId, 'name': file.name});
    final ({int status, String body}) response;
    try {
      response = await _postFile(url, file);
    } on Object {
      throw ImageStoreException(
        'The desktop helper is not running; ${file.name} was not saved',
      );
    }
    if (response.status != 200) {
      throw ImageStoreException(
        'The desktop helper refused ${file.name} (${response.status})',
      );
    }
    final attachment = Attachment.fromJson(jsonDecode(response.body));
    _revision++;
    notifyListeners();
    unawaited(_reconcile(const {}));
    return attachment;
  }

  @override
  Future<void> reconcile(Iterable<String> noteTexts) =>
      _reconcile(attachmentRefsAcross(noteTexts));

  Future<void> _reconcile(Set<AttachmentRef> refs) async {
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
  ImageSource sourceFor(AttachmentRef ref) =>
      NetworkImageSource('$origin/images/${ref.relativePath}?r=$_revision');

  @override
  bool isPending(AttachmentRef ref) => false;

  @override
  Future<int?> sizeOf(AttachmentRef ref) async {
    if (_sizes[ref] case final known?) return known;
    try {
      final response = await _http.head(_images(ref.relativePath));
      final length = response.statusCode == 200
          ? int.tryParse(response.headers['content-length'] ?? '')
          : null;
      if (length != null) _sizes[ref] = length;
      return length;
    } on Exception {
      return null;
    }
  }

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
