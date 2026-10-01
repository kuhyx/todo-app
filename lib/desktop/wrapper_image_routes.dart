/// The desktop wrapper's `/images/*` routes: the web page's only way to
/// store, show and sync attachments (images and any other file).
///
/// The page never talks to dufs itself. That keeps the dufs password out of
/// the browser, needs no CORS on dufs, and gives the desktop the same offline
/// store the phone has (an [ImageCacheStore] on disk). Same-origin with the
/// page, so an `<img src="/images/…">` just works.
///
/// * `POST /images/attach?note=<noteId>&name=<file name>` — a picked or
///   dropped file of any size, streamed to disk; stored as a re-encoded image
///   when it is one, byte-for-byte otherwise. Answers with the [Attachment].
/// * `POST /images/<noteId>/<uuid>.jpg` — raw bytes of a pasted image;
///   re-encoded here (the page must not decode on its UI thread), stored,
///   queued. 415 when the bytes are not an image.
/// * `GET|HEAD /images/<noteId>/<uuid>.<ext>[?name=<file name>]` — the cached
///   file (see `wrapper_attachment_serving.dart`), 404 when absent.
/// * `POST /images/reconcile` — `{"refs": ["<noteId>/<uuid>.<ext>", …]}`:
///   every attachment the notes link to. Uploads the queue, fetches what is
///   missing, evicts the rest; answers with the [ReconcileReport].
/// * `GET  /images/status` — `{"configured": bool, "pending": n}`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:todo/desktop/dufs_login_env.dart';
import 'package:todo/desktop/wrapper_attachment_serving.dart';
import 'package:todo/desktop/wrapper_paths.dart';
import 'package:todo/images/attachment_ingest.dart';
import 'package:todo/images/attachment_ref.dart';
import 'package:todo/images/dufs_image_client.dart';
import 'package:todo/images/image_cache_store.dart';
import 'package:todo/images/image_processing.dart';

/// The routes the real wrapper uses: cache under
/// `~/.local/share/todo-desktop/images`, login from `todo.env`.
WrapperImageRoutes defaultWrapperImageRoutes(String home) => WrapperImageRoutes(
  store: ImageCacheStore(Directory(defaultImageCachePath(home))),
  loginEnvPath: defaultDufsLoginEnvPath(home),
);

/// Handles `/images/*` for the wrapper.
class WrapperImageRoutes {
  /// Creates the routes over [store], reading the dufs login from
  /// [loginEnvPath]. [httpClient] and [prepare] are injectable for tests.
  WrapperImageRoutes({
    required this.store,
    required this.loginEnvPath,
    http.Client Function()? httpClient,
    Future<Uint8List?> Function(Uint8List)? prepare,
  }) : _httpClient = httpClient ?? http.Client.new,
       _prepare = prepare ?? prepareImageInBackground,
       _ingest = AttachmentIngest(
         store,
         prepare: prepare ?? prepareImageInBackground,
       );

  /// The on-disk attachment cache and upload queue.
  final ImageCacheStore store;

  /// `todo.env` written by `add_dufs_login.sh`.
  final String loginEnvPath;

  final http.Client Function() _httpClient;
  final Future<Uint8List?> Function(Uint8List) _prepare;
  final AttachmentIngest _ingest;

  /// Every path these routes answer starts with this.
  static const prefix = '/images/';

  /// Answers [request] and returns true when it is an `/images/` route.
  Future<bool> handle(HttpRequest request) async {
    final path = request.uri.path;
    if (!path.startsWith(prefix)) return false;
    final rest = path.substring(prefix.length);
    final response = request.response;
    final method = request.method;
    if (rest == 'attach' && method == 'POST') {
      await _attach(request);
    } else if (rest == 'reconcile' && method == 'POST') {
      await _reconcile(request);
    } else if (rest == 'status' && method == 'GET') {
      _json(response, {
        'configured': _login() != null,
        'pending': store.pending().length,
      });
    } else if (AttachmentRef.tryParse(rest) case final ref?) {
      if (method == 'GET' || method == 'HEAD') {
        await serveAttachment(
          request,
          ref,
          store.fileFor(ref),
          fileName: request.uri.queryParameters['name'],
        );
      } else if (method == 'POST' && ref.extension == 'jpg') {
        await _put(request, ref);
      } else {
        response.statusCode = HttpStatus.methodNotAllowed;
      }
    } else {
      response.statusCode = HttpStatus.notFound;
    }
    return true;
  }

  DufsLogin? _login() => readDufsLoginEnv(File(loginEnvPath));

  Future<void> _attach(HttpRequest request) async {
    final query = request.uri.queryParameters;
    final noteId = query['note'] ?? '';
    final response = request.response;
    if (!isSafeNoteId(noteId)) {
      // Read the body anyway: answering mid-upload looks like a dropped
      // connection to the browser, not a 400.
      await request.drain<void>();
      response.statusCode = HttpStatus.badRequest;
      return;
    }
    try {
      final attachment = await _ingest.fromStream(
        noteId,
        query['name'] ?? '',
        request,
      );
      _json(response, attachment.toJson());
    } on FileSystemException catch (e) {
      response
        ..statusCode = HttpStatus.internalServerError
        ..write(e.message);
    }
  }

  Future<void> _put(HttpRequest request, AttachmentRef ref) async {
    final builder = BytesBuilder(copy: false);
    var tooLarge = false;
    // Read to the end even once over the cap: answering while the browser
    // is still sending makes it see a dropped connection, not the 413.
    await for (final chunk in request) {
      tooLarge =
          tooLarge || builder.length + chunk.length > kMaxImageDecodeBytes;
      if (!tooLarge) builder.add(chunk);
    }
    if (tooLarge) {
      request.response.statusCode = HttpStatus.requestEntityTooLarge;
      return;
    }
    final jpeg = await _prepare(builder.takeBytes());
    if (jpeg == null) {
      request.response.statusCode = HttpStatus.unsupportedMediaType;
      return;
    }
    await store.put(ref, jpeg);
    request.response.statusCode = HttpStatus.noContent;
  }

  Future<void> _reconcile(HttpRequest request) async {
    final Set<AttachmentRef> refs;
    try {
      final body = jsonDecode(await utf8.decodeStream(request));
      refs = {
        for (final raw in (body as Map<String, dynamic>)['refs'] as List)
          ?AttachmentRef.tryParse(raw as String),
      };
    } on Object {
      request.response.statusCode = HttpStatus.badRequest;
      return;
    }
    final login = _login();
    final client = login == null
        ? null
        : DufsImageClient(login, httpClient: _httpClient());
    try {
      _json(request.response, (await store.reconcile(refs, client)).toJson());
    } finally {
      client?.close();
    }
  }

  void _json(HttpResponse response, Object body) {
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
  }
}
