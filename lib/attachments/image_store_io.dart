/// Android: images live in app storage and sync with dufs directly.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:todo/attachments/image_password_store.dart';
import 'package:todo/attachments/image_store_api.dart';
import 'package:todo/images/dufs_image_client.dart';
import 'package:todo/images/image_cache_store.dart';
import 'package:todo/images/image_processing.dart';
import 'package:todo/images/image_ref.dart';

/// Opens the store under the app-support directory's `images/`.
// coverage:ignore-start
// Platform wiring only: path_provider has no binding in unit tests, which
// construct [IoImageStore] over a temp directory instead.
Future<ImageStore> openImageStore() async {
  final support = await getApplicationSupportDirectory();
  final root = Directory(p.join(support.path, 'images'));
  return IoImageStore(ImageCacheStore(root));
}
// coverage:ignore-end

/// [ImageStore] over a local [ImageCacheStore], uploading with the login
/// from [ImagePasswordStore].
class IoImageStore extends ImageStore {
  /// Creates a store over [cache]; the rest is injectable for tests.
  IoImageStore(
    this.cache, {
    this._passwords = const ImagePasswordStore(),
    http.Client Function()? httpClient,
    Future<Uint8List?> Function(Uint8List)? prepare,
  }) : _httpClient = httpClient ?? http.Client.new,
       _prepare = prepare ?? prepareImageInBackground;

  /// The on-device images and upload queue.
  final ImageCacheStore cache;

  final ImagePasswordStore _passwords;
  final http.Client Function() _httpClient;
  final Future<Uint8List?> Function(Uint8List) _prepare;

  @override
  Future<ImageRef?> attach(String noteId, Uint8List bytes) async {
    final jpeg = await _prepare(bytes);
    if (jpeg == null) return null;
    final ref = ImageRef.create(noteId);
    try {
      await cache.put(ref, jpeg);
    } on FileSystemException catch (e) {
      throw ImageStoreException('Could not save the image: ${e.message}');
    }
    notifyListeners();
    // Upload right away when online. An empty ref set never evicts, so this
    // cannot race the link reaching the note.
    unawaited(_sync(const {}));
    return ref;
  }

  @override
  Future<void> reconcile(Iterable<String> noteTexts) =>
      _sync(imageRefsAcross(noteTexts));

  Future<void> _sync(Set<ImageRef> refs) async {
    final login = await _passwords.login();
    final client = login == null
        ? null
        : DufsImageClient(login, httpClient: _httpClient());
    try {
      final report = await cache.reconcile(refs, client);
      if (report.uploaded + report.downloaded + report.evicted > 0) {
        notifyListeners();
      }
    } finally {
      client?.close();
    }
  }

  @override
  ImageSource sourceFor(ImageRef ref) {
    final file = cache.fileFor(ref);
    return file.existsSync()
        ? LocalImageSource(file.path)
        : const MissingImageSource();
  }

  @override
  bool isPending(ImageRef ref) => cache.isPending(ref);

  @override
  Future<ImageStoreStatus> status() async => ImageStoreStatus(
    configured: await _passwords.login() != null,
    pending: cache.pending().length,
  );
}
