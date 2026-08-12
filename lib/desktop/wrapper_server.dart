import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crdt_sync/crdt_sync.dart';
import 'package:path/path.dart' as p;

/// Route serving `todo`'s own seeded Firebase session (a `FirebaseCredentials`
/// JSON blob), alongside [kSyncAccountPath]'s email/password pair.
///
/// `todo`-local rather than added to `crdt_sync_dart`: no other app in the
/// fleet runs a desktop wrapper of its own, so a shared route would add
/// surface area five other apps never use. Gated by the same
/// [kSyncAccountEnvVar] as [kSyncAccountPath].
const kSyncCredentialsPath = '/sync-credentials';

/// Local HTTP server backing the desktop app.
///
/// The desktop app is a Flutter **web** build (Flutter's Linux embedder manages
/// only ~20fps at 4K — see `docs/desktop-performance-findings.md`), so it runs
/// in a browser and cannot touch the filesystem. This process is the other half
/// of the desktop app: it serves the build and owns the two files a browser
/// cannot write.
///
/// * `~/todo/BACKLOG.md` — the canonical backlog path the user's tooling and
///   the `todo` MCP server read.
/// * a copy of the note log — so a wiped Chrome profile is not a total-loss
///   event for notes that have not yet synced to GitHub.
///
/// Binds to loopback only. The endpoints read and overwrite files in the user's
/// home directory with no authentication, so exposing them on a routable
/// address would let anything on the network rewrite the backlog.
class WrapperServer {
  /// Creates a server serving [webRoot] and persisting under [backlogPath] and
  /// [logPath].
  WrapperServer({
    required this.webRoot,
    required this.backlogPath,
    required this.logPath,
    bool? serveSyncAccount,
    String? syncConfigDir,
    String? todoCredentialsPath,
  }) : serveSyncAccount =
           serveSyncAccount ??
           (Platform.environment[kSyncAccountEnvVar] ?? '').isNotEmpty,
       syncConfigDir =
           syncConfigDir ??
           p.join(Platform.environment['HOME'] ?? '', '.config', 'crdt-sync'),
       todoCredentialsPath =
           todoCredentialsPath ??
           p.join(
             Platform.environment['HOME'] ?? '',
             '.config',
             'todo',
             'firebase_auth.json',
           );

  /// Whether the sync-account route answers; off unless explicitly enabled.
  final bool serveSyncAccount;

  /// Directory holding `firebase.json` and `password`.
  final String syncConfigDir;

  /// Whether [kSyncCredentialsPath] has served a valid credential yet.
  ///
  /// Flips to true after the first 200 and 404s every request after that,
  /// so a normal launch can self-provision with no env var to remember (see
  /// [_syncCredentials]) while the exposure window for a database-write
  /// credential stays "until the app finishes booting" rather than "for as
  /// long as the wrapper process runs". Independent of [serveSyncAccount]:
  /// that gate protects the legacy shared `/sync-account` route other apps'
  /// wrappers also serve, which stays opt-in.
  bool _todoCredentialsServed = false;

  /// `todo`'s own seeded Firebase session, written by
  /// `crdt-sync/tool/seed_session.py --app todo` in the same
  /// `{id_token, refresh_token, expires_at}` shape every other app's
  /// credential cache uses. The account's password grant is retired
  /// fleet-wide (see `link_google.py`/`seed_session.py`), so unlike
  /// [syncConfigDir]'s `password` file this is the only thing that actually
  /// authenticates.
  final String todoCredentialsPath;

  /// Directory holding the built Flutter web assets.
  final String webRoot;

  /// Absolute path of the Markdown backlog export.
  final String backlogPath;

  /// Absolute path of the on-disk note-log copy.
  final String logPath;

  HttpServer? _server;

  /// Port the server is listening on, once [start] has completed.
  int get port => _server!.port;

  /// Binds to loopback on [requestedPort] and begins serving.
  ///
  /// Pass 0 to let the OS choose a port (tests do this); the desktop launcher
  /// passes the fixed port, because the browser keys `localStorage` (the GitHub
  /// token) and IndexedDB (the notes) by origin — a changing port would
  /// silently hide both.
  Future<void> start(int requestedPort) async {
    _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      requestedPort,
    );
    unawaited(_serve(_server!));
  }

  /// Stops serving and releases the port.
  Future<void> stop() async => _server?.close(force: true);

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      try {
        await _handle(request);
      } on Exception {
        request.response.statusCode = HttpStatus.internalServerError;
      }
      await request.response.close();
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (path == '/backup/backlog') {
      return _file(request, backlogPath);
    }
    if (path == '/backup/log') {
      return _file(request, logPath);
    }
    if (path == kSyncAccountPath) {
      return _syncAccount(request);
    }
    if (path == kSyncCredentialsPath) {
      return _syncCredentials(request);
    }
    return _static(request, path);
  }

  /// Serves the shared sync account so a desktop install can self-provision.
  ///
  /// Off unless CRDT_SYNC_SERVE_ACCOUNT is set: this hands out a credential
  /// with database write access to anything that can reach the port, so it is
  /// something you switch on once to set an install up, not a standing route.
  /// 404 (rather than 403) when disabled, so a probe cannot tell the route
  /// exists.
  ///
  /// The account is read from the same ~/.config/crdt-sync/ pair the Python
  /// daemons already use, so there is one source of truth per machine rather
  /// than a per-app copy.
  Future<void> _syncAccount(HttpRequest request) async {
    if (!serveSyncAccount) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    final configFile = File(p.join(syncConfigDir, 'firebase.json'));
    final passwordFile = File(p.join(syncConfigDir, 'password'));
    if (!configFile.existsSync() || !passwordFile.existsSync()) {
      stderr.writeln(
        'Sync account requested but ~/.config/crdt-sync/ is incomplete — '
        'the desktop app will keep asking for credentials.',
      );
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    final email =
        (jsonDecode(await configFile.readAsString())
            as Map<String, dynamic>)['email'];
    if (email is! String || email.isEmpty) {
      stderr.writeln('firebase.json has no usable "email" — not serving it.');
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'email': email,
        'password': (await passwordFile.readAsString()).trim(),
      }),
    );
  }

  /// Serves `todo`'s own seeded Firebase session, so a fresh desktop install
  /// can authenticate without ever seeing a password field and without a
  /// human setting an env var first.
  ///
  /// Reachable by default (unlike [_syncAccount], which stays behind
  /// [serveSyncAccount]/[kSyncAccountEnvVar]) but only until the first
  /// successful serve: this hands out a credential with database write
  /// access to anything that can reach the port, shared with five other
  /// apps, so the window it is actually reachable in must be as small as
  /// "until the app finishes booting", not "for as long as the wrapper
  /// runs". 404 (not 403) both when already served and when disabled, so a
  /// probe cannot tell which case it hit.
  ///
  /// Consumed once by `loadAccount()`'s wrapper fallback and written
  /// straight into the keystore; never a standing source the app re-reads on
  /// every launch. That matters here specifically: `seed_session.py` may
  /// later rotate this file's refresh token for an unrelated app's re-seed
  /// run, and Firebase invalidates the previous token when it does --
  /// serving a stale token to a device that already adopted the live one
  /// would just hand back a token neither side can use.
  Future<void> _syncCredentials(HttpRequest request) async {
    if (_todoCredentialsServed) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    final credentialsFile = File(todoCredentialsPath);
    if (!credentialsFile.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    final Map<String, dynamic> credentials;
    try {
      credentials =
          jsonDecode(await credentialsFile.readAsString())
              as Map<String, dynamic>;
    } on FormatException {
      stderr.writeln(
        '$todoCredentialsPath is not valid JSON — not serving it.',
      );
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    if (credentials['id_token'] is! String ||
        credentials['refresh_token'] is! String ||
        credentials['expires_at'] is! String) {
      stderr.writeln(
        '$todoCredentialsPath is missing id_token/refresh_token/expires_at '
        '— not serving it.',
      );
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    // The email is a display nicety (so Settings shows an address instead of
    // a blank), not a credential -- read from the shared config, not from
    // todoCredentialsPath, which has no email field of its own.
    String? email;
    final configFile = File(p.join(syncConfigDir, 'firebase.json'));
    if (configFile.existsSync()) {
      final config =
          jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
      final configEmail = config['email'];
      if (configEmail is String && configEmail.isNotEmpty) {
        email = configEmail;
      }
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({...credentials, 'email': email}));
    // After, not before writing the response: a request that fails partway
    // through must remain retryable rather than burning the one serve.
    _todoCredentialsServed = true;
  }

  /// GET returns the file's contents (404 when absent); POST overwrites it.
  Future<void> _file(HttpRequest request, String filePath) async {
    final file = File(filePath);
    if (request.method == 'POST') {
      await file.parent.create(recursive: true);
      await file.writeAsString(await utf8.decodeStream(request));
      request.response.statusCode = HttpStatus.noContent;
      return;
    }
    if (request.method != 'GET') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      return;
    }
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    request.response.headers.contentType = ContentType.text;
    request.response.write(await file.readAsString());
  }

  Future<void> _static(HttpRequest request, String path) async {
    final relative = path == '/' ? 'index.html' : path.substring(1);
    // Reject traversal before touching the filesystem: the served root sits
    // next to the user's files, so `../` must not escape it.
    final resolved = p.normalize(p.join(webRoot, relative));
    // coverage:ignore-start
    // Defence in depth, and currently unreachable: Dart's HttpServer decodes
    // and normalises the path before a handler runs, so even `%2e%2e` arrives
    // already collapsed (verified in wrapper_server_test). Kept so the
    // guarantee does not depend on that implementation detail holding.
    if (!p.isWithin(webRoot, resolved) && resolved != p.normalize(webRoot)) {
      request.response.statusCode = HttpStatus.forbidden;
      return;
    }
    // coverage:ignore-end
    final file = File(resolved);
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      return;
    }
    request.response.headers.contentType = contentTypeFor(resolved);
    await request.response.addStream(file.openRead());
  }

  /// Content type for [filePath].
  ///
  /// Flutter web is strict here: CanvasKit refuses to instantiate a `.wasm`
  /// served as anything but `application/wasm`, and the app silently fails to
  /// render if the bootstrap `.js` is mislabelled.
  static ContentType contentTypeFor(String filePath) {
    switch (p.extension(filePath).toLowerCase()) {
      case '.html':
        return ContentType.html;
      case '.js' || '.mjs':
        return ContentType('text', 'javascript', charset: 'utf-8');
      case '.json':
        return ContentType.json;
      case '.wasm':
        return ContentType('application', 'wasm');
      case '.css':
        return ContentType('text', 'css', charset: 'utf-8');
      case '.png':
        return ContentType('image', 'png');
      case '.svg':
        return ContentType('image', 'svg+xml');
      case '.ttf':
        return ContentType('font', 'ttf');
      case '.otf':
        return ContentType('font', 'otf');
      case '.woff2':
        return ContentType('font', 'woff2');
      case '.bin' || '.symbols':
        return ContentType.binary;
      default:
        return ContentType.binary;
    }
  }
}
